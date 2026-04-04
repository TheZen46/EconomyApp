# 🧾 tAIdy (EconomyApp)

🚧 **Status:** Active Development (Beta) | 🚀 **Version:** 1.0.0

A lightweight, privacy-first personal finance management and receipt tracking app. **tAIdy** allows users to track income, extract expenses from receipts using state-of-the-art On-Device AI, and analyze financial trends securely in real time.

## 🎯 Overview & Why this project exists

Traditional expense trackers force you to upload your sensitive financial receipts to cloud servers, compromising your privacy. **tAIdy** solves this by running Large Language Models (LLMs) like Llama.cpp and Google ML Kit directly on your device hardware. Your financial history never leaves your pocket unless you explicitly choose to sync it. 

**Who is it for?** Privacy-conscious individuals, freelancers, and small business owners who want intelligent, automated accounting without the spyware.

---

## ✨ Features

- **Automated Expense Tracking:** Auto-extract prices, dates, and line-items from receipts using On-Device OCR.
- **Bifurcated AI Engine:** Choose between 100% offline smart parsing (Llama) or blazing-fast cloud inference (Gemini).
- **Electronic Vault (eVault):** Secure, AES-256 encrypted local storage for all your scanned assets.
- **Categorize & Analyze:** View monthly graphs, taxonomy breakdowns, and transaction dashboards.
- **Export Capabilities:** Export your entire financial history instantly to CSV for accountants or tools like Excel.
- **Cloud Sync (Optional):** Integration with Supabase and Google Drive for seamless backups.

---

## 📸 Screenshots

*(Add UI screenshots of the dashboard, receipt scanner, and eVault below to improve product visibility)*
> 🖼️ *Dashboard View Placeholder* | 🖼️ *Receipt Scanner Placeholder* | 🖼️ *Analytics Placeholder*

---

## 🛠️ Installation

```bash
# 1. Clone the repository
git clone https://github.com/TheZen46/EconomyApp.git

# 2. Navigate into the project workspace
cd EconomyApp

# 3. Install Flutter dependencies
flutter pub get

# 4. Run the application
flutter run
```
> ⚠️ **Note on platform support:** The web version currently relies on an isolated AI stub to bypass native C++ FFI limitations. For full On-Device AI features, compile for iOS, Android, or macOS.

---

## 📖 Usage

Using tAIdy takes less than 30 seconds:
1. **Capture:** Tap the floating `+` button to scan a physical receipt.
2. **AI Analysis:** Let the local Llama model parse the text and cleanly categorize the merchant and items.
3. **Save:** Push the structured data securely into your encrypted eVault.
4. **Analyze:** Check your dashboard for spending trends or generate a CSV report.

For a deeper dive, read our dedicated documentation:
- [🧭 tAIdy User Guide](docs/user_guide.md)
- [🤖 Integrating AI into tAIdy](docs/integrating_ai.md)

---

## 🏗️ Architecture

- **Frontend / Mobile UI:** Flutter & Dart
- **State Management:** Riverpod (`flutter_riverpod`)
- **Local Database:** Hive (Fast, NoSQL local encrypted storage)
- **Backend Sync:** Supabase / Google Drive
- **AI/ML Layer:** Google ML Kit (OCR), `llama_cpp_dart` (On-Device LLM), Google Generative AI (Cloud LLM)

**Data Flow Diagram:**
`User → Camera/OCR → Raw Text → On-Device LLM Parser → Structured JSON → Hive Database → Analytics UI`

---

## 🗺️ Roadmap

- [x] Integrate OCR and basic Receipt Parsing
- [x] Implement Llama.cpp local AI
- [x] Develop secure Hive eVault architecture
- [ ] Implement user authentication via Supabase
- [ ] Add deep Interactive Charts and AI financial forecasting
- [ ] Establish automated testing pipelines (Unit & Widget tests)
- [ ] Expand CI/CD deployment logic via GitHub Actions

---

## 🤝 Contributing

Pull requests are actively welcome! For major changes or architectural shifts, please open an issue first to discuss what you would like to change. 

Make sure to update backend settings following `.env.example` protocols before submitting test implementations.

---

## 📝 License

**MIT License**  
This project has been done in a big part with human code made by TheZen46. It is strictly for educational and personal use. Feel free to fork, build, and adapt it for your needs!
