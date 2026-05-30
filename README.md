# Flow

**Flow** is Penlo's mobile intelligence layer: an iOS app that captures conversations (via Penlo wearable or phone mic), extracts structured knowledge with Claude, lets you review before syncing, and pushes approved memories to the Enterprise Brain.

This repository contains:

| Path | Description |
|------|-------------|
| [`flow/`](flow/) | SwiftUI iOS app (Xcode project at repo root) |
| [`audio-pipeline/`](audio-pipeline/) | Python reference pipeline for transcript → Claude extraction → Enterprise Brain sync |

Both implement the **Penlo Contract v1.1** schema (SPO facts, structured people, topic summaries, vault files).

---

## Features

- **Conversational chat** powered by Claude (`claude-sonnet-4-6`)
- **Speech-to-text** from phone microphone or Penlo BLE wearable
- **Smart listening** with silence detection and battery-conscious auto-stop
- **Privacy staging vault** — review, edit, approve, or discard before anything leaves the device
- **Enterprise Brain sync** — incremental POST to `/api/v1/ingest/penlo-brain` with offline queue + retry
- **Calendar briefings** — AI-generated pre-meeting context from captured memories
- **Secure credential storage** — API keys and email stored in iOS Keychain (never in source code)

---

## Requirements

### iOS app

- **Xcode 16+** (Swift 5, iOS 18+ simulator or device)
- **Anthropic API key** — required for chat and transcript extraction
- **Enterprise Brain URL + API key** — optional; sync queues locally until configured

### Audio pipeline (optional / reference)

- **Python 3.11+**
- Same Anthropic + Enterprise Brain credentials via `.env`

---

## Quick start — iOS app

1. **Clone the repository**

   ```bash
   git clone https://github.com/SanjoyDat1/Flow.git
   cd Flow
   ```

2. **Open in Xcode**

   ```bash
   open flow.xcodeproj
   ```

3. **Select a simulator or device** (e.g. iPhone 17 Pro) and run (**⌘R**).

4. **Configure API keys in the app**

   - Tap the menu → **Settings** (gear)
   - **Claude API Key** — paste your `sk-ant-…` key and tap **Verify Key**
   - **Account** — enter your work email (included in Enterprise Brain payloads)
   - **Enterprise Brain** — enter endpoint URL and `pb_live_…` key when your team provides them

5. **Use the app**

   - **Chat** — type or tap the mic button to dictate
   - **Review Memories** — tap the status pill when captures are pending; approve to sync
   - **Penlo wearable** — connect via Bluetooth in Settings

### Permissions

The app requests:

- **Microphone** — phone mic listening
- **Speech Recognition** — on-device transcription
- **Bluetooth** — Penlo wearable connection
- **Calendar & Notifications** — briefing reminders (optional)

---

## Quick start — audio pipeline

The Python pipeline mirrors the iOS extraction + sync logic for batch-processing transcript files on a Mac or server.

```bash
cd audio-pipeline
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
# Edit .env with your Anthropic API key
```

**Process transcripts once:**

```bash
python pipeline.py
```

**Watch folder for new files:**

```bash
python pipeline.py --watch
```

**Local-only (no network sync):**

```bash
python pipeline.py --no-sync
```

Drop `.txt` files into `audio-pipeline/transcripts/` (see the included sample). Validated payloads land in `output/`; failed runs go to `failed/`.

---

## Security

**Never commit secrets.** This repo is configured to ignore:

- `.env` and local credential files
- Xcode user data (`xcuserdata/`)
- Pipeline runtime output (`output/`, `queue/`, etc.)
- Sync diagnostic logs

API keys in the iOS app are stored in the **Keychain** on-device only. The Python pipeline reads keys from a local `.env` file that stays on your machine.

If you accidentally commit a secret, rotate the key immediately and purge it from git history.

---

## Project structure

```
Flow/
├── README.md
├── .gitignore
├── Info.plist
├── flow.xcodeproj/
├── flow/                    # iOS application source
│   ├── Components/
│   ├── DesignSystem/
│   ├── Managers/            # BLE, audio, calendar, app state
│   ├── Models/              # SwiftData models, Penlo Contract v1.1
│   ├── Services/            # Claude API, Enterprise Brain syncer
│   ├── ViewModels/
│   └── Views/
├── flowTests/
├── flowUITests/
└── audio-pipeline/          # Python reference pipeline
    ├── pipeline.py
    ├── schema.py
    ├── requirements.txt
    ├── .env.example
    └── transcripts/
```

---

## Enterprise Brain integration

Approved memories are POSTed as JSON matching Penlo Contract **v1.1**:

```json
{
  "schemaVersion": "1.1",
  "deviceID": "<UUID>",
  "userEmail": "you@company.com",
  "syncedAt": "2026-05-29T12:00:00Z",
  "facts": [{ "subject": "...", "predicate": "...", "object": "...", "confidence": 0.82, "capturedAt": "..." }],
  "people": [{ "name": "...", "email": null, "phone": null, "notes": null }],
  "topicSummary": ["..."],
  "vaultFiles": []
}
```

Sync behavior: incremental facts, exponential backoff on 429, offline queue with foreground drain, contract-aligned error handling (400/422 no-retry, 401 surfaces in Settings).

---

## Development

**Build from CLI:**

```bash
xcodebuild -scheme flow -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

**Run Python self-test:**

```bash
cd audio-pipeline && python _selftest.py
```

---

## License

Proprietary — © 2026 Penlo. All rights reserved.
