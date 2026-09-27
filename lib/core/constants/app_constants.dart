/// Centralized application constants for the tAIdy financial ecosystem.
///
/// Contains parameter defaults, supported currencies, keyword taxonomies,
/// numerical limits, and design system formatting rules.
class AppConstants {
  // Prevent instantiation
  AppConstants._();

  /// Default application categories used for initial transaction classification.
  static const List<String> categories = [
    'Grocery',
    'Tech',
    'Transport',
    'Restaurant',
    'Health',
    'Education',
    'Home',
    'Clothing',
    'Gift',
    'Other',
  ];

  /// Supported currencies across the multi-currency financial ledger.
  static const List<String> supportedCurrencies = [
    'USD',
    'EUR',
    'GBP',
    'JPY',
    'CHF',
    'CAD',
    'AUD',
  ];

  /// Currency code to symbol mapping.
  static const Map<String, String> currencySymbols = {
    'USD': '\$',
    'EUR': '€',
    'GBP': '£',
    'JPY': '¥',
    'CHF': 'CHF',
    'CAD': 'CA\$',
    'AUD': 'AU\$',
  };

  /// Returns the display symbol for a currency code, falling back to the code itself.
  static String getCurrencySymbol(String currencyCode) {
    return currencySymbols[currencyCode.toUpperCase()] ?? currencyCode;
  }

  /// Formats an amount with currency symbol, respecting privacy mode masking.
  static String formatAmount(
    double amount, {
    String currency = 'USD',
    bool isPrivacy = false,
    int decimals = 2,
  }) {
    if (isPrivacy) {
      return '••••••';
    }
    final symbol = getCurrencySymbol(currency);
    return '$symbol${amount.toStringAsFixed(decimals)}';
  }

  /// Masks sensitive numeric or financial text if privacy mode is active.
  static String privacyMask(String text, {bool isPrivacy = false}) {
    if (!isPrivacy) return text;
    return '••••••';
  }

  /// Default box identifier for the main financial context.
  static const String defaultBoxId = 'main';

  /// Default box display name.
  static const String defaultBoxName = 'Out of the Box (Main Life)';

  /// Hardware and electronics keywords used for automated Digital Vault (eVault)
  /// asset detection and warranty tracking suggestions.
  static const List<String> hardwareKeywords = [
    'phone',
    'iphone',
    'smartphone',
    'laptop',
    'macbook',
    'ipad',
    'tablet',
    'monitor',
    'display',
    'tv',
    'television',
    'camera',
    'watch',
    'apple watch',
    'airpods',
    'headphones',
    'sony',
    'dell',
    'samsung',
    'apple',
    'console',
    'playstation',
    'xbox',
    'nintendo',
    'gpu',
    'graphics card',
    'keyboard',
    'mouse',
    'speaker',
    'processor',
    'cpu',
    'ram',
    'ssd',
    'drone',
  ];

  /// Furniture and physical asset keywords for asset categorization.
  static const List<String> furnitureKeywords = [
    'chair',
    'desk',
    'table',
    'sofa',
    'couch',
    'bed',
    'mattress',
    'bookshelf',
    'cabinet',
    'lamp',
    'armchair',
    'wardrobe',
    'nightstand',
  ];

  /// Default estimated tax withholding rate percentage (e.g. 22% self-employed/VAT buffer).
  static const double defaultTaxRate = 0.22;

  /// Default annual target goal for Tax Nest reserves in USD.
  static const double defaultTaxNestGoal = 12000.0;

  /// Default runway net burn warning threshold in months.
  static const double criticalRunwayThresholdMonths = 3.0;

  /// Pagination chunk size for transaction and invoice list queries.
  static const int defaultPageSize = 25;

  /// Maximum file size limit in bytes for receipt uploads (15MB).
  static const int maxReceiptUploadSizeBytes = 15 * 1024 * 1024;

  /// Default duration for UI toast snackbars in milliseconds.
  static const int snackBarDurationMs = 3000;

  /// Gamification streak requirement in consecutive days.
  static const int streakAchievementDays = 3;

  /// Gamification data hoarder achievement count threshold.
  static const int dataHoarderCountThreshold = 10;

  /// Gamification budget ninja safe threshold multiplier (80% of budget).
  static const double budgetNinjaSafeRatio = 0.80;

  /// Night owl scan threshold hour (22:00 / 10 PM).
  static const int nightOwlHourThreshold = 22;
}
