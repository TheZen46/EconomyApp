#!/usr/bin/env python3
"""
AI-Assisted Receipt Annotation CLI Assistant (Directive 1).

Bootstraps real receipt images into verified ground-truth JSON files
strictly adhering to the GBNF schema defined in `native/grammars/receipt.gbnf`.

Features:
- Multi-modal pseudo-labeling via Google Gemini 1.5 Flash (with offline fallback & mock engine)
- Strict GBNF schema validation & automated normalization
- Rich interactive CLI UI with colorized tables, confidence meters, and item breakdowns
- Fast 1-click acceptance ([Y]es), field/item editing ([E]dit), skip ([S]kip), and quit ([Q]uit)
- Verified dataset pairing in `tool/vlm_training/data/real/`
"""

import os
import re
import sys
import json
import shutil
import base64
import argparse
import warnings
from pathlib import Path
from typing import Dict, Any, List, Optional, Tuple

# Suppress deprecation warnings from legacy SDKs
warnings.filterwarnings("ignore", category=FutureWarning)

# Ensure UTF-8 output on Windows consoles
if sys.platform == "win32":
    try:
        if sys.stdout.encoding.lower() != "utf-8":
            sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        if sys.stderr.encoding.lower() != "utf-8":
            sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

import requests
from dotenv import load_dotenv

# Try importing rich; fallback to formatted ANSI if unavailable
try:
    from rich.console import Console
    from rich.table import Table
    from rich.panel import Panel
    from rich.prompt import Prompt, Confirm
    from rich.syntax import Syntax
    from rich.text import Text
    HAS_RICH = True
    console = Console(force_terminal=True)
except ImportError:
    HAS_RICH = False
    console = None

try:
    from PIL import Image
    HAS_PIL = True
except ImportError:
    HAS_PIL = False

# Try importing google.generativeai
try:
    import google.generativeai as genai
    HAS_GOOGLE_GENAI = True
except ImportError:
    HAS_GOOGLE_GENAI = False


# ══════════════════════════════════════════════════════════════════════════════
# 1. GBNF SCHEMA CONSTANTS & VALIDATION
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

CATEGORY_SYNONYMS = {
    "food": "Grocery",
    "groceries": "Grocery",
    "produce": "Fresh Produce",
    "fruit": "Fresh Produce",
    "vegetable": "Fresh Produce",
    "dairy": "Proteins & Dairy",
    "meat": "Proteins & Dairy",
    "bakery": "Pantry & Bakery",
    "beverage": "Snacks & Drinks",
    "drink": "Snacks & Drinks",
    "household": "Household & Living",
    "cleaning": "Household & Living",
    "hardware": "Tech",
    "electronics": "Tech",
    "pharmacy": "Health",
    "medicine": "Health",
    "dining": "Restaurant",
    "travel": "Transport",
}


def validate_gbnf_schema(data: Dict[str, Any]) -> Tuple[bool, List[str], Dict[str, Any]]:
    """
    Validates and normalizes a candidate receipt dictionary against `native/grammars/receipt.gbnf`.
    Returns (is_valid, error_messages, normalized_data).
    """
    errors = []
    norm = dict(data)

    # 1. Required top-level string fields
    for field in ["merchant_name", "merchant_address", "vat_number"]:
        if field not in norm or not isinstance(norm[field], str):
            errors.append(f"Missing or invalid '{field}' (expected string)")
            norm[field] = str(norm.get(field, "Unknown"))

    # 2. Date format: YYYY-MM-DD
    date_val = str(norm.get("date", ""))
    if not re.match(r"^\d{4}-\d{2}-\d{2}$", date_val):
        # Attempt recovery if date is in DD/MM/YYYY or DD.MM.YYYY
        match = re.match(r"^(\d{1,2})[/\.-](\d{1,2})[/\.-](\d{4})$", date_val)
        if match:
            day, month, year = match.groups()
            norm["date"] = f"{int(year):04d}-{int(month):02d}-{int(day):02d}"
        else:
            errors.append(f"Invalid date format: '{date_val}' (expected YYYY-MM-DD)")
            norm["date"] = "2026-01-01"

    # 3. Time format: HH:MM
    time_val = str(norm.get("time", ""))
    if not re.match(r"^\d{2}:\d{2}$", time_val):
        match = re.match(r"^(\d{1,2}):(\d{1,2})", time_val)
        if match:
            h, m = match.groups()
            norm["time"] = f"{int(h):02d}:{int(m):02d}"
        else:
            errors.append(f"Invalid time format: '{time_val}' (expected HH:MM)")
            norm["time"] = "12:00"

    # 4. Currency: 3-letter uppercase code
    curr = str(norm.get("currency", "EUR")).upper().strip()
    if len(curr) != 3 or not curr.isalpha():
        errors.append(f"Invalid currency code: '{curr}' (expected 3 uppercase letters)")
        curr = "EUR"
    norm["currency"] = curr

    # 5. Items list
    items_raw = norm.get("items", [])
    if not isinstance(items_raw, list):
        errors.append("Expected 'items' to be a list")
        items_raw = []

    norm_items = []
    computed_subtotal = 0.0

    for idx, item in enumerate(items_raw):
        if not isinstance(item, dict):
            errors.append(f"Item #{idx+1} is not a dictionary")
            continue

        raw_name = str(item.get("raw_name", f"Item {idx+1}")).strip()
        norm_name = str(item.get("normalized_name", raw_name)).strip()

        # Category validation & normalization
        cat = str(item.get("main_category", "Miscellaneous")).strip()
        if cat not in VALID_CATEGORIES:
            cat_lower = cat.lower()
            if cat_lower in CATEGORY_SYNONYMS:
                cat = CATEGORY_SYNONYMS[cat_lower]
            else:
                cat = "Miscellaneous"

        sub_cat = str(item.get("sub_category", "General")).strip()

        # Necessity validation
        nec = str(item.get("necessity", "essential")).lower().strip()
        if nec not in VALID_NECESSITIES:
            nec = "essential" if nec in ("need", "essential") else "discretional"

        # Numeric fields
        try:
            qty = max(1, int(item.get("quantity", 1)))
        except (ValueError, TypeError):
            qty = 1

        try:
            unit_p = round(float(item.get("unit_price", 0.0)), 2)
        except (ValueError, TypeError):
            unit_p = 0.0

        try:
            total_p = round(float(item.get("total_price", unit_p * qty)), 2)
        except (ValueError, TypeError):
            total_p = round(unit_p * qty, 2)

        is_asset = bool(item.get("is_asset", False))
        computed_subtotal += total_p

        norm_items.append({
            "raw_name": raw_name,
            "normalized_name": norm_name,
            "main_category": cat,
            "sub_category": sub_cat,
            "necessity": nec,
            "quantity": qty,
            "unit_price": unit_p,
            "total_price": total_p,
            "is_asset": is_asset,
        })

    norm["items"] = norm_items

    # 6. Tax Breakdown
    taxes_raw = norm.get("tax_breakdown", [])
    norm_taxes = []
    if isinstance(taxes_raw, list):
        for t in taxes_raw:
            if isinstance(t, dict):
                try:
                    r = round(float(t.get("rate", 0.0)), 4)
                    amt = round(float(t.get("tax_amount", 0.0)), 2)
                    norm_taxes.append({"rate": r, "tax_amount": amt})
                except (ValueError, TypeError):
                    pass
    norm["tax_breakdown"] = norm_taxes

    # 7. Total Amount & Confidence
    try:
        total_amt = round(float(norm.get("total_amount", computed_subtotal)), 2)
    except (ValueError, TypeError):
        total_amt = round(computed_subtotal, 2)
    norm["total_amount"] = total_amt

    try:
        conf = round(float(norm.get("confidence_score", 0.95)), 2)
        conf = max(0.0, min(1.0, conf))
    except (ValueError, TypeError):
        conf = 0.95
    norm["confidence_score"] = conf

    is_valid = len(errors) == 0
    return is_valid, errors, norm


# ══════════════════════════════════════════════════════════════════════════════
# 2. VISION & PSEUDO-LABELING EXTRACTION
# ══════════════════════════════════════════════════════════════════════════════

EXTRACTION_SYSTEM_PROMPT = """You are a high-precision on-device receipt intelligence engine.
Your task is to analyze the given receipt image and extract structured data strictly in JSON.

Output format MUST adhere to this exact schema:
{
  "merchant_name": "Store name",
  "merchant_address": "Street, City, Postal Code",
  "vat_number": "VAT/Tax ID or empty string",
  "date": "YYYY-MM-DD",
  "time": "HH:MM",
  "currency": "EUR" | "USD" | "GBP",
  "items": [
    {
      "raw_name": "Exact text printed on receipt",
      "normalized_name": "Standard clean product name",
      "main_category": "Fresh Produce" | "Proteins & Dairy" | "Pantry & Bakery" | "Frozen Foods" | "Snacks & Drinks" | "Household & Living" | "Personal Care" | "Miscellaneous" | "Grocery" | "Tech" | "Transport" | "Restaurant" | "Health" | "Education" | "Home" | "Clothing" | "Gift" | "Other",
      "sub_category": "Detailed sub-category",
      "necessity": "essential" | "discretional" | "junk" | "unknown",
      "quantity": 1,
      "unit_price": 0.00,
      "total_price": 0.00,
      "is_asset": false
    }
  ],
  "tax_breakdown": [
    {
      "rate": 0.10,
      "tax_amount": 0.00
    }
  ],
  "total_amount": 0.00,
  "confidence_score": 0.98
}

Rules:
1. is_asset must be true for durable electronics, appliances, or high-value physical goods (> $100 / €100).
2. necessity must be 'essential' for staple food/medicine, 'discretional' for dining/luxuries, 'junk' for sodas/candy/crisps.
3. Return ONLY valid raw JSON with NO markdown fences, explanations, or commentary.
"""


def extract_with_gemini_api(
    image_path: str,
    api_key: str,
    model_name: str = "gemini-1.5-flash"
) -> Optional[Dict[str, Any]]:
    """Calls Google Gemini Vision API to extract structured receipt data."""
    if not os.path.exists(image_path):
        return None

    # Option A: Use google-generativeai SDK if available
    if HAS_GOOGLE_GENAI:
        try:
            genai.configure(api_key=api_key)
            model = genai.GenerativeModel(
                model_name=model_name,
                generation_config={
                    "response_mime_type": "application/json",
                    "temperature": 0.1,
                }
            )
            pil_img = Image.open(image_path)
            response = model.generate_content([EXTRACTION_SYSTEM_PROMPT, pil_img])
            text = response.text.strip()
            # Strip potential code fences
            if text.startswith("```"):
                text = re.sub(r"^```(?:json)?\n?", "", text)
                text = re.sub(r"\n?```$", "", text)
            return json.loads(text)
        except Exception as e:
            if console:
                console.print(f"[yellow]SDK call warning ({e}), falling back to direct REST API...[/yellow]")

    # Option B: Direct HTTP REST fallback
    try:
        with open(image_path, "rb") as img_file:
            b64_data = base64.b64encode(img_file.read()).decode("utf-8")

        ext = Path(image_path).suffix.lower()
        mime_type = "image/jpeg"
        if ext in (".png", ".webp"):
            mime_type = f"image/{ext[1:]}"

        url = f"https://generativelanguage.googleapis.com/v1beta/models/{model_name}:generateContent?key={api_key}"
        payload = {
            "contents": [
                {
                    "parts": [
                        {"text": EXTRACTION_SYSTEM_PROMPT},
                        {
                            "inline_data": {
                                "mime_type": mime_type,
                                "data": b64_data
                            }
                        }
                    ]
                }
            ],
            "generationConfig": {
                "response_mime_type": "application/json",
                "temperature": 0.1
            }
        }

        resp = requests.post(url, json=payload, timeout=30)
        resp.raise_for_status()
        data = resp.json()
        candidates = data.get("candidates", [])
        if not candidates:
            return None

        raw_text = candidates[0]["content"]["parts"][0]["text"].strip()
        if raw_text.startswith("```"):
            raw_text = re.sub(r"^```(?:json)?\n?", "", raw_text)
            raw_text = re.sub(r"\n?```$", "", raw_text)
        return json.loads(raw_text)
    except Exception as err:
        if console:
            console.print(f"[red]Gemini API request failed: {err}[/red]")
        return None


def generate_mock_extraction(image_path: str) -> Dict[str, Any]:
    """Generates a schema-compliant mock extraction for testing & offline bootstrap."""
    base_name = Path(image_path).stem.replace("_", " ").title()
    return {
        "merchant_name": f"Store {base_name}",
        "merchant_address": "123 Commercial Way, Suite 400",
        "vat_number": "VAT-987654321",
        "date": "2026-03-15",
        "time": "14:32",
        "currency": "EUR",
        "items": [
            {
                "raw_name": "Organic Whole Milk 1L",
                "normalized_name": "Milk (Whole)",
                "main_category": "Proteins & Dairy",
                "sub_category": "Dairy & Alternatives",
                "necessity": "essential",
                "quantity": 2,
                "unit_price": 1.75,
                "total_price": 3.50,
                "is_asset": False
            },
            {
                "raw_name": "Fresh Sourdough Bread 500g",
                "normalized_name": "Sourdough Bread",
                "main_category": "Pantry & Bakery",
                "sub_category": "Bakery",
                "necessity": "essential",
                "quantity": 1,
                "unit_price": 2.80,
                "total_price": 2.80,
                "is_asset": False
            },
            {
                "raw_name": "Espresso Coffee Beans 250g",
                "normalized_name": "Coffee Beans",
                "main_category": "Snacks & Drinks",
                "sub_category": "Beverages",
                "necessity": "discretional",
                "quantity": 1,
                "unit_price": 5.40,
                "total_price": 5.40,
                "is_asset": False
            }
        ],
        "tax_breakdown": [
            {"rate": 0.10, "tax_amount": 0.63},
            {"rate": 0.22, "tax_amount": 1.19}
        ],
        "total_amount": 11.70,
        "confidence_score": 0.97
    }


# ══════════════════════════════════════════════════════════════════════════════
# 3. INTERACTIVE TERMINAL CLI UI
# ══════════════════════════════════════════════════════════════════════════════

def display_receipt_rich(image_path: str, data: Dict[str, Any], is_valid: bool, errors: List[str]):
    """Renders formatted rich UI for receipt verification."""
    if not HAS_RICH:
        display_receipt_ansi(image_path, data, is_valid, errors)
        return

    console.rule(f"[bold cyan]Receipt Verification: {os.path.basename(image_path)}[/bold cyan]")

    # Metadata Panel
    meta_text = (
        f"[bold]Merchant:[/bold] {data.get('merchant_name', 'N/A')}\n"
        f"[bold]Address:[/bold]  {data.get('merchant_address', 'N/A')}\n"
        f"[bold]VAT / Tax ID:[/bold] {data.get('vat_number', 'N/A')}\n"
        f"[bold]Date / Time:[/bold] {data.get('date')}  {data.get('time')}    "
        f"[bold]Currency:[/bold] {data.get('currency')}    "
        f"[bold]Confidence:[/bold] [green]{int(data.get('confidence_score', 0)*100)}%[/green]"
    )
    console.print(Panel(meta_text, title="[bold blue]Header Information[/bold blue]", border_style="blue"))

    # Items Table
    table = Table(title="Line Items Breakdown", show_header=True, header_style="bold magenta", expand=True)
    table.add_column("#", style="dim", width=3)
    table.add_column("Raw Name", style="white")
    table.add_column("Normalized Name", style="cyan")
    table.add_column("Category", style="green")
    table.add_column("Necessity", style="yellow")
    table.add_column("Qty", justify="right", width=4)
    table.add_column("Unit P.", justify="right", width=9)
    table.add_column("Total", justify="right", style="bold green", width=9)
    table.add_column("Asset?", justify="center", width=6)

    curr = data.get("currency", "EUR")
    for i, it in enumerate(data.get("items", [])):
        nec_style = "green" if it.get("necessity") == "essential" else ("red" if it.get("necessity") == "junk" else "yellow")
        asset_str = "[bold green]YES[/bold green]" if it.get("is_asset") else "[dim]no[/dim]"
        table.add_row(
            str(i + 1),
            it.get("raw_name", ""),
            it.get("normalized_name", ""),
            f"{it.get('main_category', '')} ({it.get('sub_category', '')})",
            f"[{nec_style}]{it.get('necessity', '')}[/{nec_style}]",
            str(it.get("quantity", 1)),
            f"{it.get('unit_price', 0.0):.2f} {curr}",
            f"{it.get('total_price', 0.0):.2f} {curr}",
            asset_str
        )

    console.print(table)

    # Tax & Total Summary Panel
    taxes = ", ".join([f"{t.get('rate', 0)*100:.1f}% -> {t.get('tax_amount', 0.0):.2f} {curr}" for t in data.get("tax_breakdown", [])])
    summary_text = (
        f"[bold]Tax Breakdown:[/bold] {taxes if taxes else 'None'}\n"
        f"[bold yellow]Grand Total:[/bold yellow]   [bold green]{data.get('total_amount', 0.0):.2f} {curr}[/bold green]"
    )
    console.print(Panel(summary_text, title="[bold green]Totals & Taxes[/bold green]", border_style="green"))

    if not is_valid:
        console.print(Panel("\n".join(f"[red]• {e}[/red]" for e in errors), title="[bold red]Validation Warnings (Auto-Corrected)[/bold red]", border_style="red"))


def display_receipt_ansi(image_path: str, data: Dict[str, Any], is_valid: bool, errors: List[str]):
    """ANSI fallback when rich is not available."""
    print("=" * 70)
    print(f" Receipt Verification: {os.path.basename(image_path)}")
    print("=" * 70)
    print(f" Merchant: {data.get('merchant_name')} | VAT: {data.get('vat_number')}")
    print(f" Date: {data.get('date')} {data.get('time')} | Currency: {data.get('currency')} | Total: {data.get('total_amount')}")
    print("-" * 70)
    print(" Items:")
    for i, it in enumerate(data.get("items", [])):
        print(f"  {i+1}. {it.get('raw_name')} ({it.get('main_category')}) - {it.get('quantity')}x {it.get('unit_price')} = {it.get('total_price')} [{it.get('necessity')}] (Asset: {it.get('is_asset')})")
    print("=" * 70)


def interactive_edit_receipt(data: Dict[str, Any]) -> Dict[str, Any]:
    """Provides interactive prompt to edit metadata or items."""
    curr = dict(data)

    if not HAS_RICH:
        print("\nInteractive editing in non-rich terminal:")
        print("1. Edit Merchant Name")
        print("2. Edit Date (YYYY-MM-DD)")
        print("3. Edit Total Amount")
        print("4. Done")
        choice = input("Select option (1-4): ").strip()
        if choice == "1":
            curr["merchant_name"] = input("New Merchant Name: ").strip() or curr["merchant_name"]
        elif choice == "2":
            curr["date"] = input("New Date (YYYY-MM-DD): ").strip() or curr["date"]
        elif choice == "3":
            try:
                curr["total_amount"] = float(input("New Total: ").strip() or curr["total_amount"])
            except ValueError:
                pass
        return curr

    while True:
        console.print("\n[bold cyan]Edit Options:[/bold cyan]")
        console.print("  [1] Edit Merchant / Store Info")
        console.print("  [2] Edit Date & Time")
        console.print("  [3] Edit Total & Currency")
        console.print("  [4] Edit Line Item")
        console.print("  [5] Add Line Item")
        console.print("  [6] Toggle Item Asset Flag")
        console.print("  [7] Change Item Necessity (essential / discretional / junk)")
        console.print("  [8] Recalculate Subtotal & Done")
        console.print("  [9] Cancel / Done Editing")

        choice = Prompt.ask("Choose an action", choices=["1", "2", "3", "4", "5", "6", "7", "8", "9"], default="8")

        if choice == "1":
            curr["merchant_name"] = Prompt.ask("Merchant Name", default=curr.get("merchant_name", ""))
            curr["merchant_address"] = Prompt.ask("Address", default=curr.get("merchant_address", ""))
            curr["vat_number"] = Prompt.ask("VAT Number", default=curr.get("vat_number", ""))
        elif choice == "2":
            curr["date"] = Prompt.ask("Date (YYYY-MM-DD)", default=curr.get("date", "2026-01-01"))
            curr["time"] = Prompt.ask("Time (HH:MM)", default=curr.get("time", "12:00"))
        elif choice == "3":
            curr["currency"] = Prompt.ask("Currency (3 letters)", default=curr.get("currency", "EUR")).upper()
            curr["total_amount"] = float(Prompt.ask("Total Amount", default=str(curr.get("total_amount", 0.0))))
        elif choice == "4":
            items = curr.get("items", [])
            if not items:
                console.print("[yellow]No items to edit.[/yellow]")
                continue
            idx_str = Prompt.ask(f"Select item index (1-{len(items)})", default="1")
            try:
                idx = int(idx_str) - 1
                if 0 <= idx < len(items):
                    item = items[idx]
                    item["raw_name"] = Prompt.ask("Raw Name", default=item.get("raw_name", ""))
                    item["normalized_name"] = Prompt.ask("Normalized Name", default=item.get("normalized_name", ""))
                    item["main_category"] = Prompt.ask("Main Category", choices=list(VALID_CATEGORIES), default=item.get("main_category", "Miscellaneous"))
                    item["quantity"] = int(Prompt.ask("Quantity", default=str(item.get("quantity", 1))))
                    item["unit_price"] = float(Prompt.ask("Unit Price", default=str(item.get("unit_price", 0.0))))
                    item["total_price"] = round(item["unit_price"] * item["quantity"], 2)
            except Exception as e:
                console.print(f"[red]Error editing item: {e}[/red]")
        elif choice == "5":
            try:
                name = Prompt.ask("Item Name")
                cat = Prompt.ask("Category", choices=list(VALID_CATEGORIES), default="Miscellaneous")
                qty = int(Prompt.ask("Quantity", default="1"))
                unit_p = float(Prompt.ask("Unit Price", default="1.00"))
                nec = Prompt.ask("Necessity", choices=list(VALID_NECESSITIES), default="essential")
                curr.setdefault("items", []).append({
                    "raw_name": name,
                    "normalized_name": name,
                    "main_category": cat,
                    "sub_category": "General",
                    "necessity": nec,
                    "quantity": qty,
                    "unit_price": unit_p,
                    "total_price": round(qty * unit_p, 2),
                    "is_asset": False
                })
            except Exception as e:
                console.print(f"[red]Error adding item: {e}[/red]")
        elif choice == "6":
            items = curr.get("items", [])
            idx_str = Prompt.ask(f"Toggle asset flag for item index (1-{len(items)})", default="1")
            try:
                idx = int(idx_str) - 1
                if 0 <= idx < len(items):
                    items[idx]["is_asset"] = not items[idx].get("is_asset", False)
                    console.print(f"[green]Item #{idx+1} is_asset is now: {items[idx]['is_asset']}[/green]")
            except Exception:
                pass
        elif choice == "7":
            items = curr.get("items", [])
            idx_str = Prompt.ask(f"Select item index (1-{len(items)})", default="1")
            try:
                idx = int(idx_str) - 1
                if 0 <= idx < len(items):
                    new_nec = Prompt.ask("Select necessity", choices=list(VALID_NECESSITIES), default="essential")
                    items[idx]["necessity"] = new_nec
            except Exception:
                pass
        elif choice in ("8", "9"):
            # Recalculate total if requested
            calc_sum = sum(it.get("total_price", 0.0) for it in curr.get("items", []))
            if choice == "8" or abs(calc_sum - curr.get("total_amount", 0.0)) > 0.01:
                curr["total_amount"] = round(calc_sum, 2)
            break

    return curr


# ══════════════════════════════════════════════════════════════════════════════
# 4. MAIN BATCH ANNOTATION PIPELINE
# ══════════════════════════════════════════════════════════════════════════════

def process_single_image(
    image_path: str,
    output_dir: str,
    api_key: Optional[str] = None,
    auto_accept: bool = False,
    use_mock: bool = False,
    model_name: str = "gemini-1.5-flash"
) -> str:
    """
    Processes a single image: pseudo-labels, validates GBNF schema, prompts user, and saves verified pair.
    Returns status: 'accepted', 'skipped', 'quit', or 'error'.
    """
    if console:
        console.print(f"\n[cyan]Processing image:[/cyan] [bold]{image_path}[/bold]")

    raw_extraction = None

    # Step 1: Call API or generate mock
    if not use_mock and api_key:
        if console:
            console.print("[dim]Calling Gemini 1.5 Flash Vision...[/dim]")
        raw_extraction = extract_with_gemini_api(image_path, api_key=api_key, model_name=model_name)

    if raw_extraction is None:
        if console:
            console.print("[dim]Using local/mock extraction engine...[/dim]")
        raw_extraction = generate_mock_extraction(image_path)

    # Step 2: Validate against GBNF schema
    is_valid, errors, validated_data = validate_gbnf_schema(raw_extraction)

    # Step 3: Interactive Verification & Editing
    if auto_accept:
        final_data = validated_data
        status = "accepted"
    else:
        current_data = validated_data
        while True:
            display_receipt_rich(image_path, current_data, is_valid, errors)

            action = Prompt.ask(
                "\n[bold]Action[/bold]",
                choices=["y", "e", "s", "q"],
                default="y"
            ).lower()

            if action == "y":
                final_data = current_data
                status = "accepted"
                break
            elif action == "e":
                current_data = interactive_edit_receipt(current_data)
                is_valid, errors, current_data = validate_gbnf_schema(current_data)
            elif action == "s":
                if console:
                    console.print(f"[yellow]Skipped {os.path.basename(image_path)}[/yellow]")
                return "skipped"
            elif action == "q":
                if console:
                    console.print("[bold red]Annotation session interrupted by user.[/bold red]")
                return "quit"

    # Step 4: Save verified pair
    os.makedirs(output_dir, exist_ok=True)
    base_name = Path(image_path).name
    stem = Path(image_path).stem

    dest_img = os.path.join(output_dir, base_name)
    dest_json = os.path.join(output_dir, f"{stem}.json")

    # Copy image
    shutil.copy2(image_path, dest_img)

    # Write GBNF JSON
    with open(dest_json, "w", encoding="utf-8") as f:
        json.dump(final_data, f, indent=2, ensure_ascii=False)

    if console:
        console.print(f"[green]✓ Verified pair saved:[/green] {dest_img} & {dest_json}")

    return status


def parse_arguments():
    parser = argparse.ArgumentParser(
        description="AI-Assisted Receipt Annotation CLI Assistant (Directive 1)"
    )
    parser.add_argument(
        "--input", "-i",
        type=str,
        default="assets/raw_receipts",
        help="Input directory containing raw receipt images (or path to a single image file)"
    )
    parser.add_argument(
        "--output", "-o",
        type=str,
        default="tool/vlm_training/data/real",
        help="Output directory for verified image and JSON pairs"
    )
    parser.add_argument(
        "--api_key",
        type=str,
        default=None,
        help="Google Gemini API key (defaults to GEMINI_API_KEY from .env or environment)"
    )
    parser.add_argument(
        "--model",
        type=str,
        default="gemini-1.5-flash",
        help="Gemini model identifier (default: gemini-1.5-flash)"
    )
    parser.add_argument(
        "--auto_accept",
        action="store_true",
        help="Automatically accept and save all extractions without interactive prompts"
    )
    parser.add_argument(
        "--mock",
        action="store_true",
        help="Force offline mock pseudo-labeling engine for testing without network/API"
    )
    return parser.parse_args()


def main():
    load_dotenv()
    args = parse_arguments()

    api_key = args.api_key or os.environ.get("GEMINI_API_KEY")

    if console:
        console.rule("[bold green]tAIdy AI-Assisted Receipt Annotation Assistant[/bold green]")
        console.print(f"[bold]Input Path:[/bold]  {args.input}")
        console.print(f"[bold]Output Path:[/bold] {args.output}")
        console.print(f"[bold]Mode:[/bold]        {'Auto-Accept' if args.auto_accept else 'Interactive Review'}")
        console.print(f"[bold]Engine:[/bold]      {'Mock / Offline Heuristics' if args.mock else (args.model if api_key else 'Mock (No API Key detected)')}")

    # Collect images
    image_paths = []
    supported_exts = {".jpg", ".jpeg", ".png", ".webp"}
    input_path = Path(args.input)

    if input_path.is_file() and input_path.suffix.lower() in supported_exts:
        image_paths.append(str(input_path))
    elif input_path.is_dir():
        for p in input_path.iterdir():
            if p.is_file() and p.suffix.lower() in supported_exts:
                image_paths.append(str(p))
    else:
        # If directory doesn't exist, create it to assist the user
        os.makedirs(args.input, exist_ok=True)
        if console:
            console.print(f"[yellow]Input directory '{args.input}' was empty or created. Place receipt images there to annotate.[/yellow]")
        return

    if not image_paths:
        if console:
            console.print(f"[yellow]No images (.jpg, .png, .webp) found in '{args.input}'.[/yellow]")
        return

    image_paths.sort()
    if console:
        console.print(f"[cyan]Found {len(image_paths)} images ready for annotation.[/cyan]\n")

    accepted_count = 0
    skipped_count = 0

    for idx, img_p in enumerate(image_paths):
        if console:
            console.print(f"[bold blue]--- [{idx + 1}/{len(image_paths)}] {os.path.basename(img_p)} ---[/bold blue]")
        res = process_single_image(
            image_path=img_p,
            output_dir=args.output,
            api_key=api_key,
            auto_accept=args.auto_accept,
            use_mock=args.mock or not api_key,
            model_name=args.model
        )
        if res == "accepted":
            accepted_count += 1
        elif res == "skipped":
            skipped_count += 1
        elif res == "quit":
            break

    if console:
        console.rule("[bold green]Annotation Summary[/bold green]")
        console.print(f"[green][OK] Total Accepted:[/green] {accepted_count}")
        console.print(f"[yellow] * Total Skipped:[/yellow]  {skipped_count}")
        console.print(f"[cyan] * Output Directory:[/cyan] {args.output}")


if __name__ == "__main__":
    main()
