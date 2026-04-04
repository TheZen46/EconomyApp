# tAIdy - Privacy-First AI Expense Tracker 🧾✨

![tAIdy Header](assets/logo.png)

Welcome to **tAIdy** (pronounced *tidy* / *t-AI-dy*), the next-generation, privacy-focused expense tracker that leverages on-device Artificial Intelligence to manage your receipts securely.

## 🌟 Philosophy: Privacy First
Unlike conventional cloud-based accounting tools, **tAIdy** runs powerful AI models right on your device. We believe your financial data belongs strictly to you. With tAIdy, parsing receipts, organizing expenses, and tracking data happens locally, giving you absolute control over your financial privacy.

## ✨ Features

- 🤖 **On-Device AI Engine:** Uses **Llama.cpp** (via `llama_cpp_dart`) to parse and extract structured data from receipts without internet tracking.
- ☁️ **Gemini Cloud AI Option:** Need more power? You can optionally configure your own Google Gemini API key to parse intricate receipts securely in the cloud.
- 📸 **Smart Receipt Scanning:** Instantly capture receipts using on-device OCR (Google ML Kit Text Recognition) and auto-categorize line items.
- 🔐 **Electronic Vault (eVault):** Securely manage your scanned assets and receipts in a digital vault.
- 💾 **Local-First Storage:** Fast and reliable local storage handled by **Hive**.
- ☁️ **Secure Sync & Backup:** Synchronize your encrypted receipt data using **Supabase** or back it up directly to your personal **Google Drive**.
- 📊 **CSV Exports:** Need to run the numbers yourself? Export all your data seamlessly in CSV format for integration with Excel, accounting software, or your accountant.

## 🚀 Getting Started

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (version `^3.10.4`)
- Dart SDK

### Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/TheZen46/EconomyApp.git
   cd EconomyApp
   ```

2. **Install Dependencies:**
   ```bash
   flutter pub get
   ```

3. **Configure API Keys (Optional but recommended):**
   - Head over to `Settings` > `Integrations` in the app.
   - Insert your **Gemini API Key** if you wish to use cloud-based receipt parsing.
   - Configure **Supabase / Google Drive** credentials as needed. (Make sure you download your `credentials.json` directly from the Google Cloud Console and place it securely if running locally).

4. **Run the App:**
   ```bash
   flutter run
   ```

## 🛠️ Technology Stack

- **Framework:** Flutter & Dart
- **State Management:** Riverpod (`flutter_riverpod`)
- **Routing:** GoRouter
- **Local Storage:** Hive
- **Data Synchronization:** Supabase (`supabase_flutter`)
- **Cloud AI Integration:** Google Generative AI (`google_generative_ai`)
- **On-Device AI:** Google ML Kit + Llama.cpp Dart

## 🤝 Contributing
Contributions, issues, and feature requests are welcome! Feel free to check the [issues page](https://github.com/TheZen46/EconomyApp/issues) if you want to contribute.

## 📝 License
This project is for educational and personal use. Feel free to fork and adapt it for your needs!
