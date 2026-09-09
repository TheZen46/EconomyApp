"""
PyTorch Dataset & Multimodal Collator for VLM Receipt Fine-Tuning.

Loads paired receipt images and structured JSON ground truth from:
- Directory containing paired (.jpg/.png/.webp + .json) files
- Stratified JSONL files (e.g. train.jsonl / val.jsonl)

Supports:
- Qwen2-VL (Qwen/Qwen2-VL-2B-Instruct)
- SmolVLM (HuggingFaceTB/SmolVLM-500M-Instruct)
- Strict loss masking on prompt and image tokens (-100)
- Dynamic batch collation for multimodal vision-language tensors
"""

import os
import glob
import json
import random
from pathlib import Path
from typing import Dict, Any, List, Optional, Tuple, Union
from PIL import Image, ImageEnhance, ImageFilter

try:
    import torch
    from torch.utils.data import Dataset
    HAS_TORCH = True
except ImportError:
    HAS_TORCH = False
    class Dataset:
        pass


class ReceiptDataset(Dataset):
    """
    Multimodal Dataset for Vision-Language receipt processing.
    Pairs receipt images with GBNF-aligned ground-truth JSON strings.
    """

    def __init__(
        self,
        data_dir: Optional[str] = None,
        data_file: Optional[str] = None,
        processor: Optional[Any] = None,
        is_training: bool = True,
        system_prompt: Optional[str] = None,
        sample_indices: Optional[List[int]] = None,
    ):
        self.data_dir = data_dir
        self.data_file = data_file
        self.processor = processor
        self.is_training = is_training
        self.system_prompt = system_prompt or (
            "You are an expert on-device receipt intelligence engine. "
            "Analyze the input receipt image and extract structured data strictly into JSON matching the schema."
        )

        all_samples: List[Tuple[str, Union[str, Dict[str, Any]]]] = []

        # Mode A: Load from JSONL file
        if data_file and os.path.exists(data_file):
            base_dir = os.path.dirname(os.path.abspath(data_file))
            with open(data_file, "r", encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        record = json.loads(line)
                        img_path = record.get("image_path")
                        if img_path:
                            # Resolve relative path against jsonl directory
                            if not os.path.isabs(img_path):
                                img_path = os.path.normpath(os.path.join(base_dir, img_path))
                            ground_truth = record.get("ground_truth", {})
                            if os.path.exists(img_path):
                                all_samples.append((img_path, ground_truth))
                    except Exception:
                        pass

        # Mode B: Discover paired image + json files in data_dir
        elif data_dir and os.path.exists(data_dir):
            image_extensions = ("*.jpg", "*.jpeg", "*.png", "*.webp")
            for ext in image_extensions:
                for img_path in glob.glob(os.path.join(data_dir, ext)):
                    base_name = os.path.splitext(img_path)[0]
                    json_path = f"{base_name}.json"
                    if os.path.exists(json_path):
                        all_samples.append((img_path, json_path))

        all_samples.sort(key=lambda x: str(x[0]))

        if sample_indices is not None:
            self.samples = [all_samples[i] for i in sample_indices if i < len(all_samples)]
        else:
            self.samples = all_samples

        print(f"ReceiptDataset ({'Train' if is_training else 'Val'}): Loaded {len(self.samples)} paired samples")

    def __len__(self) -> int:
        return len(self.samples)

    def _apply_augmentations(self, img: Image.Image) -> Image.Image:
        """Applies realistic optical degradations during training only."""
        if not self.is_training:
            return img

        # 1. Subtle perspective/rotation jitter (-2.0 to +2.0 degrees)
        if random.random() > 0.4:
            angle = random.uniform(-2.0, 2.0)
            img = img.rotate(angle, resample=Image.BICUBIC, expand=False, fillcolor=(245, 245, 240))

        # 2. Random contrast adjustment (0.90 to 1.15)
        if random.random() > 0.3:
            factor = random.uniform(0.90, 1.15)
            img = ImageEnhance.Contrast(img).enhance(factor)

        # 3. Random brightness adjustment (0.90 to 1.10)
        if random.random() > 0.3:
            factor = random.uniform(0.90, 1.10)
            img = ImageEnhance.Brightness(img).enhance(factor)

        # 4. Slight Gaussian blur simulating camera defocus
        if random.random() > 0.5:
            radius = random.uniform(0.20, 0.60)
            img = img.filter(ImageFilter.GaussianBlur(radius=radius))

        return img

    def __getitem__(self, idx: int) -> Dict[str, Any]:
        img_path, json_or_dict = self.samples[idx]

        # 1. Load and augment image
        raw_img = Image.open(img_path).convert("RGB")
        aug_img = self._apply_augmentations(raw_img)

        # 2. Load ground-truth JSON string
        if isinstance(json_or_dict, dict):
            label_dict = json_or_dict
        else:
            with open(json_or_dict, "r", encoding="utf-8") as f:
                label_dict = json.load(f)

        target_json_str = json.dumps(label_dict, ensure_ascii=False, indent=2)

        if self.processor is None:
            # Fallback dictionary for processor-less inspection
            return {
                "image": aug_img,
                "target_text": target_json_str,
                "image_path": img_path
            }

        # 3. Construct prompt conversation (User prompt up to generation point)
        prompt_messages = [
            {
                "role": "system",
                "content": [{"type": "text", "text": self.system_prompt}]
            },
            {
                "role": "user",
                "content": [
                    {"type": "image", "image": aug_img},
                    {"type": "text", "text": "Extract all receipt metadata, items, tax breakdown, and totals in structured JSON format."}
                ]
            }
        ]

        # Full conversation including assistant response
        full_messages = prompt_messages + [
            {
                "role": "assistant",
                "content": [{"type": "text", "text": target_json_str}]
            }
        ]

        # 4. Format chat templates
        try:
            prompt_text = self.processor.apply_chat_template(
                prompt_messages, tokenize=False, add_generation_prompt=True
            )
            full_text = self.processor.apply_chat_template(
                full_messages, tokenize=False, add_generation_prompt=False
            )
        except Exception:
            # Fallback for processors without custom chat template
            prompt_text = f"<|im_start|>system\n{self.system_prompt}<|im_end|>\n<|im_start|>user\n<image>Extract all receipt metadata in structured JSON format.<|im_end|>\n<|im_start|>assistant\n"
            full_text = f"{prompt_text}{target_json_str}<|im_end|>"

        # 5. Process multimodal inputs through model processor
        inputs = self.processor(
            text=[full_text],
            images=[aug_img],
            padding=False,
            return_tensors="pt"
        )

        prompt_inputs = self.processor(
            text=[prompt_text],
            images=[aug_img],
            padding=False,
            return_tensors="pt"
        )

        input_ids = inputs["input_ids"].squeeze(0)
        attention_mask = inputs["attention_mask"].squeeze(0)
        prompt_length = prompt_inputs["input_ids"].shape[1]

        # 6. Mask prompt tokens with -100 so loss is computed strictly on target JSON tokens
        labels = input_ids.clone()
        labels[:min(prompt_length, len(labels))] = -100

        item = {
            "input_ids": input_ids,
            "attention_mask": attention_mask,
            "labels": labels,
        }

        # Include model-specific vision tensors
        if "mm_token_type_ids" in inputs:
            item["mm_token_type_ids"] = inputs["mm_token_type_ids"].squeeze(0)
        if "pixel_values" in inputs:
            item["pixel_values"] = inputs["pixel_values"]
        if "image_grid_thw" in inputs:
            item["image_grid_thw"] = inputs["image_grid_thw"].squeeze(0)
        if "pixel_attention_mask" in inputs:
            item["pixel_attention_mask"] = inputs["pixel_attention_mask"]

        return item


class ReceiptDataCollator:
    """
    Custom collator for dynamic batch padding of multimodal vision-language tensors.
    """

    def __init__(self, processor: Any, pad_token_id: int = 151643):
        self.processor = processor
        if hasattr(processor, "tokenizer") and processor.tokenizer.pad_token_id is not None:
            self.pad_token_id = processor.tokenizer.pad_token_id
        else:
            self.pad_token_id = pad_token_id

    def __call__(self, batch: List[Dict[str, Any]]) -> Dict[str, Any]:
        if not HAS_TORCH:
            return {"batch": batch}

        input_ids = [item["input_ids"] for item in batch]
        labels = [item["labels"] for item in batch]
        attention_mask = [item["attention_mask"] for item in batch]

        input_ids_padded = torch.nn.utils.rnn.pad_sequence(
            input_ids, batch_first=True, padding_value=self.pad_token_id
        )
        labels_padded = torch.nn.utils.rnn.pad_sequence(
            labels, batch_first=True, padding_value=-100
        )
        attention_mask_padded = torch.nn.utils.rnn.pad_sequence(
            attention_mask, batch_first=True, padding_value=0
        )

        batch_dict = {
            "input_ids": input_ids_padded,
            "labels": labels_padded,
            "attention_mask": attention_mask_padded,
        }

        # Collate multimodal token type IDs (M-RoPE)
        if "mm_token_type_ids" in batch[0] and batch[0]["mm_token_type_ids"] is not None:
            mm_types = [item["mm_token_type_ids"] for item in batch]
            batch_dict["mm_token_type_ids"] = torch.nn.utils.rnn.pad_sequence(
                mm_types, batch_first=True, padding_value=0
            )

        # Collate pixel values
        if "pixel_values" in batch[0] and batch[0]["pixel_values"] is not None:
            pixel_values = [item["pixel_values"] for item in batch if item.get("pixel_values") is not None]
            if pixel_values:
                batch_dict["pixel_values"] = torch.cat(pixel_values, dim=0)

        # Collate image_grid_thw
        if "image_grid_thw" in batch[0] and batch[0]["image_grid_thw"] is not None:
            image_grid_thw = [item["image_grid_thw"] for item in batch if item.get("image_grid_thw") is not None]
            if image_grid_thw:
                batch_dict["image_grid_thw"] = torch.stack(image_grid_thw, dim=0) if image_grid_thw[0].dim() == 1 else torch.cat(image_grid_thw, dim=0)

        return batch_dict
