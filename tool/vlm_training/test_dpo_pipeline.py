#!/usr/bin/env python3
"""
Unit and Integration Test Suite for DPO Pipeline (Directive 9).

Validates:
1. Semantic difference analyzer and correction severity weighting.
2. Hard negative mining and JSONL dataset generation.
3. DPO loss mathematical calculation and reward margins.
4. Regression test harness metrics (MAE, F1, Exact Match).
"""

import os
import sys
import copy
import json
import math
import shutil
import tempfile
import unittest

# Ensure UTF-8 on Windows
if sys.platform == "win32":
    try:
        if sys.stdout.encoding.lower() != "utf-8":
            sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        if sys.stderr.encoding.lower() != "utf-8":
            sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

# Add parent directory to path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from mine_dpo_pairs import (
    compute_string_similarity,
    analyze_correction_severity,
    generate_hard_negative_from_ground_truth,
    mine_dpo_pairs
)
from eval_regression import (
    evaluate_receipt_pair,
    run_regression_evaluation
)


class TestDPOPipeline(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.mkdtemp(prefix="dpo_test_")
        self.sample_ground_truth = {
            "merchant_name": "Esselunga Supermercato",
            "merchant_address": "Via Pellegrino Rossi 15, Milano",
            "vat_number": "IT01234567890",
            "date": "2026-09-09",
            "time": "11:30:00",
            "currency": "EUR",
            "items": [
                {
                    "raw_name": "LATTE PARMALAT 1L",
                    "normalized_name": "Milk (Whole)",
                    "quantity": 2,
                    "unit_price": 1.75,
                    "total_price": 3.50,
                    "main_category": "Proteins & Dairy",
                    "sub_category": "Dairy & Alternatives",
                    "necessity": "essential",
                    "is_asset": False
                },
                {
                    "raw_name": "CAFFE LAVAZZA 250G",
                    "normalized_name": "Coffee Beans",
                    "quantity": 1,
                    "unit_price": 4.50,
                    "total_price": 4.50,
                    "main_category": "Snacks & Drinks",
                    "sub_category": "Beverages",
                    "necessity": "discretionary",
                    "is_asset": False
                }
            ],
            "tax_breakdown": [{"rate_percent": 10.0, "taxable_amount": 7.27, "tax_amount": 0.73}],
            "total_amount": 8.00,
            "confidence_score": 0.99
        }

    def tearDown(self):
        if os.path.exists(self.temp_dir):
            shutil.rmtree(self.temp_dir, ignore_errors=True)

    # ──────────────────────────────────────────────────────────────────────────
    # 1. String Similarity & Diffing Tests
    # ──────────────────────────────────────────────────────────────────────────
    def test_string_similarity(self):
        self.assertAlmostEqual(compute_string_similarity("Apple", "Apple"), 1.0)
        self.assertAlmostEqual(compute_string_similarity("Apple", "apple"), 1.0)
        self.assertGreater(compute_string_similarity("Esselunga", "Esselung"), 0.85)
        self.assertLess(compute_string_similarity("Apple", "Banana"), 0.3)
        self.assertEqual(compute_string_similarity("", "Apple"), 0.0)

    # ──────────────────────────────────────────────────────────────────────────
    # 2. Correction Severity Weighting Tests
    # ──────────────────────────────────────────────────────────────────────────
    def test_arithmetic_error_weighting(self):
        # Flawed total amount (+3.0x weight)
        rejected = dict(self.sample_ground_truth)
        rejected["total_amount"] = 12.50

        weight, severity = analyze_correction_severity(self.sample_ground_truth, rejected)
        self.assertGreaterEqual(severity["arithmetic_errors"], 1)
        self.assertGreaterEqual(weight, 4.0)  # Base 1.0 + 3.0 * Arithmetic = 4.0

    def test_category_error_weighting(self):
        # Misclassified category (+2.0x weight)
        rejected = json.loads(json.dumps(self.sample_ground_truth))
        rejected["items"][0]["main_category"] = "Electronics"

        weight, severity = analyze_correction_severity(self.sample_ground_truth, rejected)
        self.assertGreaterEqual(severity["category_errors"], 1)
        self.assertGreaterEqual(weight, 3.0)  # Base 1.0 + 2.0 * Category = 3.0

    def test_ocr_spelling_error_weighting(self):
        # Minor typo in merchant name (+1.0x weight)
        rejected = json.loads(json.dumps(self.sample_ground_truth))
        rejected["merchant_name"] = "Esselung Supermercato"

        weight, severity = analyze_correction_severity(self.sample_ground_truth, rejected)
        self.assertGreaterEqual(severity["ocr_spelling_errors"], 1)
        self.assertGreaterEqual(weight, 2.0)  # Base 1.0 + 1.0 * OCR = 2.0

    # ──────────────────────────────────────────────────────────────────────────
    # 3. Hard Negative Mining Pipeline Tests
    # ──────────────────────────────────────────────────────────────────────────
    def test_mine_dpo_pairs_generation(self):
        summary = mine_dpo_pairs(
            output_dir=self.temp_dir,
            target_count=30,
            seed=123
        )

        self.assertEqual(summary["total_pairs"], 30)
        self.assertEqual(summary["train_count"], 24)
        self.assertEqual(summary["val_count"], 3)
        self.assertEqual(summary["test_count"], 3)

        train_file = os.path.join(self.temp_dir, "dpo_train.jsonl")
        self.assertTrue(os.path.exists(train_file))

        with open(train_file, "r", encoding="utf-8") as f:
            lines = [json.loads(line) for line in f if line.strip()]
            self.assertEqual(len(lines), 24)
            sample = lines[0]
            self.assertIn("chosen", sample)
            self.assertIn("rejected", sample)
            self.assertIn("weight", sample)
            self.assertIn("prompt", sample)
            self.assertGreaterEqual(sample["weight"], 1.0)

    # ──────────────────────────────────────────────────────────────────────────
    # 4. DPO Loss Mathematical Verification (Simulated NumPy/Python Math)
    # ──────────────────────────────────────────────────────────────────────────
    def test_dpo_loss_formula_math(self):
        beta = 0.1

        # Scenario A: Model prefers chosen (log p(chosen) = -1.0, log p(rejected) = -3.0)
        # Reference is neutral (log ref(chosen) = -2.0, log ref(rejected) = -2.0)
        log_pi_w = -1.0
        log_pi_l = -3.0
        log_ref_w = -2.0
        log_ref_l = -2.0

        r_w = beta * (log_pi_w - log_ref_w)  # 0.1 * (-1.0 - -2.0) = +0.10
        r_l = beta * (log_pi_l - log_ref_l)  # 0.1 * (-3.0 - -2.0) = -0.10
        margin_good = r_w - r_l              # +0.20
        loss_good = -math.log(1.0 / (1.0 + math.exp(-margin_good)))

        # Scenario B: Model prefers rejected (flawed prediction)
        log_pi_w_bad = -3.0
        log_pi_l_bad = -1.0
        r_w_bad = beta * (log_pi_w_bad - log_ref_w)  # -0.10
        r_l_bad = beta * (log_pi_l_bad - log_ref_l)  # +0.10
        margin_bad = r_w_bad - r_l_bad               # -0.20
        loss_bad = -math.log(1.0 / (1.0 + math.exp(-margin_bad)))

        # Assert loss is strictly lower when model aligns with human preferences
        self.assertLess(loss_good, loss_bad)
        self.assertGreater(margin_good, 0.0)
        self.assertLess(margin_bad, 0.0)

    # ──────────────────────────────────────────────────────────────────────────
    # 5. Regression Evaluation Harness Tests
    # ──────────────────────────────────────────────────────────────────────────
    def test_receipt_pair_evaluation_metrics(self):
        pred_perfect = copy.deepcopy(self.sample_ground_truth)
        metrics_perfect = evaluate_receipt_pair(self.sample_ground_truth, pred_perfect)

        self.assertTrue(metrics_perfect["total_exact_match"])
        self.assertEqual(metrics_perfect["total_abs_error"], 0.0)
        self.assertEqual(metrics_perfect["f1"], 1.0)
        self.assertEqual(metrics_perfect["category_accuracy"], 1.0)
        self.assertEqual(metrics_perfect["hallucination_rate"], 0.0)

        # Imperfect prediction (1 wrong price, 1 phantom item)
        pred_flawed = copy.deepcopy(self.sample_ground_truth)
        pred_flawed["total_amount"] = 15.00
        pred_flawed["items"].append({
            "normalized_name": "Phantom Warranty Plan",
            "quantity": 1,
            "unit_price": 7.00,
            "total_price": 7.00,
            "main_category": "Services",
            "necessity": "junk"
        })

        metrics_flawed = evaluate_receipt_pair(self.sample_ground_truth, pred_flawed)
        self.assertFalse(metrics_flawed["total_exact_match"])
        self.assertEqual(metrics_flawed["total_abs_error"], 7.0)
        self.assertLess(metrics_flawed["precision"], 1.0)
        self.assertGreater(metrics_flawed["hallucination_rate"], 0.0)


if __name__ == "__main__":
    unittest.main()
