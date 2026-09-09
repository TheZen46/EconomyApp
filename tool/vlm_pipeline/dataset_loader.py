"""
Receipt Intelligence Dataset Loader & Spatial Augmentation Pipeline.
Formats raw receipts and synthetic bounding boxes into Vision-Language Model tokens.
"""

import os
import json
import random
from typing import List, Dict, Any, Tuple, Optional
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter
import torch
from torch.utils.data import Dataset


class SpatialReceiptDataset(Dataset):
    """
    Multimodal spatial receipt dataset with bounding box coordinate tokenization.
    Normalizes coordinates to [0, 1000) scale for spatial VLM alignment (e.g., Qwen2-VL / SmolVLM).
    """

    def __init__(
        self,
        data_manifest_path: str,
        image_dir: str,
        processor: Any,
        max_image_dim: int = 896,
        augment: bool = False,
    ):
        self.image_dir = image_dir
        self.processor = processor
        self.max_image_dim = max_image_dim
        self.augment = augment
        self.records = self._load_manifest(data_manifest_path)

    def _load_manifest(self, path: str) -> List[Dict[str, Any]]:
        records = []
        if not os.path.exists(path):
            raise FileNotFoundError(f"Manifest not found: {path}")
        with open(path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line:
                    records.append(json.loads(line))
        return records

    def __len__(self) -> int:
        return len(self.records)

    def _apply_photometric_augmentation(self, img: Image.Image) -> Image.Image:
        """Simulate real-world thermal receipt degradation: fading, shadows, blur."""
        if random.random() < 0.3:
            enhancer = ImageEnhance.Contrast(img)
            img = enhancer.enhance(random.uniform(0.6, 1.4))

        if random.random() < 0.3:
            enhancer = ImageEnhance.Brightness(img)
            img = enhancer.enhance(random.uniform(0.7, 1.3))

        if random.random() < 0.2:
            img = img.filter(ImageFilter.GaussianBlur(radius=random.uniform(0.5, 1.2)))

        return img

    def _normalize_and_resize(
        self, img: Image.Image, boxes: List[Dict[str, Any]]
    ) -> Tuple[Image.Image, List[Dict[str, Any]]]:
        """Resizes image to max_image_dim while adjusting 2D bounding boxes."""
        orig_w, orig_h = img.size
        scale = min(self.max_image_dim / orig_w, self.max_image_dim / orig_h)
        new_w = int(orig_w * scale)
        new_h = int(orig_h * scale)

        resized_img = img.resize((new_w, new_h), Image.Resampling.BILINEAR)

        scaled_boxes = []
        for box in boxes:
            xmin, ymin, xmax, ymax = box["bbox"]
            norm_box = [
                int((xmin / orig_w) * 1000),
                int((ymin / orig_h) * 1000),
                int((xmax / orig_w) * 1000),
                int((ymax / orig_h) * 1000),
            ]
            scaled_boxes.append({
                "label": box.get("label", "text"),
                "text": box.get("text", ""),
                "norm_bbox": norm_box,
            })

        return resized_img, scaled_boxes

    def _format_target_json(self, record: Dict[str, Any]) -> str:
        """Serializes clean canonical ground truth JSON without markdown boilerplate."""
        ground_truth = {
            "merchant_name": record.get("merchant_name", "Unknown"),
            "date": record.get("date", "2024-01-01"),
            "currency": record.get("currency", "USD"),
            "items": [
                {
                    "raw_name": item.get("raw_name", ""),
                    "normalized_name": item.get("normalized_name", item.get("raw_name", "")),
                    "category": item.get("category", "General"),
                    "quantity": int(item.get("quantity", 1)),
                    "unit_price": float(item.get("unit_price", 0.0)),
                    "total_price": float(item.get("total_price", 0.0)),
                }
                for item in record.get("items", [])
            ],
            "tax_breakdown": [
                {
                    "rate": float(tax.get("rate", 0.0)),
                    "tax_amount": float(tax.get("tax_amount", 0.0)),
                }
                for tax in record.get("tax_breakdown", [])
            ],
            "total_amount": float(record.get("total_amount", 0.0)),
            "confidence_score": float(record.get("confidence_score", 1.0)),
        }
        return json.dumps(ground_truth, separators=(",", ":"), ensure_ascii=False)

    def __getitem__(self, idx: int) -> Dict[str, Any]:
        record = self.records[idx]
        img_path = os.path.join(self.image_dir, record["image_file"])

        image = Image.open(img_path).convert("RGB")

        if self.augment:
            image = self._apply_photometric_augmentation(image)

        raw_boxes = record.get("bounding_boxes", [])
        image, scaled_boxes = self._normalize_and_resize(image, raw_boxes)

        target_json = self._format_target_json(record)

        prompt = [
            {
                "role": "system",
                "content": "You are a high-precision spatial receipt parser. Extract all receipt metadata and line items directly from the image into canonical JSON format.",
            },
            {
                "role": "user",
                "content": [
                    {"type": "image", "image": image},
                    {"type": "text", "text": "Extract structured receipt items, tax, and totals into strict JSON."},
                ],
            },
            {
                "role": "assistant",
                "content": [{"type": "text", "text": target_json}],
            },
        ]

        text = self.processor.apply_chat_template(prompt, tokenize=False, add_generation_prompt=False)

        inputs = self.processor(
            text=[text],
            images=[image],
            padding="max_length",
            max_length=2048,
            return_tensors="pt",
        )

        item = {k: v.squeeze(0) for k, v in inputs.items()}
        labels = item["input_ids"].clone()
        labels[labels == self.processor.tokenizer.pad_token_id] = -100
        item["labels"] = labels

        return item
