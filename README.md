# Vaahana

A community ride-sharing platform for the South Asian diaspora. Riders post requests with a coin offer, drivers browse and bid, and riders pick a driver. Coins transfer on completion.

---

## What It Does

### For Riders
- Post a ride request (pickup, drop-off, time, coin offer)
- See live driver bids on your request, sorted lowest-coin first
- Select a driver — coins are locked immediately
- Track the driver in real-time through enroute → arrived → started → completed
- Rate the driver after the ride
- Earn 100 coins every day just for having an account

### For Drivers
- See all hot ride requests on a live map
- Filter by radius (1–50 miles) around your location or a custom pin
- Place bids on rides, edit or withdraw before acceptance
- Track your bids across "Pending / Selected / Closed" tabs
- Advance the ride through statuses and complete it to receive coins
- Go online/offline with one toggle

### Coins
Coins are community currency — no real money involved. Every user gets 100 coins/day. Coins are locked from the rider on acceptance and transferred to the driver on completion. If the ride is cancelled, coins are refunded.

---

## Architecture

```
iOS App (SwiftUI)
    ↕ real-time Firestore listeners
Firebase Firestore
    ↕ Cloud Functions (Node.js 22)
        ├── Scheduled: expireStaleRides (every 1 min)
        ├── Scheduled: reconcileRecentRides (every 5 min)
        ├── Scheduled: reconcileUserLocks (every 5 min)
        ├── Scheduled: reconcileDriverAssignments (every 5 min)
        ├── Scheduled: grantDailyCoins (midnight UTC daily)
        ├── HTTP:      ingestWhatsAppMessages
        ├── Callable:  reconcileRide (admin)
        ├── Trigger:   onBidPlaced → FCM push to rider
        └── Trigger:   onRideStatusChanged → FCM push to both parties
```

### Firestore Collections

| Collection | Purpose |
|---|---|
| `users/{uid}` | Profile, role, coins, coinsLocked, fcmToken, vehicle info |
| `rides/{rideId}` | Full ride lifecycle — status, route, coins, timestamps |
| `rides/{rideId}/bids/{bidId}` | Per-driver bids on a posted ride |
| `coinTransactions/{txId}` | Immutable record of every coin transfer |
| `ratings/{ratingId}` | Post-ride star ratings (1–5) with optional comment |
| `reconciliationLogs/{logId}` | Server-written integrity audit trail |
| `whatsappRiders/{id}` | Placeholder profiles for WhatsApp-sourced riders without a Vaahana account |
| `whatsappIngestionLogs/{id}` | Per-message audit log from the ingestion pipeline |

### Ride State Machine

```
posted ──► accepted ──► driver_enroute ──► driver_arrived ──► ride_started ──► completed
   │                                                                                 │
   └──────────────────────── cancelled / expired ◄────────────────────────────────── ┘
```

Coin flow: `posted (none)` → `accepted (locked)` → `completed (transferred)` or `cancelled (refunded)`

---

## iOS App — Key Files

| File | Role |
|---|---|
| `VaahanaApp.swift` | Entry point, auth state, daily coin grant, FCM setup |
| `ContentView.swift` | Main router, `Ride` model, `RideStorage` real-time listener, `PostRideSheet`, driver map view |
| `RideService.swift` | All atomic Firestore transactions (accept, bid, cancel, complete) |
| `LocationPickerView.swift` | MKLocalSearchCompleter address picker with current-location support |
| `DriverBidsStore.swift` | Collection-group query for driver's bids across all rides |
| `ProfileView.swift` | Account dashboard — name, phone, vehicle info, ride history |
| `RatingView.swift` | Post-ride star rating — writes to `ratings` and increments user aggregate |
| `AdminView.swift` | Reconciliation logs, user/ride inspector, manual reconcile trigger |

---

## WhatsApp Ingestion API

Vaahana ingests ride requests posted in WhatsApp community groups. A scraper forwards messages to this endpoint, which parses them into live ride documents visible to drivers.

### Endpoint

```
POST https://us-central1-vaahana-fb9b8.cloudfunctions.net/ingestWhatsAppMessages
```

### Authentication

Pass the API key in the request header:

```
x-api-key: <WHATSAPP_INGEST_API_KEY>
```

The key is stored as a Firebase Secret (`WHATSAPP_INGEST_API_KEY`). Contact the project owner for the value.

### Request — Option A: Raw WhatsApp Export

Paste the raw text copied from a WhatsApp group export directly.

```json
{
  "groupName": "NH Rides",
  "rawExport": "[5:38 PM, 4/9/2026] +1 (720) 560-3486: Need ride from Nashua to New Jersey tomorrow\n[6:11 PM, 4/9/2026] +1 (603) 438-1495: Need ride from Hudson to Nashua at 7pm\n[7:42 PM, 4/9/2026] +1 (978) 815-8869: Need accommodation for a boy from May 1st. Dm me if any leads"
}
```

### Request — Option B: Pre-parsed Array

If your scraper already splits messages, send them as an array. `timestamp` is ISO 8601.

```json
{
  "groupName": "NH Rides",
  "messages": [
    {
      "phone": "+17205603486",
      "text": "Need ride from Nashua to New Jersey tomorrow",
      "timestamp": "2026-04-09T17:38:00Z"
    },
    {
      "phone": "+16034381495",
      "text": "Need ride from Hudson to Nashua at 7pm",
      "timestamp": "2026-04-09T18:11:00Z"
    }
  ]
}
```

### Response

```json
{
  "total": 3,
  "ingested": 2,
  "skipped": 1,
  "duplicate": 0,
  "errors": 0,
  "rides": [
    "cf99622f-a484-4222-aeae-4151cd2d71e8",
    "7626c818-d981-4677-8529-e29d61add268"
  ]
}
```

| Field | Meaning |
|---|---|
| `total` | Messages received |
| `ingested` | Ride documents created |
| `skipped` | Not a ride request (accommodation, no route, past pickup) |
| `duplicate` | Same phone + route + date seen in last 24h |
| `errors` | Processing failures (check `whatsappIngestionLogs`) |
| `rides` | Firestore document IDs of created rides |

### Parsing Logic

The parser uses regex to classify and extract data from natural language messages.

**Accepted messages (examples):**
```
Need ride from Nashua to New Jersey tomorrow
Need ride from Hudson to Nashua at 7pm
Anybody travelling by road from Massachusetts to Virginia next few weeks
Need ride from 310 brook village,nh to 72 baldwin ave,jersey city
```

**Discarded messages (examples):**
```
Need accommodation for a boy from May 1st         → accommodation keyword
Shared room available in Nashua downtown           → accommodation keyword
DM me if any leads                                 → no ride keyword or route
```

**Hot duration inference:**

| Urgency cue | Hot duration |
|---|---|
| "tonight", "now", "asap" | 60 minutes |
| "today", "this morning" | 120 minutes |
| "tomorrow", "tmrw" | 480 minutes (8 hours) |
| "next few weeks", "soon" | 2,880 minutes (48 hours) |
| No cue (time-based fallback) | 60–480 minutes based on how far away pickup is |

**Phone matching:**

If the sender's phone matches an existing Vaahana user's `phone` or `whatsapp` field, the ride is linked to their account. Otherwise, a placeholder entry is created in `whatsappRiders` keyed by a hash of the phone number — so when they sign up, rides can be claimed retroactively.

### Monitoring Dashboard

A live monitoring dashboard is available at:

```
https://vaahana-fb9b8.web.app/dashboard
```

Shows real-time ingestion stats, recent messages, parse results, and system health.

---

## Cloud Functions

### `ingestWhatsAppMessages` — HTTP
Parses WhatsApp group messages into ride documents. See [WhatsApp Ingestion API](#whatsapp-ingestion-api) above.

### `expireStaleRides` — every 1 minute
Marks `posted` rides as `expired` when `createdAt + hotDuration` has passed. Server-side counterpart to the client-side expiry in `RideStorage`.

### `reconcileRecentRides` — every 5 minutes
Scans all live rides and recently-finalized rides (last 7 days). Auto-repairs:
- Closes active bids on final rides
- Refunds locked coins on cancelled/expired rides
- Clears stale `driverId`/`selectedBidId`/`finalCoins` on re-posted rides

### `reconcileUserLocks` — every 5 minutes
Validates every user's `coinsLocked` against their active rides. Auto-corrects mismatches.

### `reconcileDriverAssignments` — every 5 minutes
Validates every driver's `activeRideId`. Clears links to rides that no longer exist, are final, or belong to a different driver.

### `grantDailyCoins` — midnight UTC daily
Grants 100 coins to every user who hasn't received them today. Deduplicated via `lastDailyCoinDate`. The iOS app also does a client-side grant on each login as a failsafe.

### `reconcileRide` — callable (admin)
Deep single-ride inspection. Returns all detected issues and applies safe repairs immediately without waiting for the next cron run. Used from the in-app Admin panel.

### `onBidPlaced` — Firestore trigger
Sends an FCM push notification to the rider when a new bid is placed on their ride.

### `onRideStatusChanged` — Firestore trigger
Routes FCM push notifications to both parties as the ride advances through states.

---

## Security

- All Firestore writes from the iOS app go through security rules enforcing ownership
- Coin movements use atomic Firestore transactions — no partial updates
- Final ride states (`completed`, `cancelled`, `expired`) are immutable
- The WhatsApp ingestion endpoint is protected by a shared secret stored in Google Secret Manager
- Admin panel is gated behind a Firestore `isAdmin` flag set server-side

---

## Firebase Project

**Project ID:** `vaahana-fb9b8`
**Region:** `us-central1`
**Node.js runtime:** 22 (LTS)
