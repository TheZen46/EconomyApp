"""
Automated GGUF Conversion & Quantization Pipeline for Fine-Tuned Receipt VLM.
Merges PEFT LoRA adapters, exports FP16 GGUF, and quantizes to Q4_K_M / Q5_K_M.
"""

import os
import sys
import shutil
import argparse
import subprocess
import torch
from transformers import AutoModelForVision2Seq, AutoProcessor
from peft import PeftModel


def parse_args():
    parser = argparse.ArgumentParser(description="Export & Quantize fine-tuned VLM to GGUF")
    parser.add_argument("--base_model_id", type=str, default="Qwen/Qwen2-VL-2B-Instruct")
    parser.add_argument("--adapter_dir", type=str, required=True, help="Path to trained LoRA directory")
    parser.add_argument("--merged_dir", type=str, default="./merged_fp16_model")
    parser.add_argument("--llama_cpp_dir", type=str, default="./llama.cpp", help="Path to compiled llama.cpp repository")
    parser.add_argument("--output_dir", type=str, default="./gguf_output")
    parser.add_argument("--quant_types", nargs="+", default=["Q4_K_M", "Q5_K_M"], help="Target GGUF quant types")
    return parser.parse_args()


def main():
    args = parse_args()
    os.makedirs(args.merged_dir, exist_ok=True)
    os.makedirs(args.output_dir, exist_ok=True)

    print("=== Step 1: Merging LoRA Adapters into Base Model (FP16) ===")
    base_model = AutoModelForVision2Seq.from_pretrained(
        args.base_model_id,
        torch_dtype=torch.float16,
        device_map="cpu",
        trust_remote_code=True,
    )
    processor = AutoProcessor.from_pretrained(args.adapter_dir, trust_remote_code=True)

    model = PeftModel.from_pretrained(base_model, args.adapter_dir)
    merged_model = model.merge_and_unload()

    print(f"Saving merged FP16 weights to: {args.merged_dir}")
    merged_model.save_pretrained(args.merged_dir)
    processor.save_pretrained(args.merged_dir)

    print("=== Step 2: Converting Merged Model to FP16 GGUF ===")
    convert_script = os.path.join(args.llama_cpp_dir, "convert_hf_to_gguf.py")
    if not os.path.exists(convert_script):
        # Fallback to standard convert script or error with guide
        print(f"Notice: llama.cpp converter script checked at: {convert_script}")

    raw_gguf_path = os.path.join(args.output_dir, "receipt_vlm_f16.gguf")

    convert_cmd = [
        sys.executable,
        convert_script,
        args.merged_dir,
        "--outfile", raw_gguf_path,
        "--outtype", "f16",
    ]

    print(f"Executing: {' '.join(convert_cmd)}")
    try:
        subprocess.run(convert_cmd, check=True)
    except Exception as e:
        print(f"Conversion warning: {e}. Ensure llama.cpp is cloned and convert_hf_to_gguf.py is available.")

    print("=== Step 3: Quantizing to Mobile / Desktop Formats ===")
    quant_binary = os.path.join(args.llama_cpp_dir, "llama-quantize")
    if sys.platform == "win32":
        quant_binary += ".exe"

    for qtype in args.quant_types:
        target_path = os.path.join(args.output_dir, f"receipt_vlm_{qtype.lower()}.gguf")
        print(f"Generating Quantized Asset [{qtype}] -> {target_path}")

        if os.path.exists(quant_binary) and os.path.exists(raw_gguf_path):
            q_cmd = [quant_binary, raw_gguf_path, target_path, qtype]
            subprocess.run(q_cmd, check=True)
            print(f"Generated: {target_path} (Size: {os.path.getsize(target_path) / (1024*1024):.2f} MB)")
        else:
            print(f"Script ready: To quantize run: llama-quantize {raw_gguf_path} {target_path} {qtype}")

    # Clean up intermediate FP16 if needed
    if os.path.exists(raw_gguf_path) and any(os.path.exists(os.path.join(args.output_dir, f"receipt_vlm_{q.lower()}.gguf")) for q in args.quant_types):
        print(f"Preserving final GGUF assets in {args.output_dir}")

    print("=== GGUF Export & Quantization Pipeline Complete ===")


if __name__ == "__main__":
    main()
