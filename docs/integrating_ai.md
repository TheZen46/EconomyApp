# Integrating AI into tAIdy 🤖

**tAIdy** supports powerful Artificial Intelligence features through two different paradigms: completely offline on-device inference using **Llama.cpp**, and cloud-based AI using **Google Gemini**. 

This guide walks you through integrating and activating these AI models.

## 1. On-Device AI (Llama.cpp)
tAIdy is natively built with `llama_cpp_dart` to run Large Language Models directly on your hardware. This ensures that no third party ever receives your receipt data.

**How to configure On-Device AI:**
1. Download a compatible `.gguf` local model (e.g., Llama 3 8B, Mistral, or a smaller model depending on your device specs) from Hugging Face.
2. In the app, navigate to **Settings** > **AI Configuration**.
3. Enable the **On-Device Llama** toggle.
4. Provide the absolute file path to the downloaded model, or simply use the file picker inside the application to select the `.gguf` file.
5. Save settings. 

The application will load the weights into memory when the AI is invoked. *Note: Local inference can be resource-intensive on older devices.*

## 2. Cloud AI (Google Gemini)
If you require more complex reasoning or prefer a faster experience at the cost of cloud processing, you can use the Google Gemini integration.

**How to configure Google Gemini AI:**
1. Go to Google AI Studio ([aistudio.google.com](https://aistudio.google.com/)) and log in with your Google account.
2. Generate an **API Key**.
3. Open **tAIdy** and navigate to **Settings** > **Integrations**.
4. Enable the **Gemini AI Engine** and paste your API key into the designated field.
5. Tap **Save**. 

The app secures this key locally on your device via Hive. Once saved, tAIdy will seamlessly send parsed receipt text to the Gemini API for categorization and expense extraction.
