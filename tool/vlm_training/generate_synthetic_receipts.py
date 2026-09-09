#!/usr/bin/env python3
"""
Multilingual Synthetic Receipt Generator for tAIdy On-Device VLM Fine-Tuning.

Generates realistic paired receipt images (.jpg) and structured ground truth (.json)
with procedurally rendered thermal paper textures, multi-column alignments, nested discounts,
tax breakdowns, and physical camera augmentations (homography warp, lighting gradients, shadows, blur).

Supported language distributions:
- Italian: 50%
- French: 20%
- German: 15%
- English: 15%

Strictly adheres to schema defined in `native/grammars/receipt.gbnf`.
"""

import os
import math
import json
import random
import argparse
from datetime import datetime, timedelta
from typing import List, Dict, Any, Tuple, Optional

import numpy as np
from PIL import (
    Image,
    ImageDraw,
    ImageFont,
    ImageFilter,
    ImageEnhance,
    ImageOps
)

# ══════════════════════════════════════════════════════════════════════════════
# 1. MULTILINGUAL TAXONOMY & STORE CATALOGS
# ══════════════════════════════════════════════════════════════════════════════

CATALOG_ITALIAN = {
    "stores": [
        ("ESSELUNGA S.P.A.", "Via Carlo De Angeli 3, 20141 Milano (MI)", "IT01234567890", "RT 99MEY012488", "+39 02 8950 1234"),
        ("CONAD CENTRO NORD", "Via Tuscolana 450, 00181 Roma (RM)", "IT09876543211", "RT 88ABC110943", "+39 06 7812 5543"),
        ("COOP ALLEANZA 3.0", "Via Emilia Ponente 80, 40133 Bologna (BO)", "IT03322114455", "RT 77XYZ440129", "+39 051 614 9900"),
        ("CARREFOUR EXPRESS", "Corso Vittorio Emanuele 12, 10123 Torino (TO)", "IT05544332211", "RT 66KKL990234", "+39 011 543 2198"),
        ("EUROSPIN ITALIA", "Via Casilina 1020, 00169 Roma (RM)", "IT06677889900", "RT 55HHY334411", "+39 06 2329 8812"),
        ("FARMACIA SANTA LUCIA", "Piazza del Duomo 4, 50122 Firenze (FI)", "IT01122334455", "RT 44FFR112233", "+39 055 214 556"),
        ("BRICO IO - BRICOLAGE", "Via Tiburtina 770, 00159 Roma (RM)", "IT07788990011", "RT 33ZZK887766", "+39 06 4390 112"),
        ("TRATTORIA DA MARIO", "Via dei Fossi 28R, 50123 Firenze (FI)", "IT02233445566", "RT 22MMN554433", "+39 055 218 075"),
    ],
    "titles": [
        "DOCUMENTO COMMERCIALE",
        "DOCUMENTO COMMERCIALE DI VENDITA",
        "SCONTRINO FISCALE",
        "RICEVUTA FISCALE",
    ],
    "items": [
        # (raw_name, norm_name, main_cat, sub_cat, necessity, price_range, tax_rate)
        ("BANANE BIO CHIQUITA KG", "Bananas", "Fresh Produce", "Fruits", "essential", (1.80, 2.70), 0.04),
        ("MELE GOLDEN MELINDA DOP", "Apples/Pears", "Fresh Produce", "Fruits", "essential", (1.99, 2.99), 0.04),
        ("ARANCE DI SICILIA TAROCCO", "Citrus (Oranges/Lemons/Limes)", "Fresh Produce", "Fruits", "essential", (2.20, 3.50), 0.04),
        ("INSALATA MISTA BONDUELLE", "Lettuce/Salad Greens", "Fresh Produce", "Leafy Greens & Cruciferous", "essential", (1.29, 2.19), 0.04),
        ("POMODORI CILIEGINO 500G", "Tomatoes", "Fresh Produce", "Fruit Vegetables", "essential", (1.59, 2.89), 0.04),
        ("ZUCCHINE CHIARE FRESCHE", "Zucchini/Eggplant", "Fresh Produce", "Fruit Vegetables", "essential", (1.70, 2.80), 0.04),
        ("FUNGHI CHAMPIGNON 300G", "Mushrooms (White/Cremini)", "Fresh Produce", "Fresh Herbs & Fungi", "essential", (1.89, 2.69), 0.04),
        ("LATTE FRESCO INTERO 1L", "Milk (Whole/Skim)", "Proteins & Dairy", "Dairy & Alternatives", "essential", (1.49, 2.19), 0.10),
        ("UOVA FRESCHE TERRA X6", "Eggs (Standard)", "Proteins & Dairy", "Dairy & Alternatives", "essential", (1.79, 2.99), 0.10),
        ("BURRO SANTA LUCIA 250G", "Butter", "Proteins & Dairy", "Dairy & Alternatives", "essential", (2.49, 3.89), 0.10),
        ("PARMIGIANO REGGIANO 24M", "Cheese (Fancy)", "Proteins & Dairy", "Dairy & Alternatives", "discretional", (4.80, 7.90), 0.10),
        ("MOZZARELLA DI BUFALA DOP", "Cheese (Fancy)", "Proteins & Dairy", "Dairy & Alternatives", "discretional", (3.20, 5.50), 0.10),
        ("YOGURT GRECO BIANCO 150G", "Yogurt (Plain/Greek)", "Proteins & Dairy", "Dairy & Alternatives", "essential", (1.19, 1.89), 0.10),
        ("PETTO DI POLLO A FETTE", "Chicken (Whole/Breast/Thighs)", "Proteins & Dairy", "Butcher Counter", "essential", (4.50, 8.20), 0.10),
        ("MACINATO SCELTO BOVINO", "Ground Beef/Pork/Turkey", "Proteins & Dairy", "Butcher Counter", "essential", (4.20, 7.10), 0.10),
        ("FILETTO DI SALMONE 250G", "Oily Fish (Salmon/Trout)", "Proteins & Dairy", "Seafood", "essential", (5.90, 8.90), 0.10),
        ("PANE CASERECCIO 500G", "Sliced Bread", "Pantry & Bakery", "Bakery", "essential", (1.50, 2.80), 0.04),
        ("SPAGHETTI BARILLA N.5", "Pasta", "Pantry & Bakery", "Grains & Pasta", "essential", (0.99, 1.79), 0.04),
        ("RISO CARNAROLI 1KG", "Rice", "Pantry & Bakery", "Grains & Pasta", "essential", (2.89, 4.20), 0.04),
        ("PASSATA MUTTI 700G", "Tomato Paste", "Pantry & Bakery", "Condiments", "essential", (1.19, 1.89), 0.04),
        ("OLIO EVO MONINI 1L", "Oil (Olive/Veg)", "Pantry & Bakery", "Condiments", "essential", (6.90, 11.90), 0.04),
        ("CAFFE LAVAZZA ROSSA 250G", "Coffee", "Snacks & Drinks", "Beverages", "discretional", (2.99, 4.59), 0.22),
        ("ACQUA NATURALE 1.5L", "Water", "Snacks & Drinks", "Beverages", "essential", (0.35, 0.69), 0.22),
        ("COCA COLA LATTINA 33CL", "Soda", "Snacks & Drinks", "Beverages", "junk", (0.85, 1.25), 0.22),
        ("PATATINE SAN CARLO 150G", "Chips/Crisps", "Snacks & Drinks", "Savory Snacks", "junk", (1.49, 2.29), 0.22),
        ("DETERSIVO SVELTO PIATTI", "Dish Soap", "Household & Living", "Kitchen & Cleaning", "essential", (1.69, 2.89), 0.22),
        ("CARTA IGIENICA SCOTTEX", "Toilet Paper", "Household & Living", "Kitchen & Cleaning", "essential", (3.20, 5.80), 0.22),
        ("TACHIPIRINA 500MG 20CPR", "Pain Relief", "Personal Care", "Health", "essential", (4.50, 6.20), 0.10),
    ],
    "discounts": [
        "SCONTO CONAD CARD",
        "SCONTO FEDELTA'",
        "PROMO VOLANTINO",
        "BUONO SPESA",
    ],
    "labels": {
        "date": "DATA",
        "time": "ORA",
        "qty": "QTA",
        "price": "PREZZO",
        "amount": "IMPORTO",
        "subtotal": "SUBTOTALE",
        "total": "TOTALE COMPLESSIVO",
        "tax": "IVA",
        "taxable": "IMPONIBILE",
        "vat_amount": "IMPOSTA",
        "payment": "PAGAMENTO ELETTRONICO",
        "change": "RESTO",
        "greeting": "GRAZIE PER LA VISITA E ARRIVEDERCI",
    }
}

CATALOG_FRENCH = {
    "stores": [
        ("CARREFOUR MARKET", "15 Rue de Rennes, 75006 Paris", "FR12345678901", "SIRET 12345678900012", "+33 1 45 44 12 34"),
        ("MONOPRIX NATION", "1 Place de la Nation, 75011 Paris", "FR98765432109", "SIRET 98765432100034", "+33 1 43 72 88 90"),
        ("E.LECLERC CENTRE", "60 Rue Gambetta, 69007 Lyon", "FR45678901234", "SIRET 45678901200056", "+33 4 78 69 45 10"),
        ("AUCHAN SUPERMARCHE", "24 Boulevard Victor Hugo, 59000 Lille", "FR33445566778", "SIRET 33445566700078", "+33 3 20 55 12 00"),
    ],
    "titles": [
        "TICKET DE CAISSE",
        "JUSTIFICATIF DE PAIEMENT",
        "FACTURE SIMPLIFIEE",
    ],
    "items": [
        ("BAGUETTE DE TRADITION", "Artisan Bread", "Pantry & Bakery", "Bakery", "discretional", (1.20, 1.50), 0.055),
        ("LAIT DEMI-ECREME 1L", "Milk (Whole/Skim)", "Proteins & Dairy", "Dairy & Alternatives", "essential", (1.10, 1.65), 0.055),
        ("BEURRE DOUX BRETON 250G", "Butter", "Proteins & Dairy", "Dairy & Alternatives", "essential", (2.30, 3.60), 0.055),
        ("OEUFS PLEIN AIR BIO X6", "Eggs (Standard)", "Proteins & Dairy", "Dairy & Alternatives", "essential", (1.95, 3.10), 0.055),
        ("POULET FERMIER 1.2KG", "Chicken (Whole/Breast/Thighs)", "Proteins & Dairy", "Butcher Counter", "essential", (6.50, 10.50), 0.055),
        ("FROMAGE COMTE AOP 200G", "Cheese (Fancy)", "Proteins & Dairy", "Dairy & Alternatives", "discretional", (3.80, 6.20), 0.055),
        ("EVIAN EAU MINERALE 1.5L", "Water", "Snacks & Drinks", "Beverages", "essential", (0.75, 1.15), 0.055),
        ("CROISSANT PUR BEURRE", "Croissants/Danishes", "Pantry & Bakery", "Bakery", "junk", (1.10, 1.60), 0.10),
        ("LESSIVE LIQUIDE 2L", "Laundry Detergent", "Household & Living", "Kitchen & Cleaning", "essential", (7.50, 12.90), 0.20),
        ("PAPIER TOILETTE 8RLX", "Toilet Paper", "Household & Living", "Kitchen & Cleaning", "essential", (3.20, 5.40), 0.20),
    ],
    "discounts": [
        "REMISE CARTE FIDELITE",
        "AVANTAGE PROMO",
        "BON D'ACHAT",
    ],
    "labels": {
        "date": "DATE",
        "time": "HEURE",
        "qty": "QTE",
        "price": "P.U.",
        "amount": "MONTANT",
        "subtotal": "SOUS-TOTAL HT",
        "total": "TOTAL TTC",
        "tax": "TVA",
        "taxable": "BASE HT",
        "vat_amount": "MT TVA",
        "payment": "CARTE BANCAIRE",
        "change": "RENDU",
        "greeting": "MERCI DE VOTRE VISITE ET A BIENTOT",
    }
}

CATALOG_GERMAN = {
    "stores": [
        ("REWE MARKT GMBH", "Friedrichstrasse 100, 10117 Berlin", "DE123456789", "ST.-NR. 12/345/67890", "+49 30 2045 1100"),
        ("ALDI SUED GMBH", "Leopoldstrasse 45, 80802 Muenchen", "DE987654321", "ST.-NR. 98/765/43210", "+49 89 3817 990"),
        ("EDEKA FRISCHECENTER", "Moenckebergstrasse 22, 20095 Hamburg", "DE456789012", "ST.-NR. 45/678/90123", "+49 40 3287 440"),
        ("DM-DROGERIE MARKT", "Zeil 105, 60313 Frankfurt am Main", "DE334455667", "ST.-NR. 33/445/56678", "+49 69 2199 880"),
    ],
    "titles": [
        "KASSENBON",
        "KASSENZETTEL",
        "KAUFBELEG",
    ],
    "items": [
        ("BIO BANANEN 1KG", "Bananas", "Fresh Produce", "Fruits", "essential", (1.79, 2.59), 0.07),
        ("FRISCHE VOLLMILCH 3.8% 1L", "Milk (Whole/Skim)", "Proteins & Dairy", "Dairy & Alternatives", "essential", (1.15, 1.75), 0.07),
        ("FREILANDEIER 10ER PACK", "Eggs (Standard)", "Proteins & Dairy", "Dairy & Alternatives", "essential", (2.49, 3.69), 0.07),
        ("DEUTSCHE MARKENBUTTER 250G", "Butter", "Proteins & Dairy", "Dairy & Alternatives", "essential", (2.19, 3.49), 0.07),
        ("VOLLKORNBROT 500G", "Sliced Bread", "Pantry & Bakery", "Bakery", "essential", (1.69, 2.89), 0.07),
        ("GOUDA JUNG 400G", "Cheese (Cheddar/Mozzarella)", "Proteins & Dairy", "Dairy & Alternatives", "essential", (2.99, 4.69), 0.07),
        ("MINERALWASSER MEDIUM 1L", "Water", "Snacks & Drinks", "Beverages", "essential", (0.45, 0.95), 0.19),
        ("SCHOKOLADE RITTER SPORT", "Chocolate", "Snacks & Drinks", "Sweet Snacks", "junk", (1.29, 1.89), 0.07),
        ("GESCHIRRSPUELER TABS 30ER", "Dish Soap", "Household & Living", "Kitchen & Cleaning", "essential", (4.50, 7.90), 0.19),
        ("TOILETTENPAPIER 8 ROLLEN", "Toilet Paper", "Household & Living", "Kitchen & Cleaning", "essential", (3.29, 5.49), 0.19),
    ],
    "discounts": [
        "PAYBACK RABATT",
        "AKTIONSRABATT",
        "COUPON VORTEIL",
    ],
    "labels": {
        "date": "DATUM",
        "time": "ZEIT",
        "qty": "STK",
        "price": "EINZEL",
        "amount": "BETRAG",
        "subtotal": "ZWISCHENSUMME",
        "total": "GESAMTBETRAG EUR",
        "tax": "MWST",
        "taxable": "NETTO",
        "vat_amount": "STEUER",
        "payment": "GEGEBEN EC-KARTE",
        "change": "RUECKGELD",
        "greeting": "VIELEN DANK FUER IHREN EINKAUF",
    }
}

CATALOG_ENGLISH = {
    "stores": [
        ("WHOLE FOODS MARKET", "1044 Market St, San Francisco, CA 94103", "US-CA-94103-8821", "REG #04", "+1 (415) 552-1155"),
        ("TARGET STORE T-1200", "789 Broadway Ave, New York, NY 10003", "US-NY-10003-1104", "REG #08", "+1 (212) 674-8800"),
        ("TESCO EXPRESS LONDON", "12 Oxford St, London W1D 1AN", "GB123456789", "POS #02", "+44 20 7437 1122"),
        ("SAINSBURY'S LOCAL", "45 Strand, London WC2N 5LT", "GB987654321", "POS #05", "+44 20 7839 4411"),
    ],
    "titles": [
        "RECEIPT",
        "TAX INVOICE",
        "CUSTOMER RECEIPT",
    ],
    "items": [
        ("ORGANIC BANANAS 2LB", "Bananas", "Fresh Produce", "Fruits", "essential", (1.49, 2.49), 0.0825),
        ("WHOLE MILK 1 GALLON", "Milk (Whole/Skim)", "Proteins & Dairy", "Dairy & Alternatives", "essential", (3.49, 4.89), 0.0825),
        ("ORGANIC EGGS GRADE A 12CT", "Eggs (Standard)", "Proteins & Dairy", "Dairy & Alternatives", "essential", (3.99, 5.49), 0.0825),
        ("WHOLE WHEAT BREAD 24OZ", "Sliced Bread", "Pantry & Bakery", "Bakery", "essential", (2.79, 3.99), 0.0825),
        ("GROUND BEEF 80/20 1LB", "Ground Beef/Pork/Turkey", "Proteins & Dairy", "Butcher Counter", "essential", (4.99, 7.49), 0.0825),
        ("SPRING WATER 24PK", "Water", "Snacks & Drinks", "Beverages", "essential", (3.99, 5.99), 0.0825),
        ("POTATO CHIPS SEA SALT 8OZ", "Chips/Crisps", "Snacks & Drinks", "Savory Snacks", "junk", (3.29, 4.99), 0.0825),
        ("LIQUID DISH SOAP 24OZ", "Dish Soap", "Household & Living", "Kitchen & Cleaning", "essential", (2.89, 4.19), 0.0825),
        ("BATH TISSUE 12 ROLLS", "Toilet Paper", "Household & Living", "Kitchen & Cleaning", "essential", (8.99, 13.99), 0.0825),
    ],
    "discounts": [
        "MEMBER SAVINGS",
        "STORE COUPON",
        "LOYALTY DISCOUNT",
    ],
    "labels": {
        "date": "DATE",
        "time": "TIME",
        "qty": "QTY",
        "price": "PRICE",
        "amount": "TOTAL",
        "subtotal": "SUBTOTAL",
        "total": "TOTAL AMOUNT",
        "tax": "SALES TAX",
        "taxable": "TAXABLE",
        "vat_amount": "TAX AMT",
        "payment": "VISA CONTACTLESS",
        "change": "CHANGE DUE",
        "greeting": "THANK YOU FOR SHOPPING WITH US",
    }
}


# ══════════════════════════════════════════════════════════════════════════════
# 2. LOCALIZED CONTENT GENERATION
# ══════════════════════════════════════════════════════════════════════════════

def format_localized_price(val: float, lang: str) -> str:
    """Formats float price with appropriate decimal separator and symbol."""
    if lang in ("it", "fr", "de"):
        formatted = f"{val:.2f}".replace(".", ",")
        return f"{formatted} €"
    else:
        return f"${val:.2f}"


def generate_receipt_content(lang: str) -> Dict[str, Any]:
    """Generates structured receipt metadata and line items for a specific language."""
    if lang == "it":
        cat = CATALOG_ITALIAN
        currency = "EUR"
    elif lang == "fr":
        cat = CATALOG_FRENCH
        currency = "EUR"
    elif lang == "de":
        cat = CATALOG_GERMAN
        currency = "EUR"
    else:
        cat = CATALOG_ENGLISH
        currency = "USD" if "US" in cat["stores"][0][2] else "GBP"

    store_name, address, vat_no, reg_id, phone = random.choice(cat["stores"])
    title = random.choice(cat["titles"])

    # Date / Time
    days_ago = random.randint(0, 180)
    dt = datetime.now() - timedelta(days=days_ago)
    iso_date = dt.strftime("%Y-%m-%d")
    
    if lang in ("it", "fr"):
        disp_date = dt.strftime("%d/%m/%Y")
    elif lang == "de":
        disp_date = dt.strftime("%d.%m.%Y")
    else:
        disp_date = dt.strftime("%Y-%m-%d")

    time_str = f"{random.randint(8, 21):02d}:{random.randint(0, 59):02d}"

    # Pick 4 to 12 items
    num_items = random.randint(4, 12)
    pool = cat["items"]
    chosen_specs = random.sample(pool, min(num_items, len(pool)))

    items_json = []
    items_render = []
    subtotal = 0.0
    tax_accum: Dict[float, float] = {}

    for spec in chosen_specs:
        raw_name, norm_name, main_cat, sub_cat, necessity, (min_p, max_p), tax_rate = spec
        qty = random.choices([1, 2, 3], weights=[0.8, 0.15, 0.05])[0]
        unit_p = round(random.uniform(min_p, max_p), 2)
        item_total = round(unit_p * qty, 2)

        # 10% chance of an item-level promotional discount
        has_discount = random.random() < 0.12
        discount_amount = 0.0
        discount_label = ""
        if has_discount:
            discount_amount = round(random.uniform(0.30, min(1.50, item_total * 0.4)), 2)
            discount_label = random.choice(cat["discounts"])

        final_item_price = round(item_total - discount_amount, 2)
        subtotal += final_item_price

        # Accumulate tax
        tax_accum[tax_rate] = tax_accum.get(tax_rate, 0.0) + final_item_price

        items_json.append({
            "raw_name": raw_name,
            "normalized_name": norm_name,
            "main_category": main_cat,
            "sub_category": sub_cat,
            "necessity": necessity,
            "quantity": qty,
            "unit_price": unit_p,
            "total_price": final_item_price,
            "is_asset": False
        })

        items_render.append({
            "raw_name": raw_name,
            "qty": qty,
            "unit_p": unit_p,
            "item_total": item_total,
            "discount_amount": discount_amount,
            "discount_label": discount_label,
            "final_price": final_item_price,
            "tax_rate": tax_rate,
        })

    # Calculate tax breakdown
    tax_breakdown_json = []
    total_tax = 0.0
    for rate, taxable_amt in tax_accum.items():
        tax_amt = round(taxable_amt * rate, 2)
        total_tax += tax_amt
        tax_breakdown_json.append({
            "rate": rate,
            "tax_amount": tax_amt
        })

    grand_total = round(subtotal + (total_tax if lang == "en" else 0.0), 2)
    if lang != "en":
        # In Europe, prices on receipts are already IVA/TVA inclusive
        grand_total = round(subtotal, 2)

    confidence = round(random.uniform(0.93, 0.99), 2)

    ground_truth = {
        "merchant_name": store_name,
        "merchant_address": address,
        "vat_number": vat_no,
        "date": iso_date,
        "time": time_str,
        "currency": currency,
        "items": items_json,
        "tax_breakdown": tax_breakdown_json,
        "total_amount": grand_total,
        "confidence_score": confidence,
    }

    render_data = {
        "lang": lang,
        "currency": currency,
        "store_name": store_name,
        "address": address,
        "vat_no": vat_no,
        "reg_id": reg_id,
        "phone": phone,
        "title": title,
        "disp_date": disp_date,
        "time_str": time_str,
        "items": items_render,
        "subtotal": subtotal,
        "tax_accum": tax_accum,
        "tax_breakdown": tax_breakdown_json,
        "grand_total": grand_total,
        "labels": cat["labels"],
    }

    return ground_truth, render_data


# ══════════════════════════════════════════════════════════════════════════════
# 3. PROCEDURAL RECEIPT CANVAS RENDERING (PILLOW)
# ══════════════════════════════════════════════════════════════════════════════

def create_thermal_paper_background(width: int, height: int) -> Image.Image:
    """Generates a realistic thermal receipt background with texture noise and paper tint."""
    # Warm off-white / thermal paper tone [244..250]
    base_color = np.random.randint(245, 252, size=(height, width, 3), dtype=np.uint8)
    # Add subtle paper fiber noise
    noise = np.random.normal(0, 2.5, (height, width, 3)).astype(np.int16)
    blended = np.clip(base_color.astype(np.int16) + noise, 235, 255).astype(np.uint8)
    return Image.fromarray(blended, mode="RGB")


def render_receipt_image(render_data: Dict[str, Any]) -> Image.Image:
    """Renders formatted multi-column receipt text onto a realistic thermal paper canvas."""
    lang = render_data["lang"]
    labels = render_data["labels"]
    items = render_data["items"]

    # Canvas dimensions
    width = 640
    line_count = len(items) * 2 + len(render_data["tax_breakdown"]) + 20
    height = max(700, 360 + line_count * 24)

    img = create_thermal_paper_background(width, height)
    draw = ImageDraw.Draw(img)

    # Load fallback or custom fonts
    try:
        font_regular = ImageFont.load_default()
        font_bold = ImageFont.load_default()
    except Exception:
        font_regular = None
        font_bold = None

    y = 28

    # Top serration / cut pattern
    for x in range(20, width - 20, 16):
        draw.line([(x, y - 8), (x + 8, y - 14)], fill=(210, 210, 205), width=1)
        draw.line([(x + 8, y - 14), (x + 16, y - 8)], fill=(210, 210, 205), width=1)

    y += 10
    # Store Header
    draw.text((width // 2 - 130, y), render_data["title"], fill=(80, 80, 80), font=font_regular)
    y += 24
    draw.text((width // 2 - 140, y), render_data["store_name"], fill=(20, 20, 20), font=font_bold)
    y += 26
    draw.text((width // 2 - 150, y), render_data["address"], fill=(60, 60, 60), font=font_regular)
    y += 18
    draw.text((width // 2 - 120, y), f"TEL: {render_data['phone']}", fill=(70, 70, 70), font=font_regular)
    y += 18
    draw.text((width // 2 - 140, y), f"P.IVA / VAT: {render_data['vat_no']}", fill=(60, 60, 60), font=font_regular)
    y += 18
    draw.text((width // 2 - 90, y), render_data["reg_id"], fill=(90, 90, 90), font=font_regular)
    y += 22

    # Divider line
    draw.line([(30, y), (width - 30, y)], fill=(120, 120, 120), width=1)
    y += 12

    # Date / Time
    draw.text((40, y), f"{labels['date']}: {render_data['disp_date']}", fill=(50, 50, 50), font=font_regular)
    draw.text((width - 160, y), f"{labels['time']}: {render_data['time_str']}", fill=(50, 50, 50), font=font_regular)
    y += 22
    draw.line([(30, y), (width - 30, y)], fill=(120, 120, 120), width=1)
    y += 16

    # Column Headers
    draw.text((40, y), labels["amount"] if lang == "en" else "DESCRIZIONE", fill=(40, 40, 40), font=font_bold)
    draw.text((360, y), labels["qty"], fill=(40, 40, 40), font=font_bold)
    draw.text((430, y), labels["price"], fill=(40, 40, 40), font=font_bold)
    draw.text((520, y), labels["amount"], fill=(40, 40, 40), font=font_bold)
    y += 20
    draw.line([(30, y), (width - 30, y)], fill=(160, 160, 160), width=1)
    y += 14

    # Render Line Items
    for it in items:
        name_trunc = it["raw_name"][:28]
        draw.text((40, y), name_trunc, fill=(20, 20, 20), font=font_regular)
        draw.text((370, y), str(it["qty"]), fill=(20, 20, 20), font=font_regular)
        draw.text((430, y), format_localized_price(it["unit_p"], lang), fill=(20, 20, 20), font=font_regular)
        draw.text((520, y), format_localized_price(it["item_total"], lang), fill=(20, 20, 20), font=font_regular)
        y += 22

        # Nested discount line if applicable
        if it["discount_amount"] > 0:
            draw.text((60, y), f">> {it['discount_label']}", fill=(180, 30, 30), font=font_regular)
            draw.text((510, y), f"-{format_localized_price(it['discount_amount'], lang)}", fill=(180, 30, 30), font=font_regular)
            y += 20

        y += 6

    y += 10
    draw.line([(30, y), (width - 30, y)], fill=(120, 120, 120), width=1)
    y += 16

    # Subtotal
    draw.text((280, y), f"{labels['subtotal']}:", fill=(60, 60, 60), font=font_regular)
    draw.text((490, y), format_localized_price(render_data["subtotal"], lang), fill=(60, 60, 60), font=font_regular)
    y += 24

    # Grouped Tax Breakdown Table
    draw.line([(280, y), (width - 30, y)], fill=(190, 190, 190), width=1)
    y += 10
    for tb in render_data["tax_breakdown"]:
        rate_pct = f"{tb['rate']*100:.1f}%"
        tax_line = f"{labels['tax']} {rate_pct}:"
        draw.text((280, y), tax_line, fill=(80, 80, 80), font=font_regular)
        draw.text((490, y), format_localized_price(tb["tax_amount"], lang), fill=(80, 80, 80), font=font_regular)
        y += 20

    y += 8
    draw.line([(270, y), (width - 30, y)], fill=(30, 30, 30), width=2)
    y += 12

    # Grand Total
    draw.text((270, y), f"{labels['total']}:", fill=(10, 10, 10), font=font_bold)
    draw.text((470, y), format_localized_price(render_data["grand_total"], lang), fill=(10, 10, 10), font=font_bold)
    y += 36

    # Payment details
    draw.text((40, y), f"{labels['payment']}", fill=(60, 60, 60), font=font_regular)
    draw.text((480, y), format_localized_price(render_data["grand_total"], lang), fill=(60, 60, 60), font=font_regular)
    y += 22
    draw.text((40, y), f"{labels['change']}", fill=(60, 60, 60), font=font_regular)
    draw.text((480, y), format_localized_price(0.0, lang), fill=(60, 60, 60), font=font_regular)
    y += 36

    # Barcode representation
    bc_y = y
    random.seed(render_data["vat_no"])
    for bx in range(width // 2 - 120, width // 2 + 120, 4):
        if random.random() > 0.35:
            bar_w = random.choice([1, 2, 3])
            draw.rectangle([(bx, bc_y), (bx + bar_w, bc_y + 40)], fill=(30, 30, 30))
    random.seed()

    y += 54
    # Greeting / Farewell
    draw.text((width // 2 - 140, y), labels["greeting"], fill=(90, 90, 90), font=font_regular)
    y += 36

    # Crop to final height with padding
    final_height = y + 20
    return img.crop((0, 0, width, final_height))


# ══════════════════════════════════════════════════════════════════════════════
# 4. OPTICAL & PHYSICAL CAMERA AUGMENTATIONS (NUMPY / PIL)
# ══════════════════════════════════════════════════════════════════════════════

def apply_homography_warp(img: Image.Image) -> Image.Image:
    """Applies a realistic perspective quad transform simulating camera angle/tilt."""
    w, h = img.size
    # Perturb corners by up to 25 pixels
    dx1, dy1 = random.randint(-18, 18), random.randint(-15, 15)
    dx2, dy2 = random.randint(-18, 18), random.randint(-15, 15)
    dx3, dy3 = random.randint(-18, 18), random.randint(-15, 15)
    dx4, dy4 = random.randint(-18, 18), random.randint(-15, 15)

    src_quad = [
        (0 + dx1, 0 + dy1),
        (w + dx2, 0 + dy2),
        (w + dx3, h + dy3),
        (0 + dx4, h + dy4)
    ]

    # Transform using Pillow QUAD mapping
    flat_quad = [coord for pt in src_quad for coord in pt]
    warped = img.transform(
        (w, h),
        Image.QUAD,
        flat_quad,
        resample=Image.BICUBIC,
        fillcolor=(235, 235, 230)
    )
    return warped


def apply_lighting_and_shadows(img: Image.Image) -> Image.Image:
    """Applies non-uniform linear lighting gradient and subtle radial hand shadow."""
    arr = np.array(img, dtype=np.float32)
    h, w, c = arr.shape

    # 1. Linear directional lighting gradient
    angle = random.uniform(0, 2 * math.pi)
    x = np.linspace(-1.0, 1.0, w)
    y = np.linspace(-1.0, 1.0, h)
    xx, yy = np.meshgrid(x, y)
    gradient = math.cos(angle) * xx + math.sin(angle) * yy
    gradient_norm = (gradient - gradient.min()) / (gradient.max() - gradient.min() + 1e-6)
    
    # Mild intensity (0.88 to 1.08)
    lighting = 0.88 + 0.20 * gradient_norm
    arr = arr * lighting[:, :, np.newaxis]

    # 2. Synthetic radial shadow (e.g. phone or hand silhouette)
    if random.random() < 0.65:
        center_x = random.uniform(0.1, 0.9) * w
        center_y = random.uniform(0.1, 0.9) * h
        radius = random.uniform(0.4, 0.9) * max(w, h)

        dist = np.sqrt((np.arange(w)[np.newaxis, :] - center_x)**2 + 
                       (np.arange(h)[:, np.newaxis] - center_y)**2)
        shadow = 1.0 - np.clip((1.0 - dist / radius) * 0.22, 0.0, 0.22)
        arr = arr * shadow[:, :, np.newaxis]

    arr = np.clip(arr, 0, 255).astype(np.uint8)
    return Image.fromarray(arr, mode="RGB")


def apply_optical_degradations(img: Image.Image) -> Image.Image:
    """Applies Gaussian defocus blur and contrast jitter."""
    # Defocus blur
    if random.random() < 0.55:
        radius = random.uniform(0.3, 0.9)
        img = img.filter(ImageFilter.GaussianBlur(radius=radius))

    # Contrast adjustment
    contrast_factor = random.uniform(0.92, 1.12)
    img = ImageEnhance.Contrast(img).enhance(contrast_factor)

    return img


def augment_receipt_image(raw_canvas: Image.Image) -> Image.Image:
    """Applies full augmentation pipeline simulating realistic on-device camera capture."""
    warped = apply_homography_warp(raw_canvas)
    lit = apply_lighting_and_shadows(warped)
    final = apply_optical_degradations(lit)
    return final


# ══════════════════════════════════════════════════════════════════════════════
# 5. CLI & BATCH DATASET GENERATION
# ══════════════════════════════════════════════════════════════════════════════

def select_language_by_distribution() -> str:
    """Picks language matching 50% IT, 20% FR, 15% DE, 15% EN."""
    langs = ["it", "fr", "de", "en"]
    weights = [0.50, 0.20, 0.15, 0.15]
    return random.choices(langs, weights=weights)[0]


def generate_single_sample(index: int, output_dir: str) -> Tuple[str, str]:
    """Generates a single synthetic receipt image and matching GBNF JSON pair."""
    lang = select_language_by_distribution()
    ground_truth, render_data = generate_receipt_content(lang)

    # Render clean canvas
    canvas = render_receipt_image(render_data)

    # Apply camera augmentations
    final_img = augment_receipt_image(canvas)

    # File paths
    base_name = f"receipt_{lang}_{index:06d}"
    jpg_path = os.path.join(output_dir, f"{base_name}.jpg")
    json_path = os.path.join(output_dir, f"{base_name}.json")

    # Save image with realistic JPEG compression (quality 68..90)
    jpeg_quality = random.randint(68, 90)
    final_img.save(jpg_path, format="JPEG", quality=jpeg_quality, optimize=True)

    # Save matching ground truth JSON
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(ground_truth, f, indent=2, ensure_ascii=False)

    return jpg_path, json_path


def main():
    parser = argparse.ArgumentParser(
        description="Procedural Multilingual Receipt Dataset Generator for On-Device VLM Training"
    )
    parser.add_argument(
        "--count",
        type=int,
        default=50,
        help="Number of paired receipt image and JSON samples to generate"
    )
    parser.add_argument(
        "--output_dir",
        type=str,
        default="./synthetic_dataset",
        help="Target output directory"
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=42,
        help="Random seed for reproducibility"
    )
    args = parser.parse_args()

    random.seed(args.seed)
    np.random.seed(args.seed)
    os.makedirs(args.output_dir, exist_ok=True)

    print("==================================================================")
    print("Procedural Multilingual Receipt Generator")
    print(f"Target count:      {args.count}")
    print(f"Output directory:  {args.output_dir}")
    print("Distribution:      50% Italian, 20% French, 15% German, 15% English")
    print("Taxonomy:          Aligned with tAIdy TaxonomyConstants & GBNF")
    print("==================================================================")

    for i in range(args.count):
        jpg, js = generate_single_sample(i + 1, args.output_dir)
        if (i + 1) % 10 == 0 or (i + 1) == args.count:
            print(f"[{i + 1}/{args.count}] Generated {os.path.basename(jpg)} + {os.path.basename(js)}")

    print("==================================================================")
    print(f"Successfully generated {args.count} paired training samples in {args.output_dir}")
    print("==================================================================")


if __name__ == "__main__":
    main()
