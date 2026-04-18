# Vaahana

A community ride-sharing platform for the South Asian diaspora. Riders post requests via the app or WhatsApp community groups, drivers browse and contact riders, and the community self-organizes rides.

> **Current status: V1 — Rider-only mode.** The app is in early access for riders. The driver-side (bidding, assignment, coin transfers) is built but disabled pending driver onboarding. All users are assigned the `rider` role on sign-up.

---

## What It Does (V1)

### Rides Tab
- Community feed of all active ride requests posted via the app or ingested from WhatsApp
- Search bar to filter by pickup location
- Rides sorted by distance to the user's current location, then newest-first
- Collapsible "My Requests" section showing your own active posts
- Collapsible "Expired" section showing past/expired ride requests
- Swipe to cancel or delete your own rides
- Post a new ride request: pickup, destination, date/time, seat count, notes, and a coin offer

### Ride Detail Sheet
- Tappable map showing the pickup pin and destination, with a drawn route
- Distance and estimated drive time
- Contact the rider directly via WhatsApp deep link
- Mark as expired or cancel your own rides

### Map Tab
- Live map showing all active ride request pickup locations as pins
- Tap a pin to preview the ride; tap the card to open the full detail sheet
- Current location button — requests Always location permission, centers the map, and shows an alert with a Settings deeplink if permission was denied
- Ride count badge showing how many active requests are on the map

### Settings Tab
- Sign out
- (Driver controls are scaffolded but hidden in V1)

---

## Architecture

```
iOS App (SwiftUI, iOS 17+)
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

WhatsApp Bot (Baileys)
    → forwards messages → ingestWhatsAppMessages Cloud Function
    → rides appear in the app feed in real time
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
| `VaahanaApp.swift` | Entry point, auth state, `LocationService` (Always permission), daily coin grant, FCM setup |
| `ContentView.swift` | Main router, `Ride` model, `RideStorage` (Firestore listener + disk cache + geocoding), `RiderView`, `MapTabView`, `PostRideSheet`, `RideDetailSheet` |
| `RideService.swift` | All atomic Firestore transactions (accept, bid, cancel, complete) |
| `LocationPickerView.swift` | MKLocalSearchCompleter address picker with current-location support |
| `DriverBidsStore.swift` | Collection-group query for driver's bids across all rides |
| `ProfileView.swift` | Account dashboard — name, phone, vehicle info, ride history |
| `RatingView.swift` | Post-ride star rating — writes to `ratings` and increments user aggregate |
| `AdminView.swift` | Reconciliation logs, user/ride inspector, manual reconcile trigger |

### RideStorage — offline-first data layer

`RideStorage` is the central `ObservableObject` that owns all ride data:

- **Disk cache**: on first launch, cached rides from the previous session are loaded instantly from `Caches/vaahana_posted_rides.json` so the feed appears before Firestore responds.
- **Firestore listener**: real-time updates are merged in. Empty snapshots from Firestore's local cache are ignored to prevent the feed from flickering to empty on re-open.
- **Geocoding**: pickup coordinates are resolved once per ride (using stored `pickupLat`/`pickupLng` if available, falling back to `MKLocalSearch`). Results are shared between the Rides tab (distance sorting) and the Map tab (pin placement) — no duplicate lookups.
- **Deduplication**: rides with the same Firestore document ID are deduplicated before display.

### Location

`LocationService` requests `requestAlwaysAuthorization()` on first launch. The Map tab's re-center button checks the current authorization status and:
- If authorized: starts location updates and flies to the user's position
- If denied/restricted: shows an alert with a direct link to Settings
- If not determined: triggers the system permission dialog

`UIBackgroundModes: location` is declared in `Info.plist` so iOS offers the "Always" option in the permission sheet.

---

## WhatsApp Ingestion API

Vaahana ingests ride requests posted in WhatsApp community groups. A Baileys-based bot forwards messages to this endpoint, which parses them into live ride documents visible in the app.

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

**Time parsing:**

| Input | Parsed as |
|---|---|
| `7pm`, `7:30 AM` | Exact time on inferred date |
| `morning` | 9:00 AM |
| `afternoon` | 2:00 PM |
| `evening` | 6:00 PM |
| `night` | 8:00 PM |
| `noon` | 12:00 PM |
| `midnight` | 12:00 AM |
| No time mentioned | Time of message (i.e., "now") |

**Date inference:** "today", "tonight", "tomorrow", "tmrw", "next week", or bare weekday names ("Monday") are resolved relative to the message timestamp (in US/Eastern). If no date cue is present, the message date is used.

**Hot duration inference (time until ride expires from the feed):**

| Time until pickup | Hot duration |
|---|---|
| ≤ 1 hour | 60 minutes |
| ≤ 6 hours | 2 hours |
| ≤ 24 hours | 8 hours |
| ≤ 72 hours | 24 hours |
| > 72 hours | 48 hours |

**Phone matching:**

If the sender's phone matches an existing Vaahana user's `phone` or `whatsapp` field, the ride is linked to their account. Otherwise, a placeholder entry is created in `whatsappRiders` keyed by a hash of the phone number — so when they sign up, rides can be claimed retroactively.

### Known Limitations

- **Offline messages are permanently missed.** The Baileys bot uses `syncFullHistory: false`. Messages sent while the bot is offline are not replayed when it reconnects. This is a Baileys design constraint; the only workaround is manual re-ingestion via the raw export endpoint.

---

## Cloud Functions

### `ingestWhatsAppMessages` — HTTP
Parses WhatsApp group messages into ride documents. See [WhatsApp Ingestion API](#whatsapp-ingestion-api) above.

### `expireStaleRides` — every 1 minute
Marks `posted` rides as `expired` when `createdAt + hotDuration` has passed. Expired rides remain visible in the rider's "Expired" section in the app.

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
