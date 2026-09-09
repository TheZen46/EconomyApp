"""
QLoRA Parameter-Efficient Fine-Tuning (PEFT) Pipeline for Receipt VLM.
Optimized for 1.5B - 3B parameter Vision-Language Models (e.g. Qwen2-VL-2B / SmolVLM-Instruct).
"""

import os
import sys
import argparse
import torch
from transformers import (
    AutoProcessor,
    AutoModelForVision2Seq,
    BitsAndBytesConfig,
    TrainingArguments,
    Trainer,
)
from peft import (
    LoraConfig,
    get_peft_model,
    prepare_model_for_kbit_training,
    TaskType,
)
from dataset_loader import SpatialReceiptDataset


def parse_args():
    parser = argparse.ArgumentParser(description="Fine-tune on-device Receipt VLM via QLoRA")
    parser.add_argument("--model_id", type=str, default="Qwen/Qwen2-VL-2B-Instruct", help="HuggingFace model ID")
    parser.add_argument("--data_manifest", type=str, required=True, help="Path to training JSONL manifest")
    parser.add_argument("--image_dir", type=str, required=True, help="Path to image directory")
    parser.add_argument("--output_dir", type=str, default="./lora_receipt_vlm", help="Adapter output directory")
    parser.add_argument("--epochs", type=int, default=3, help="Training epochs")
    parser.add_argument("--batch_size", type=int, default=2, help="Per-device train batch size")
    parser.add_argument("--grad_accum", type=int, default=8, help="Gradient accumulation steps")
    parser.add_argument("--lr", type=float, default=2e-4, help="Learning rate")
    parser.add_argument("--lora_rank", type=int, default=16, help="LoRA rank dimension")
    parser.add_argument("--lora_alpha", type=int, default=32, help="LoRA alpha scaling factor")
    parser.add_argument("--lora_dropout", type=float, default=0.05, help="LoRA dropout rate")
    return parser.parse_args()


def main():
    args = parse_args()
    os.makedirs(args.output_dir, exist_ok=True)

    print(f"=== Initializing QLoRA Fine-Tuning for: {args.model_id} ===")

    # 1. 4-bit Quantization Configuration (NF4 with Double Quantization)
    bnb_config = BitsAndBytesConfig(
        load_in_4bit=True,
        bnb_4bit_quant_type="nf4",
        bnb_4bit_use_double_quant=True,
        bnb_4bit_compute_dtype=torch.bfloat16 if torch.cuda.is_bf16_supported() else torch.float16,
    )

    # 2. Load Processor and Base Model in 4-bit
    processor = AutoProcessor.from_pretrained(args.model_id, trust_remote_code=True)
    model = AutoModelForVision2Seq.from_pretrained(
        args.model_id,
        quantization_config=bnb_config,
        device_map="auto",
        trust_remote_code=True,
        torch_dtype=torch.bfloat16 if torch.cuda.is_bf16_supported() else torch.float16,
    )

    # 3. Prepare Base Model for k-bit Training (Freeze weights, cast LayerNorm to FP32)
    model = prepare_model_for_kbit_training(model, use_gradient_checkpointing=True)

    # 4. LoRA Adapter Configuration targeting attention and MLP projections
    target_modules = [
        "q_proj", "k_proj", "v_proj", "o_proj",
        "gate_proj", "up_proj", "down_proj",
        "merger.linear_fc", "merger.linear_proj"
    ]

    lora_config = LoraConfig(
        r=args.lora_rank,
        lora_alpha=args.lora_alpha,
        target_modules=target_modules,
        lora_dropout=args.lora_dropout,
        bias="none",
        task_type=TaskType.CAUSAL_LM,
    )

    model = get_peft_model(model, lora_config)
    model.print_trainable_parameters()

    # 5. Load Multimodal Dataset
    train_dataset = SpatialReceiptDataset(
        data_manifest_path=args.data_manifest,
        image_dir=args.image_dir,
        processor=processor,
        max_image_dim=896,
        augment=True,
    )

    # 6. Training Arguments
    training_args = TrainingArguments(
        output_dir=args.output_dir,
        num_train_epochs=args.epochs,
        per_device_train_batch_size=args.batch_size,
        gradient_accumulation_steps=args.grad_accum,
        warmup_ratio=0.05,
        learning_rate=args.lr,
        fp16=not torch.cuda.is_bf16_supported(),
        bf16=torch.cuda.is_bf16_supported(),
        logging_steps=10,
        save_strategy="epoch",
        evaluation_strategy="no",
        save_total_limit=2,
        dataloader_num_workers=4,
        gradient_checkpointing=True,
        report_to="none",
    )

    # 7. Execute Fine-Tuning
    trainer = Trainer(
        model=model,
        args=training_args,
        train_dataset=train_dataset,
    )

    print("=== Starting Model Convergence Training ===")
    trainer.train()

    # 8. Save Final LoRA Adapters and Processor
    print(f"=== Saving trained adapter weights to: {args.output_dir} ===")
    model.save_pretrained(args.output_dir)
    processor.save_pretrained(args.output_dir)
    print("=== Fine-Tuning Completed Successfully ===")


if __name__ == "__main__":
    main()
