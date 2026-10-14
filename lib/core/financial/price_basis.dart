/// Pricing basis indicating whether amounts include or exclude VAT.
enum PriceBasis {
  /// Gross amounts (VAT-inclusive). Standard for consumer and retail cash receipts.
  gross,

  /// Net amounts (VAT-exclusive). Standard for B2B commercial invoices.
  net;

  static PriceBasis fromString(String? value) {
    if (value == null) return PriceBasis.gross;
    final lower = value.toLowerCase().trim();
    if (lower == 'net') return PriceBasis.net;
    return PriceBasis.gross;
  }
}
