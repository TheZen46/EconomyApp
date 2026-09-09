#!/usr/bin/env python3
"""
Automated Verification Test Suite for VLM Training & Export Pipeline:
- tool/annotate_receipts.py
- tool/vlm_training/blend_datasets.py
- tool/vlm_training/train_qlora.py
- tool/vlm_training/export_gguf.py
"""

import os
import sys
import json
import unittest
import tempfile
import shutil
from pathlib import Path

# Add repo root to path
REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
if REPO_ROOT not in sys.path:
    sys.path.insert(0, REPO_ROOT)

from tool.annotate_receipts import validate_gbnf_schema, generate_mock_extraction
from tool.vlm_training.blend_datasets import (
    validate_sample_gbnf,
    discover_paired_samples,
    blend_and_sample,
    stratified_split,
    compute_telemetry_summary
)
from tool.vlm_training.train_qlora import resolve_model_info, MODEL_REGISTRY
from tool.vlm_training.export_gguf import calculate_sha256, export_gguf_and_quantize, QUANTIZATION_TIERS


class TestReceiptVlmPipeline(unittest.TestCase):

    def test_gbnf_schema_validation_valid(self):
        sample = {
            "merchant_name": "Esselunga S.p.A.",
            "merchant_address": "Via Milano 12, Milano",
            "vat_number": "IT12345678901",
            "date": "2026-05-10",
            "time": "15:30",
            "currency": "EUR",
            "items": [
                {
                    "raw_name": "Latte Fresco 1L",
                    "normalized_name": "Milk",
                    "main_category": "Proteins & Dairy",
                    "sub_category": "Dairy",
                    "necessity": "essential",
                    "quantity": 2,
                    "unit_price": 1.50,
                    "total_price": 3.00,
                    "is_asset": False
                }
            ],
            "tax_breakdown": [{"rate": 0.10, "tax_amount": 0.30}],
            "total_amount": 3.00,
            "confidence_score": 0.99
        }
        is_valid, errors, normalized = validate_gbnf_schema(sample)
        self.assertTrue(is_valid)
        self.assertEqual(len(errors), 0)
        self.assertEqual(normalized["currency"], "EUR")
        self.assertEqual(normalized["items"][0]["main_category"], "Proteins & Dairy")

    def test_gbnf_schema_auto_normalization(self):
        sample = {
            "merchant_name": "Bakery Corner",
            "merchant_address": "45 Paris Ave",
            "vat_number": "",
            "date": "15/08/2026",
            "time": "9:15",
            "currency": "eur",
            "items": [
                {
                    "raw_name": "Baguette",
                    "main_category": "bakery",
                    "necessity": "NEED",
                    "quantity": 2,
                    "unit_price": 1.20,
                    "total_price": 2.40,
                }
            ]
        }
        is_valid, errors, normalized = validate_gbnf_schema(sample)
        self.assertEqual(normalized["date"], "2026-08-15")
        self.assertEqual(normalized["time"], "09:15")
        self.assertEqual(normalized["currency"], "EUR")
        self.assertEqual(normalized["items"][0]["main_category"], "Pantry & Bakery")
        self.assertEqual(normalized["items"][0]["necessity"], "essential")
        self.assertEqual(normalized["items"][0]["is_asset"], False)

    def test_dataset_blending_stratification(self):
        real_samples = [
            {
                "id": f"real_{i}",
                "image_path": f"/path/real_{i}.jpg",
                "source": "real",
                "primary_category": "Proteins & Dairy" if i % 2 == 0 else "Tech",
                "data": {
                    "merchant_name": f"Real Store {i}",
                    "currency": "EUR",
                    "total_amount": 25.0,
                    "items": [{"main_category": "Proteins & Dairy", "necessity": "essential", "total_price": 25.0, "is_asset": False}]
                }
            }
            for i in range(10)
        ]
        synth_samples = [
            {
                "id": f"synth_{i}",
                "image_path": f"/path/synth_{i}.jpg",
                "source": "synthetic",
                "primary_category": "Fresh Produce",
                "data": {
                    "merchant_name": f"Synth Store {i}",
                    "currency": "EUR",
                    "total_amount": 10.0,
                    "items": [{"main_category": "Fresh Produce", "necessity": "essential", "total_price": 10.0, "is_asset": False}]
                }
            }
            for i in range(40)
        ]

        blended = blend_and_sample(real_samples, synth_samples, real_ratio=0.20, seed=42)
        self.assertEqual(len(blended), 50)
        real_count = sum(1 for s in blended if s["source"] == "real")
        self.assertEqual(real_count, 10)

        train, val, test = stratified_split(blended, train_ratio=0.80, val_ratio=0.10, test_ratio=0.10, seed=42)
        self.assertEqual(len(train) + len(val) + len(test), 50)
        self.assertTrue(len(train) > 0)
        self.assertTrue(len(val) > 0)
        self.assertTrue(len(test) > 0)

        summary = compute_telemetry_summary(train, val, test)
        self.assertEqual(summary["total_samples"], 50)
        self.assertEqual(summary["real_percentage"], 20.0)
        self.assertEqual(summary["synthetic_percentage"], 80.0)

    def test_model_resolution(self):
        qwen_spec = resolve_model_info("qwen2-vl-2b")
        self.assertEqual(qwen_spec["hf_id"], "Qwen/Qwen2-VL-2B-Instruct")
        self.assertIn("q_proj", qwen_spec["target_modules"])

        smol_spec = resolve_model_info("smolvlm-500m")
        self.assertEqual(smol_spec["hf_id"], "HuggingFaceTB/SmolVLM-500M-Instruct")
        self.assertIn("q_proj", smol_spec["target_modules"])

    def test_export_gguf_quantization_tiers(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            manifest = export_gguf_and_quantize(
                merged_hf_dir="Qwen/Qwen2-VL-2B-Instruct",
                output_dir=tmpdir,
                model_name="test_model",
                model_version="1.0.0"
            )

            self.assertIn("models", manifest)
            self.assertIn("mobile_q4", manifest["models"])
            self.assertIn("desktop_q5", manifest["models"])
            self.assertIn("high_precision_q8", manifest["models"])

            # Check that files exist and have non-empty hashes
            for tier_key in ["mobile_q4", "desktop_q5", "high_precision_q8"]:
                tier_info = manifest["models"][tier_key]
                file_path = os.path.join(tmpdir, tier_info["file_name"])
                self.assertTrue(os.path.exists(file_path))
                self.assertEqual(len(tier_info["sha256"]), 64)


if __name__ == "__main__":
    unittest.main()
