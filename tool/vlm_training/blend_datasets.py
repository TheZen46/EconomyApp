#!/usr/bin/env python3
"""
Dataset Blending & Stratification Pipeline for Receipt Intelligence (Directive 1).

Combines verified real receipts (`tool/vlm_training/data/real/`) with procedurally generated
synthetic receipts (`tool/vlm_training/data/synthetic/` or `./synthetic_dataset/`)
into balanced, stratified multimodal datasets.

Features:
- Configurable real-to-synthetic blending ratio (e.g. 20% real / 80% synthetic)
- Full GBNF schema validation on every sample before inclusion
- Stratified Train / Validation / Test partitioning (default 80% / 10% / 10%)
- Generates standard `train.jsonl`, `val.jsonl`, and `test.jsonl` files
- Comprehensive dataset statistics telemetry (`dataset_summary.json`)
"""

import sys
import os
import glob
import json
import random
import shutil
import argparse
from pathlib import Path
from typing import Dict, Any, List, Tuple, Optional
from collections import Counter

# Ensure UTF-8 output on Windows consoles
if sys.platform == "win32":
    try:
        if sys.stdout.encoding.lower() != "utf-8":
            sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        if sys.stderr.encoding.lower() != "utf-8":
            sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

# Try importing rich for summary tables
try:
    from rich.console import Console
    from rich.table import Table
    from rich.panel import Panel
    HAS_RICH = True
    console = Console(force_terminal=True)
except ImportError:
    HAS_RICH = False
    console = None


# ══════════════════════════════════════════════════════════════════════════════
# 1. GBNF SCHEMA VALIDATOR
# ══════════════════════════════════════════════════════════════════════════════

VALID_CATEGORIES = {
    "Fresh Produce",
    "Proteins & Dairy",
    "Pantry & Bakery",
    "Frozen Foods",
    "Snacks & Drinks",
    "Household & Living",
    "Personal Care",
    "Miscellaneous",
    "Grocery",
    "Tech",
    "Transport",
    "Restaurant",
    "Health",
    "Education",
    "Home",
    "Clothing",
    "Gift",
    "Other",
}

VALID_NECESSITIES = {
    "essential",
    "discretional",
    "junk",
    "unknown",
}


def validate_sample_gbnf(json_path: str) -> Tuple[bool, Optional[Dict[str, Any]], str]:
    """Validates that a JSON file matches the GBNF receipt schema."""
    try:
        with open(json_path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception as e:
        return False, None, f"JSON parse error: {e}"

    required_fields = ["merchant_name", "date", "time", "currency", "items", "total_amount"]
    for rf in required_fields:
        if rf not in data:
            return False, None, f"Missing required field: '{rf}'"

    if not isinstance(data.get("items"), list):
        return False, None, "'items' must be a list"

    for it in data["items"]:
        if not isinstance(it, dict):
            return False, None, "Line item must be a dictionary"
        cat = it.get("main_category")
        if cat not in VALID_CATEGORIES:
            return False, None, f"Invalid category: '{cat}'"
        nec = it.get("necessity")
        if nec not in VALID_NECESSITIES:
            return False, None, f"Invalid necessity: '{nec}'"

    return True, data, "OK"


# ══════════════════════════════════════════════════════════════════════════════
# 2. DATA DISCOVERY & SAMPLING
# ══════════════════════════════════════════════════════════════════════════════

def discover_paired_samples(directory: str, source_type: str) -> List[Dict[str, Any]]:
    """Discovers all valid paired (.jpg/.png/.webp + .json) samples in a directory."""
    samples = []
    if not os.path.exists(directory):
        return samples

    supported_exts = ("*.jpg", "*.jpeg", "*.png", "*.webp")
    discovered_images = []
    for ext in supported_exts:
        discovered_images.extend(glob.glob(os.path.join(directory, ext)))

    for img_p in discovered_images:
        stem = Path(img_p).stem
        parent = Path(img_p).parent
        json_p = os.path.join(parent, f"{stem}.json")

        if os.path.exists(json_p):
            is_valid, data, reason = validate_sample_gbnf(json_p)
            if is_valid and data is not None:
                samples.append({
                    "id": stem,
                    "image_path": os.path.abspath(img_p),
                    "json_path": os.path.abspath(json_p),
                    "source": source_type,
                    "data": data,
                    # Dominant category for stratification
                    "primary_category": data["items"][0]["main_category"] if data["items"] else "Miscellaneous",
                })
            else:
                if console:
                    console.print(f"[yellow]Skipping invalid sample {stem}.json: {reason}[/yellow]")

    return samples


def blend_and_sample(
    real_samples: List[Dict[str, Any]],
    synth_samples: List[Dict[str, Any]],
    real_ratio: float = 0.20,
    total_samples: Optional[int] = None,
    seed: int = 42
) -> List[Dict[str, Any]]:
    """
    Blends real and synthetic samples maintaining target ratio.
    """
    rng = random.Random(seed)
    rng.shuffle(real_samples)
    rng.shuffle(synth_samples)

    n_real = len(real_samples)
    n_synth = len(synth_samples)

    if n_real == 0 and n_synth == 0:
        return []

    if n_real == 0:
        return synth_samples[:total_samples] if total_samples else synth_samples

    if n_synth == 0:
        return real_samples[:total_samples] if total_samples else real_samples

    # Compute target counts based on availability and ratio
    if total_samples is not None:
        target_real = min(n_real, int(round(total_samples * real_ratio)))
        target_synth = min(n_synth, total_samples - target_real)
    else:
        # Scale to include as much real data as available while keeping ratio
        # real_count / (real_count + synth_count) == real_ratio
        target_real = n_real
        target_synth = min(n_synth, int(round(target_real * (1.0 - real_ratio) / max(1e-5, real_ratio))))

        # If synthetic pool is the bottleneck, adjust real count
        if target_synth > n_synth:
            target_synth = n_synth
            target_real = min(n_real, int(round(target_synth * real_ratio / (1.0 - real_ratio))))

    selected_real = real_samples[:target_real]
    selected_synth = synth_samples[:target_synth]

    blended = selected_real + selected_synth
    rng.shuffle(blended)
    return blended


# ══════════════════════════════════════════════════════════════════════════════
# 3. STRATIFIED PARTITIONING
# ══════════════════════════════════════════════════════════════════════════════

def stratified_split(
    samples: List[Dict[str, Any]],
    train_ratio: float = 0.80,
    val_ratio: float = 0.10,
    test_ratio: float = 0.10,
    seed: int = 42
) -> Tuple[List[Dict[str, Any]], List[Dict[str, Any]], List[Dict[str, Any]]]:
    """
    Splits samples into Train / Val / Test sets stratified by source and primary category.
    """
    rng = random.Random(seed)

    # Group by (source, primary_category) strata
    strata: Dict[Tuple[str, str], List[Dict[str, Any]]] = {}
    for s in samples:
        key = (s["source"], s["primary_category"])
        strata.setdefault(key, []).append(s)

    train_set = []
    val_set = []
    test_set = []

    for group in strata.values():
        rng.shuffle(group)
        n = len(group)
        if n == 1:
            train_set.extend(group)
            continue
        elif n == 2:
            train_set.append(group[0])
            val_set.append(group[1])
            continue

        n_train = int(round(n * train_ratio))
        n_val = int(round(n * val_ratio))
        # Ensure at least 1 in train if n > 0
        n_train = max(1, n_train)

        train_set.extend(group[:n_train])
        val_set.extend(group[n_train:n_train + n_val])
        test_set.extend(group[n_train + n_val:])

    rng.shuffle(train_set)
    rng.shuffle(val_set)
    rng.shuffle(test_set)

    return train_set, val_set, test_set


# ══════════════════════════════════════════════════════════════════════════════
# 4. JSONL SERIALIZATION & SUMMARY METRICS
# ══════════════════════════════════════════════════════════════════════════════

SYSTEM_PROMPT = (
    "You are an expert on-device receipt intelligence engine. "
    "Analyze the input receipt image and extract structured data strictly into JSON matching the schema."
)
USER_PROMPT = "Extract all receipt metadata, items, tax breakdown, and totals in structured JSON format."


def write_jsonl_file(
    samples: List[Dict[str, Any]],
    output_file: str,
    copy_to_dir: Optional[str] = None
):
    """Writes dataset split to JSONL format."""
    os.makedirs(os.path.dirname(os.path.abspath(output_file)), exist_ok=True)

    with open(output_file, "w", encoding="utf-8") as f:
        for s in samples:
            img_path = s["image_path"]
            if copy_to_dir:
                os.makedirs(copy_to_dir, exist_ok=True)
                dest_img = os.path.join(copy_to_dir, os.path.basename(img_path))
                if not os.path.exists(dest_img):
                    shutil.copy2(img_path, dest_img)
                rel_img_path = os.path.relpath(dest_img, os.path.dirname(output_file))
            else:
                rel_img_path = img_path

            record = {
                "id": s["id"],
                "image_path": rel_img_path,
                "source": s["source"],
                "system_prompt": SYSTEM_PROMPT,
                "user_prompt": USER_PROMPT,
                "ground_truth": s["data"],
            }
            f.write(json.dumps(record, ensure_ascii=False) + "\n")


def compute_telemetry_summary(
    train_set: List[Dict[str, Any]],
    val_set: List[Dict[str, Any]],
    test_set: List[Dict[str, Any]]
) -> Dict[str, Any]:
    """Calculates dataset health and distribution statistics."""
    all_samples = train_set + val_set + test_set

    source_counter = Counter(s["source"] for s in all_samples)
    category_counter = Counter()
    necessity_counter = Counter()
    currency_counter = Counter()
    total_spend = 0.0
    total_items = 0
    asset_count = 0

    for s in all_samples:
        d = s["data"]
        currency_counter[d.get("currency", "EUR")] += 1
        total_spend += float(d.get("total_amount", 0.0))
        for it in d.get("items", []):
            total_items += 1
            category_counter[it.get("main_category", "Miscellaneous")] += 1
            necessity_counter[it.get("necessity", "essential")] += 1
            if it.get("is_asset", False):
                asset_count += 1

    return {
        "total_samples": len(all_samples),
        "splits": {
            "train_count": len(train_set),
            "val_count": len(val_set),
            "test_count": len(test_set),
        },
        "source_distribution": dict(source_counter),
        "real_percentage": round((source_counter["real"] / max(1, len(all_samples))) * 100, 2),
        "synthetic_percentage": round((source_counter["synthetic"] / max(1, len(all_samples))) * 100, 2),
        "total_line_items": total_items,
        "total_assets_flagged": asset_count,
        "currency_distribution": dict(currency_counter),
        "necessity_distribution": dict(necessity_counter),
        "top_categories": dict(category_counter.most_common(10)),
        "total_spend_aggregated": round(total_spend, 2)
    }


# ══════════════════════════════════════════════════════════════════════════════
# 5. CLI PIPELINE EXECUTION
# ══════════════════════════════════════════════════════════════════════════════

def parse_args():
    parser = argparse.ArgumentParser(
        description="Dataset Blending & Stratified Partitioning for Receipt Intelligence (Directive 1)"
    )
    parser.add_argument(
        "--real_dir",
        type=str,
        default="tool/vlm_training/data/real",
        help="Directory containing verified real receipt image and JSON pairs"
    )
    parser.add_argument(
        "--synthetic_dir",
        type=str,
        default="synthetic_dataset",
        help="Directory containing procedurally generated synthetic receipt pairs"
    )
    parser.add_argument(
        "--output_dir",
        type=str,
        default="tool/vlm_training/data/blended",
        help="Output directory for train.jsonl, val.jsonl, test.jsonl, and dataset_summary.json"
    )
    parser.add_argument(
        "--real_ratio",
        type=float,
        default=0.20,
        help="Target real dataset ratio (e.g. 0.20 for 20%% real / 80%% synthetic)"
    )
    parser.add_argument(
        "--total_samples",
        type=int,
        default=None,
        help="Optional maximum number of total samples in the blended dataset"
    )
    parser.add_argument(
        "--train_ratio",
        type=float,
        default=0.80,
        help="Proportion of data for training split (default: 0.80)"
    )
    parser.add_argument(
        "--val_ratio",
        type=float,
        default=0.10,
        help="Proportion of data for validation split (default: 0.10)"
    )
    parser.add_argument(
        "--test_ratio",
        type=float,
        default=0.10,
        help="Proportion of data for test split (default: 0.10)"
    )
    parser.add_argument(
        "--copy_images",
        action="store_true",
        help="Copy all referenced images into output_dir/images/ for standalone portable datasets"
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=42,
        help="Random seed for reproducibility"
    )
    return parser.parse_args()


def main():
    args = parse_args()

    if console:
        console.rule("[bold green]tAIdy Dataset Blending & Stratification Pipeline[/bold green]")
        console.print(f"[bold]Real Data Dir:[/bold]      {args.real_dir}")
        console.print(f"[bold]Synthetic Data Dir:[/bold] {args.synthetic_dir}")
        console.print(f"[bold]Output Dir:[/bold]         {args.output_dir}")
        console.print(f"[bold]Target Real Ratio:[/bold]  {args.real_ratio * 100:.1f}%")
        console.print(f"[bold]Split Distribution:[/bold] Train={args.train_ratio*100:.0f}% / Val={args.val_ratio*100:.0f}% / Test={args.test_ratio*100:.0f}%")

    # Step 1: Discover datasets
    real_samples = discover_paired_samples(args.real_dir, source_type="real")
    synth_samples = discover_paired_samples(args.synthetic_dir, source_type="synthetic")

    if console:
        console.print(f"[cyan]Discovered:[/cyan] [green]{len(real_samples)} verified real samples[/green], [blue]{len(synth_samples)} synthetic samples[/blue].")

    if not real_samples and not synth_samples:
        if console:
            console.print("[bold red]Error: No valid samples found in real or synthetic directories.[/bold red]")
        sys.exit(1)

    # Step 2: Blend & Sample
    blended = blend_and_sample(
        real_samples=real_samples,
        synth_samples=synth_samples,
        real_ratio=args.real_ratio,
        total_samples=args.total_samples,
        seed=args.seed
    )

    if console:
        console.print(f"[cyan]Total blended samples selected:[/cyan] [bold green]{len(blended)}[/bold green]")

    # Step 3: Stratified Partitioning
    train_set, val_set, test_set = stratified_split(
        blended,
        train_ratio=args.train_ratio,
        val_ratio=args.val_ratio,
        test_ratio=args.test_ratio,
        seed=args.seed
    )

    # Step 4: Write JSONL and copy images if requested
    os.makedirs(args.output_dir, exist_ok=True)
    images_dest_dir = os.path.join(args.output_dir, "images") if args.copy_images else None

    train_jsonl = os.path.join(args.output_dir, "train.jsonl")
    val_jsonl = os.path.join(args.output_dir, "val.jsonl")
    test_jsonl = os.path.join(args.output_dir, "test.jsonl")
    summary_json = os.path.join(args.output_dir, "dataset_summary.json")

    write_jsonl_file(train_set, train_jsonl, copy_to_dir=images_dest_dir)
    write_jsonl_file(val_set, val_jsonl, copy_to_dir=images_dest_dir)
    write_jsonl_file(test_set, test_jsonl, copy_to_dir=images_dest_dir)

    # Step 5: Compute summary metrics
    summary = compute_telemetry_summary(train_set, val_set, test_set)
    with open(summary_json, "w", encoding="utf-8") as f:
        json.dump(summary, f, indent=2, ensure_ascii=False)

    # Step 6: Render summary
    if HAS_RICH and console:
        table = Table(title="Blended Dataset Partition Summary", header_style="bold green")
        table.add_column("Split", style="cyan")
        table.add_column("Count", justify="right", style="bold")
        table.add_column("Real Count", justify="right")
        table.add_column("Synthetic Count", justify="right")

        for name, split in [("Train", train_set), ("Validation", val_set), ("Test", test_set)]:
            r_c = sum(1 for s in split if s["source"] == "real")
            s_c = sum(1 for s in split if s["source"] == "synthetic")
            table.add_row(name, str(len(split)), str(r_c), str(s_c))

        console.print(table)
        console.print(Panel(
            f"[bold]Total Samples:[/bold] {summary['total_samples']}\n"
            f"[bold]Real Data:[/bold]    {summary['real_percentage']}%\n"
            f"[bold]Synthetic:[/bold]    {summary['synthetic_percentage']}%\n"
            f"[bold]Line Items:[/bold]   {summary['total_line_items']} ({summary['total_assets_flagged']} assets flagged)\n"
            f"[bold]Artifacts:[/bold]    {train_jsonl}\n"
            f"              {val_jsonl}\n"
            f"              {test_jsonl}\n"
            f"              {summary_json}",
            title="[bold green]✓ Dataset Blending Complete[/bold green]",
            border_style="green"
        ))
    else:
        print(f"Successfully created blended dataset: Train={len(train_set)}, Val={len(val_set)}, Test={len(test_set)}")
        print(f"Summary saved to: {summary_json}")


if __name__ == "__main__":
    main()
