# Vaahana — WhatsApp Bot

Listens to WhatsApp groups in real-time and forwards ride request messages to the Vaahana ingestion API.

## How it works

1. Connects to WhatsApp via QR login using [Baileys](https://baileys.wiki/docs/api/classes/BinaryInfo)
2. Watches only the groups listed in `.env`
3. For every new text message, sends it to the Firebase ingestion endpoint
4. The Firebase function parses, classifies, and stores valid ride requests in Firestore

## Setup

```bash
npm install
```

Edit `.env`:
```
API_KEY=your_api_key
TARGET_GROUPS=NH Rides,Rides Test 1,Rides Test 2
```

## Run

```bash
cd "/Users/puneet/Downloads/Vibe Hai/Vaahana/Whatsapp BOT"
npm start
```

Scan the QR code with WhatsApp → Settings → Linked Devices → Link a Device.

Session is saved in `auth_session/` — subsequent runs skip the QR.

## Terminal output

```
[Rides Test 1] Puneet | ingested:1 skipped:0 dup:0 | "Need ride from Boston to Nashua tomorrow"
[Rides Test 1] Puneet | ingested:0 skipped:1 dup:0 | "What's up bro"
```

## What gets sent to the API

```json
{
  "groupName": "Rides Test 1",
  "messages": [
    {
      "phone": "+18573647103",
      "name": "Puneet",
      "text": "Need ride from Boston to Nashua tomorrow",
      "timestamp": "2026-04-10T22:15:00.000Z"
    }
  ]
}
```

## What gets ignored

- Messages sent by the bot account itself
- Media (images, video, audio, stickers)
- System messages (join/leave, group name changes)
- Any group not in `TARGET_GROUPS`

## Baileys

Built on [@whiskeysockets/baileys](https://baileys.wiki/docs/api/classes/BinaryInfo) — an open source WhatsApp Web API library for Node.js.

- Uses multi-device linking (no phone needs to stay online)
- Authenticates via QR or pairing code
- Exposes real-time events via `sock.ev` — `messages.upsert`, `connection.update`, `creds.update`
- Sender JIDs use the `@lid` format (privacy alias) — the bot resolves these to real phone numbers via group participant metadata

## Files

| File | Purpose |
|---|---|
| `index.js` | Main bot logic |
| `.env` | API key and group names |
| `auth_session/` | Saved WhatsApp session (auto-created, gitignored) |
