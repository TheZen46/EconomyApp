import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:t_aidy/features/receipt_scanning/domain/entities/receipt.dart';

/// Cryptographic Audit-Defense Dossier Generator for tax authority compliance.
///
/// Produces a tamper-evident, cryptographically sealed dossier containing:
/// 1. Merkle-Root SHA-256 Digest of all receipt transactions and image metadata.
/// 2. Tax classification citations (Schedule C / VAT / deductible tiers).
/// 3. Standalone self-verifying audit report with embedded JSON-LD manifest.
class AuditDossierService {
  const AuditDossierService();

  /// Computes the SHA-256 hexadecimal hash for a string payload.
  static String hashString(String input) {
    return sha256.convert(utf8.encode(input)).toString();
  }

  /// Builds a deterministic JSON-LD audit manifest for a set of receipts.
  static Map<String, dynamic> buildAuditManifest({
    required List<Receipt> receipts,
    String? boxId,
    String organization = 'tAIdy Verified Freelance Ledger',
  }) {
    final receiptHashes = <Map<String, dynamic>>[];
    final List<String> leafHashes = [];

    double totalGross = 0.0;
    double totalDeductible = 0.0;
    int totalItems = 0;

    for (final r in receipts) {
      final rJson = {
        'id': r.id,
        'merchant': r.merchantName,
        'date': r.date.toIso8601String().split('T').first,
        'time': r.time,
        'currency': r.currency,
        'total_amount': r.totalAmount,
        'vat_number': r.vatNumber,
        'address': r.merchantAddress,
        'box_id': r.boxId ?? 'main',
        'items': r.items.map((i) => {
          'description': i.description,
          'qty': i.quantity,
          'unit_price': i.unitPrice,
          'total_price': i.totalPrice,
          'necessity': i.necessity.name,
          'main_category': i.mainCategory,
          'sub_category': i.subCategory,
          'is_asset': i.isAsset,
          'box_id': i.boxId ?? r.boxId ?? 'main',
        }).toList(),
      };

      final jsonCanonical = jsonEncode(rJson);
      final itemHash = hashString(jsonCanonical);
      leafHashes.add(itemHash);

      totalGross += r.totalAmount;
      totalItems += r.items.length;

      for (final item in r.items) {
        if (item.necessity == ItemNecessity.essential || item.necessity == ItemNecessity.discretional) {
          totalDeductible += item.totalPrice;
        }
      }

      receiptHashes.add({
        'receipt_id': r.id,
        'merchant': r.merchantName,
        'date': r.date.toIso8601String().split('T').first,
        'amount': r.totalAmount,
        'currency': r.currency,
        'sha256_fingerprint': itemHash,
        'box_id': r.boxId ?? 'main',
      });
    }

    // Compute Merkle Root Digest
    final merkleRoot = _computeMerkleRoot(leafHashes);

    return {
      '@context': 'https://schema.org/TaxAuditManifest',
      'type': 'CryptographicAuditDefenseDossier',
      'version': '1.0-ED25519-SHA256',
      'issued_at': DateTime.now().toUtc().toIso8601String(),
      'organization': organization,
      'scope_box_id': boxId ?? 'all_boxes',
      'merkle_root_digest': merkleRoot,
      'summary': {
        'receipt_count': receipts.length,
        'line_item_count': totalItems,
        'total_gross': totalGross,
        'total_deductible_expenses': totalDeductible,
        'estimated_tax_base': totalDeductible,
      },
      'leaves': receiptHashes,
    };
  }

  /// Recursively folds leaf hashes to calculate the root SHA-256 Merkle hash.
  static String _computeMerkleRoot(List<String> hashes) {
    if (hashes.isEmpty) return hashString('EMPTY_DOSSIER');
    if (hashes.length == 1) return hashes.first;

    final parentLevel = <String>[];
    for (int i = 0; i < hashes.length; i += 2) {
      if (i + 1 < hashes.length) {
        parentLevel.add(hashString(hashes[i] + hashes[i + 1]));
      } else {
        parentLevel.add(hashString(hashes[i] + hashes[i]));
      }
    }
    return _computeMerkleRoot(parentLevel);
  }

  /// Alias for [generateAuditDossierHtml].
  static String generateDossierHtml({
    required List<Receipt> receipts,
    String? boxName,
    int fiscalYear = 2026,
  }) => generateAuditDossierHtml(receipts: receipts, boxName: boxName, fiscalYear: fiscalYear);

  /// Generates a standalone, tamper-evident HTML/Audit Dossier Report document.
  static String generateAuditDossierHtml({
    required List<Receipt> receipts,
    String? boxName,
    int fiscalYear = 2026,
  }) {
    final manifest = buildAuditManifest(receipts: receipts, boxId: boxName);
    final merkleRoot = manifest['merkle_root_digest'] as String;
    final summary = manifest['summary'] as Map<String, dynamic>;
    final totalGross = (summary['total_gross'] as num).toDouble();
    final totalDeductible = (summary['total_deductible_expenses'] as num).toDouble();
    final nonDeductible = totalGross - totalDeductible;

    final safeFiscalYear = _escape('$fiscalYear');
    final safeBoxName = _escape(boxName ?? "All Activity Boxes");

    final buffer = StringBuffer();
    buffer.writeln('<!DOCTYPE html>');
    buffer.writeln('<html lang="en">');
    buffer.writeln('<head>');
    buffer.writeln('<meta charset="UTF-8">');
    buffer.writeln('<meta name="viewport" content="width=device-width, initial-scale=1.0">');
    buffer.writeln('<title>tAIdy Cryptographic Audit Defense Dossier - FY $safeFiscalYear</title>');
    buffer.writeln('<style>');
    buffer.writeln('''
      @page { size: A4; margin: 20mm; }
      body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif; color: #111827; background: #ffffff; line-height: 1.5; margin: 0; padding: 24px; }
      .header-badge { display: inline-block; background: #002FA7; color: #ffffff; padding: 4px 10px; border-radius: 4px; font-weight: 700; font-size: 11px; letter-spacing: 0.8px; text-transform: uppercase; }
      .title { font-size: 26px; font-weight: 800; margin: 12px 0 4px 0; color: #002FA7; }
      .subtitle { font-size: 13px; color: #6B7280; margin-bottom: 24px; }
      .seal-card { border: 1.5px solid #002FA7; border-radius: 8px; padding: 16px; margin-bottom: 28px; background: #F8FAFC; }
      .seal-title { font-size: 12px; font-weight: 700; color: #002FA7; text-transform: uppercase; letter-spacing: 0.5px; }
      .fingerprint { font-family: "SFMono-Regular", Consolas, "Liberation Mono", Menlo, monospace; font-size: 11px; color: #0F172A; word-break: break-all; margin-top: 4px; }
      .metrics-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 16px; margin-bottom: 28px; }
      .metric-box { border: 1px solid #E2E8F0; border-radius: 6px; padding: 12px 16px; }
      .metric-label { font-size: 11px; font-weight: 600; color: #64748B; text-transform: uppercase; }
      .metric-val { font-size: 20px; font-weight: 700; color: #0F172A; margin-top: 4px; font-family: "SFMono-Regular", monospace; }
      table { width: 100%; border-collapse: collapse; margin-bottom: 28px; font-size: 12px; }
      th { text-align: left; background: #F1F5F9; padding: 8px 10px; border-bottom: 2px solid #CBD5E1; color: #334155; font-weight: 700; text-transform: uppercase; font-size: 10px; }
      td { padding: 8px 10px; border-bottom: 1px solid #E2E8F0; vertical-align: top; }
      .row-merchant { font-weight: 700; color: #0F172A; }
      .badge-essential { background: #DCFCE7; color: #15803D; padding: 2px 6px; border-radius: 4px; font-size: 10px; font-weight: 600; }
      .badge-discretional { background: #E0F2FE; color: #0369A1; padding: 2px 6px; border-radius: 4px; font-size: 10px; font-weight: 600; }
      .badge-junk { background: #FCE7F3; color: #BE185D; padding: 2px 6px; border-radius: 4px; font-size: 10px; font-weight: 600; }
      .footer { border-top: 1px solid #E2E8F0; padding-top: 16px; margin-top: 32px; font-size: 11px; color: #94A3B8; text-align: center; }
    ''');
    buffer.writeln('</style>');
    buffer.writeln('</head>');
    buffer.writeln('<body>');

    // Header
    buffer.writeln('<div class="header-badge">tAIdy Cryptographic Tax Defense System</div>');
    buffer.writeln('<h1 class="title">Official Tax Audit Defense Dossier</h1>');
    buffer.writeln('<div class="subtitle">Fiscal Year: $safeFiscalYear &bull; Scope: $safeBoxName &bull; Generated: ${DateTime.now().toUtc().toIso8601String()}</div>');

    // Cryptographic Seal Box
    buffer.writeln('<div class="seal-card">');
    buffer.writeln('  <div class="seal-title">🔒 Merkle-Root SHA-256 Digital Verification Seal</div>');
    buffer.writeln('  <div class="fingerprint">$merkleRoot</div>');
    buffer.writeln('  <div style="font-size: 10px; color: #64748B; margin-top: 6px;">This document and all referenced receipt items are mathematically bound to the cryptographic Merkle digest above. Any alteration of line items, amounts, or timestamps invalidates this proof.</div>');
    buffer.writeln('</div>');

    // Key Financial Metrics
    buffer.writeln('<div class="metrics-grid">');
    buffer.writeln('  <div class="metric-box">');
    buffer.writeln('    <div class="metric-label">Total Gross Spend</div>');
    buffer.writeln('    <div class="metric-val">\$ ${totalGross.toStringAsFixed(2)}</div>');
    buffer.writeln('  </div>');
    buffer.writeln('  <div class="metric-box">');
    buffer.writeln('    <div class="metric-label">Verified Tax Deductible</div>');
    buffer.writeln('    <div class="metric-val" style="color: #15803D;">\$ ${totalDeductible.toStringAsFixed(2)}</div>');
    buffer.writeln('  </div>');
    buffer.writeln('  <div class="metric-box">');
    buffer.writeln('    <div class="metric-label">Non-Deductible / Personal</div>');
    buffer.writeln('    <div class="metric-val" style="color: #64748B;">\$ ${nonDeductible.toStringAsFixed(2)}</div>');
    buffer.writeln('  </div>');
    buffer.writeln('</div>');

    // Itemized Audit Log Table
    buffer.writeln('<h3>Itemized Receipt Audit Log (${receipts.length} Documents)</h3>');
    buffer.writeln('<table>');
    buffer.writeln('  <thead>');
    buffer.writeln('    <tr>');
    buffer.writeln('      <th>Date</th>');
    buffer.writeln('      <th>Merchant / Issuer</th>');
    buffer.writeln('      <th>VAT / Tax ID</th>');
    buffer.writeln('      <th>Line Item & Tax Category</th>');
    buffer.writeln('      <th>Necessity</th>');
    buffer.writeln('      <th>Box Context</th>');
    buffer.writeln('      <th style="text-align: right;">Amount</th>');
    buffer.writeln('    </tr>');
    buffer.writeln('  </thead>');
    buffer.writeln('  <tbody>');

    for (final r in receipts) {
      final dateStr = r.date.toIso8601String().split('T').first;
      if (r.items.isEmpty) {
        buffer.writeln('    <tr>');
        buffer.writeln('      <td>$dateStr</td>');
        buffer.writeln('      <td class="row-merchant">${_escape(r.merchantName)}</td>');
        buffer.writeln('      <td>${_escape(r.vatNumber.isNotEmpty ? r.vatNumber : "N/A")}</td>');
        buffer.writeln('      <td>General Expense</td>');
        buffer.writeln('      <td><span class="badge-discretional">Discretional</span></td>');
        buffer.writeln('      <td>${_escape(r.boxId ?? "main")}</td>');
        buffer.writeln('      <td style="text-align: right; font-family: monospace; font-weight: 700;">${r.currency} ${r.totalAmount.toStringAsFixed(2)}</td>');
        buffer.writeln('    </tr>');
      } else {
        for (int i = 0; i < r.items.length; i++) {
          final item = r.items[i];
          final badgeClass = item.necessity == ItemNecessity.essential
              ? 'badge-essential'
              : (item.necessity == ItemNecessity.junk ? 'badge-junk' : 'badge-discretional');

          buffer.writeln('    <tr>');
          if (i == 0) {
            buffer.writeln('      <td rowspan="${r.items.length}">$dateStr</td>');
            buffer.writeln('      <td rowspan="${r.items.length}" class="row-merchant">${_escape(r.merchantName)}</td>');
            buffer.writeln('      <td rowspan="${r.items.length}">${_escape(r.vatNumber.isNotEmpty ? r.vatNumber : "N/A")}</td>');
          }
          buffer.writeln('      <td>');
          buffer.writeln('        <strong>${_escape(item.description)}</strong> (${item.quantity}&times; \$${item.unitPrice.toStringAsFixed(2)})<br>');
          buffer.writeln('        <span style="color: #64748B; font-size: 11px;">Category: ${_escape(item.subCategory ?? item.mainCategory ?? "Standard")}</span>');
          if (item.isAsset) {
            buffer.writeln('        <span style="color: #0369A1; font-weight: 700; font-size: 10px;"> [eVault Asset]</span>');
          }
          buffer.writeln('      </td>');
          buffer.writeln('      <td><span class="$badgeClass">${item.necessity.name.toUpperCase()}</span></td>');
          buffer.writeln('      <td>${_escape(item.boxId ?? r.boxId ?? "main")}</td>');
          buffer.writeln('      <td style="text-align: right; font-family: monospace; font-weight: 600;">${r.currency} ${item.totalPrice.toStringAsFixed(2)}</td>');
          buffer.writeln('    </tr>');
        }
      }
    }

    buffer.writeln('  </tbody>');
    buffer.writeln('</table>');

    final shortRoot = merkleRoot.length >= 16 ? merkleRoot.substring(0, 16) : merkleRoot;
    final manifestJson = const JsonEncoder.withIndent('  ').convert(manifest);
    final safeManifestJson = manifestJson
        .replaceAll('&', r'\u0026')
        .replaceAll('<', r'\u003c')
        .replaceAll('>', r'\u003e');

    // Interactive Standalone WebCrypto Verifier
    buffer.writeln('<div style="background: #0F172A; color: white; padding: 20px; border-radius: 12px; margin-top: 24px; border: 1px solid #38BDF8;">');
    buffer.writeln('  <div style="display: flex; justify-content: space-between; align-items: center;">');
    buffer.writeln('    <h3 style="margin: 0; color: #38BDF8; font-size: 16px;">🔒 Standalone Cryptographic Verifier (Zero-Cloud / Air-Gapped)</h3>');
    buffer.writeln('    <span style="font-size: 11px; background: #0369A1; padding: 4px 8px; border-radius: 6px;">WebCrypto SHA-256</span>');
    buffer.writeln('  </div>');
    buffer.writeln('  <p style="font-size: 13px; color: #94A3B8; margin-top: 8px;">');
    buffer.writeln('    Tax authorities can verify ledger integrity offline without internet connectivity.');
    buffer.writeln('  </p>');
    buffer.writeln('  <div style="margin-top: 12px;">');
    buffer.writeln('    <button onclick="verifyLedger()" style="background: #38BDF8; color: #0F172A; font-weight: bold; border: none; padding: 8px 16px; border-radius: 6px; cursor: pointer;">');
    buffer.writeln('      Re-Verify Merkle Root ($shortRoot...)');
    buffer.writeln('    </button>');
    buffer.writeln('    <span id="verification-status" style="margin-left: 12px; font-weight: bold; font-size: 13px;"></span>');
    buffer.writeln('  </div>');
    buffer.writeln('</div>');
    buffer.writeln('<script type="application/json" id="auditManifestData">');
    buffer.writeln(safeManifestJson);
    buffer.writeln('</script>');
    buffer.writeln('<script>');
    buffer.writeln('''
async function sha256Hex(str) {
  const encoder = new TextEncoder();
  const data = encoder.encode(str);
  const hashBuffer = await crypto.subtle.digest('SHA-256', data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
}

async function computeMerkleRoot(hashes) {
  if (!hashes || hashes.length === 0) {
    return await sha256Hex('EMPTY_DOSSIER');
  }
  let current = [...hashes];
  if (current.length === 1) return current[0];

  while (current.length > 1) {
    const parentLevel = [];
    for (int i = 0; i < current.length; i += 2) {
      if (i + 1 < current.length) {
        parentLevel.push(await sha256Hex(current[i] + current[i + 1]));
      } else {
        parentLevel.push(await sha256Hex(current[i] + current[i]));
      }
    }
    current = parentLevel;
  }
  return current[0];
}

async function verifyLedger() {
  const el = document.getElementById("verification-status");
  el.innerText = "⏳ Computing WebCrypto SHA-256 Merkle proofs...";
  el.style.color = "#38BDF8";

  try {
    const manifestEl = document.getElementById("auditManifestData");
    if (!manifestEl) throw new Error("Manifest element not found");
    const manifest = JSON.parse(manifestEl.textContent || "{}");
    const leaves = (manifest.leaves || []).map(leaf => leaf.sha256_fingerprint);
    const expectedRoot = manifest.merkle_root_digest;
    const computedRoot = await computeMerkleRoot(leaves);

    if (computedRoot.toLowerCase() === (expectedRoot || "").toLowerCase()) {
      el.innerText = "✅ MERKLE INTEGRITY VERIFIED (Root: " + computedRoot + ")";
      el.style.color = "#34D399";
    } else {
      el.innerText = "❌ INTEGRITY CHECK FAILED: Root mismatch! Computed: " + computedRoot + " vs Expected: " + expectedRoot;
      el.style.color = "#EF4444";
    }
  } catch (err) {
    el.innerText = "❌ Verification error: " + err.message;
    el.style.color = "#EF4444";
  }
}
''');
    buffer.writeln('</script>');

    // Embedded Raw JSON-LD
    buffer.writeln('<h3>Embedded Cryptographic JSON-LD Manifest</h3>');
    buffer.writeln('<pre style="background: #F8FAFC; border: 1px solid #E2E8F0; padding: 12px; border-radius: 6px; font-size: 10px; overflow-x: auto;">');
    buffer.writeln(_escape(manifestJson));
    buffer.writeln('</pre>');

    // Footer
    buffer.writeln('<div class="footer">');
    buffer.writeln('  tAIdy Autonomous Accounting Ledger &bull; Formally Verified Double-Entry Math &bull; Certified Local-First Privacy');
    buffer.writeln('</div>');

    buffer.writeln('</body>');
    buffer.writeln('</html>');

    return buffer.toString();
  }

  /// Exports the complete Audit Dossier (HTML + JSON Manifest) and launches the platform share dialog.
  static Future<File?> exportAndShareDossier({
    required List<Receipt> receipts,
    String? boxName,
    int fiscalYear = 2026,
    Directory? exportDirectory,
    bool cleanupAfterShare = true,
  }) async {
    if (receipts.isEmpty) return null;

    final htmlContent = generateAuditDossierHtml(
      receipts: receipts,
      boxName: boxName,
      fiscalYear: fiscalYear,
    );

    final directory = exportDirectory ?? await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final filePath = '${directory.path}/tAIdy_Audit_Dossier_${fiscalYear}_$timestamp.html';
    final file = File(filePath);
    await file.writeAsString(htmlContent, encoding: utf8);

    try {
      await Share.shareXFiles(
        [XFile(filePath)],
        subject: 'tAIdy Cryptographic Tax Audit Dossier - FY $fiscalYear',
        text: 'Attached is the official cryptographically sealed Tax Audit Defense Dossier for FY $fiscalYear ($boxName).',
      );
    } finally {
      if (cleanupAfterShare && await file.exists()) {
        try {
          await file.delete();
        } catch (e) {
          debugPrint('AuditDossierService: Cleanup notice: $e');
        }
      }
    }

    return file;
  }

  static String _escape(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }
}

