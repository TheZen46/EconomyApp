# tAIdy User Guide 

Welcome to tAIdy. The app is intuitively designed to simplify your expense tracking while letting the underlying AI do the heavy lifting of categorizing, tagging, and saving your data.

This guide provides a quick look into how to use the application to simplify your daily accounting and data process.

## Step 1: Capture or Import Receipts 
The most tedious part of expense tracking is manual data entry. tAIdy nullifies this.
1. Tap the large `+` (Add) button on the main dashboard.
2. Snap a photo of a physical receipt or upload an image from your gallery.
3. *On-Device OCR* (Google ML Kit) immediately sweeps the image and extracts the raw text.

## Step 2: AI Parsing & Structuring 
Once the image is digitized:
1. Check the extracted text. If it looks correct, tap **Analyze via AI**.
2. Depending on your configuration (Local Llama or Gemini), the AI will read the unstructured text and format it into categorized tables. 
3. The AI understands nuances: it will cleanly separate the merchant name, total price, date, and individual line items (like tax, food, and miscellaneous goods).

## Step 3: Secure the Receipt in the eVault 
Once analyzed, the receipt data needs a home. 
1. The categorized data card will prompt you to **Save to eVault**.
2. The eVault encrypts the data and stores it locally securely using Hive. 
3. If you have integrations turned on (Supabase or Google Drive), the eVault will mirror this data so you never lose it if you lose your phone.

## Step 4: Exporting for Accountants 
When tax season comes around, you do not want to hunt for receipts.
1. Open the **Analytics & Exports** tab.
2. Select your timeframe (e.g., Q1 2026).
3. Tap **Export CSV**.
4. The system will bundle your scanned expenses into a beautifully structured spreadsheet, ready for external accounting software like Excel, QuickBooks, or directly to your accountant.

## Step 5: Cross-Device Cloud Synchronization & Parity
When switching devices, signing in on a new phone, or launching the desktop app:
1. **Initial Full Replication**: Immediately after logging in, tAIdy presents the **Kinetic Replication Screen** (`/sync_progress`).
2. **Real-Time Telemetry**:
   - **Data Replicated**: Live transferred volume vs. total cloud backup size.
   - **Delta Objects**: Tracks new receipts, boxes, invoices, and eVault assets being hydrated into your encrypted local storage.
   - **Bandwidth**: Real-time throughput (e.g., `3.5 MB/s`).
   - **Estimated Time**: Live completion countdown.
3. **Deep Link Retention**: If you opened a specific invoice link (e.g., `/invoices` or `/vault`), tAIdy preserves your destination and seamlessly opens it once synchronization completes.
4. **On-Demand Replication**: Open **Settings** (⚙️) $\rightarrow$ **Sync Center** $\rightarrow$ tap **Replicate Cloud Data** anytime to pull cross-device updates manually.
5. **Offline Mode**: If you are traveling or have no cellular reception, tap **Continue in Offline Mode** on the replication screen to immediately access cached receipts and local records without delay.

## Step 6: Activity Contexts (Boxes) & Invoices
- **Boxes (`/boxes`)**: Group receipts into specific activity contexts (e.g., *Business Travel*, *Home Renovation*, *Office Supplies*). View spending velocity and pace against customized budget caps.
- **Invoices (`/invoices`)**: Track client receivables with status tracking (*Draft*, *Sent*, *Settled*, *Overdue*), revenue velocity charts, and local data persistence.
