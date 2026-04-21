# Vaahana — Design & Architecture

A single reference for the whole system. Skim the top to orient, drop into the
section you need.

---

## 1. Elevator pitch

**Vaahana is a community ride marketplace.** Riders post requests ("I need to
get from A to B, pickup around X, WhatsApp me"), and drivers in the same
community see those requests in real time, contact the rider directly on
WhatsApp, and optionally accept the ride to own its progress through
enroute → arrived → started → completed.

It's not Uber. There's no pricing, no algorithmic matching, no coin payment
layer. The product is: make community ride-sharing visible and structured,
with WhatsApp as the messaging substrate people already trust.

**Three entry points, one backend:**

| Surface | For | Built with |
|---|---|---|
| iOS app (`Vaahana/`) | Full-featured riders + drivers | SwiftUI, MapKit, Firebase iOS SDK |
| Web app (`dashboard/public/`) | Anyone on a browser, mirrors iOS flow | Vanilla HTML/JS, Leaflet + OSM, Firebase Web SDK |
| WhatsApp bot (`Whatsapp BOT/` + `ingestWhatsAppMessages` Cloud Function) | Riders who don't install anything | Node.js, regex-based parser |

All three converge on the same Firestore `rides` collection, so a WhatsApp
rider shows up live on the app's map next to an iOS-posted ride.

---

## 2. System architecture

```
                             ┌───────────────────────┐
                             │   iOS app (SwiftUI)   │
                             │   Vaahana/*.swift     │
                             └──────────┬────────────┘
                                        │  Firestore SDK
                                        │  FirebaseAuth SDK
                                        │
  ┌────────────────────┐                ▼                ┌──────────────────────┐
  │ WhatsApp groups    │         ┌───────────────┐       │ Web app              │
  │ (community chats)  │  parse  │   Firebase    │◄──────│ dashboard/public/*   │
  └──────────┬─────────┘ ──────► │   Firestore   │       │ (SPA, vanilla JS)    │
             │ HTTP POST          └───────┬───────┘       └──────────────────────┘
             ▼                            │
  ┌──────────────────────┐                │
  │ ingestWhatsAppMessages│◄───────────────┘
  │ (Cloud Function)     │       listeners, transactions
  └──────────────────────┘
             ▲
             │
  ┌──────────────────────┐
  │ Other Cloud Functions│
  │ - expireStaleRides   │  every 1 min
  │ - reconcile* jobs    │  every 5 min
  │ - onBidPlaced / etc. │  Firestore triggers
  │ - auth callables     │  phone check, reset password
  └──────────────────────┘
```

**Infrastructure summary:**

- **Firebase Project:** `vaahana-fb9b8`
- **Auth:** Email + password, email verification required, forgot-password
  via managed callable (uses custom template hosted at `/reset-password`)
- **Firestore:** authoritative data store (rides, users, bids, logs)
- **Cloud Functions:** ingestion, scheduled reconciliation, auth helpers,
  ride lifecycle triggers
- **Firebase Hosting:** static web app + admin dashboard + reset-password page
  - Root `/` → consumer web app (`dashboard/public/index.html` + `app.html`)
  - `/admin` → legacy admin/ingestion dashboard (`dashboard/public/admin/index.html`)
  - `/reset-password` → handles all Firebase Auth action emails (verifyEmail, resetPassword)
- **Domain:** `vaahana.app` (Namecheap), fronting Firebase Hosting
  - Custom email sender domain in progress so verification emails don't spam-filter

---

## 3. Data model (Firestore)

### `users/{uid}`
Created on first login, updated on profile edits.

| Field | Type | Notes |
|---|---|---|
| `uid` | string | Firebase auth UID |
| `email` | string | |
| `displayName` | string | |
| `phone`, `phoneCountryCode` | string, string | Stored separate on iOS/web; WhatsApp-ingested users store `phone` with country code already baked in (e.g. `+919876543210`). Web helpers (`fullPhone()` in `util.js`) handle both. |
| `whatsappPhone`, `whatsappCountryCode` | string, string | |
| `role` | `"rider" \| "driver"` *or unset* | iOS enforces a permanent role. Web treats every user as both (no role picker). |
| `isAdmin` | bool | Gates the `/admin` dashboard |
| `isAvailable` | bool | Driver availability toggle (iOS only) |
| `vehicle{Make,Model,Color,Plate}` | strings | Driver details (iOS only) |
| `createdAt`, `updatedAt` | Timestamp | |

### `rides/{rideId}`
The center of gravity. Every surface reads and writes here.

| Field | Type | Meaning |
|---|---|---|
| `id` | UUID string | Mirrors document ID |
| `riderId` | string | UID of the rider; `whatsapp-<phoneHash>` for unlinked WhatsApp riders |
| `status` | enum | `posted → accepted → driverEnroute → driverArrived → rideStarted → completed` or `cancelled` / `expired` |
| `source` | `"app" \| "web" \| "whatsapp"` | Determines UI affordances (e.g. web shows a green "WhatsApp" badge on `whatsapp` rides) |
| `name`, `phone`, `phoneCountryCode` | string | Rider contact |
| `whatsappPhone`, `whatsappCountryCode` | string | WhatsApp CTA links use these |
| `from`, `to` | string | Free-text addresses |
| `miles` | number | OSRM (web) or MapKit (iOS) calculation |
| `pickupLat`, `pickupLng` | number \| null | Geocoded pickup for map pins |
| `pickupDate` | Timestamp | Requested pickup time |
| `hotDuration` | int (minutes) | Ride is "hot" while `createdAt + hotDuration` is in the future |
| `notes` | string \| null | Rider's free-form note |
| `createdAt`, `updatedAt` | Timestamp | |
| `driverId`, `driverName`, `driverPhone`, `driverWhatsapp` | populated on accept |
| `acceptedAt`, `driverEnrouteAt`, `arrivedAt`, `startedAt`, `completedAt`, `cancelledAt` | state transition timestamps |
| `cancelledBy`, `cancellationReasonCode` | | |
| `bidCount`, `selectedBidId`, `latestBidAt` | denormalized bid summary (iOS-only feature) |

**Subcollection `rides/{rideId}/bids/{bidId}`** — iOS-only bid marketplace.
Web never writes here. Drivers place message-based offers ("Can be there in
10 min") and riders pick one. Structure in [RideBid.swift](Vaahana/RideBid.swift).

### `reconciliationLogs/{logId}`
Written by the scheduled reconciliation jobs. Admin dashboard displays them.

### `whatsappIngestionLogs/{logId}`
Audit trail for the ingestion endpoint. Admin dashboard reads, server-only writes.

### `whatsappRiders/{docId}`
Placeholder profiles for WhatsApp-sourced riders who haven't signed up yet.

### `ratings/{ratingId}`
Post-ride ratings.

### Firestore security model

See [firestore.rules](firestore.rules). High-level:

- `users/{uid}` — any signed-in user can read (drivers browse rider names);
  only `uid` owner can write.
- `rides/{id}` — **public read** (so unauthenticated admin dashboards and
  drivers can list). Writes require auth + ownership of the relevant field
  (`riderId` for create/cancel, `riderId || driverId` for updates, plus a
  special case where a driver claims a `posted` ride by setting
  `driverId == auth.uid`).
- Bids, logs, ratings, WhatsApp-ingested collections — each has its own
  scoped rule.

### Firestore indexes

[firestore.indexes.json](firestore.indexes.json). Composite indexes for:
- Active posted rides: `status ASC, createdAt DESC`
- Rider history: `riderId ASC, status ASC, updatedAt DESC`
- Driver history: `driverId ASC, status ASC, updatedAt DESC`
- Legacy WhatsApp ingestion lookups

---

## 4. Core user flows

### 4.1 Sign up / sign in (iOS + web)

1. User enters email + password + name + phone.
2. Client calls `checkPhoneUnique` callable (defends against duplicate phones).
3. `createUserWithEmailAndPassword` → user created, unverified.
4. Client writes `users/{uid}` profile document.
5. `sendEmailVerification` fires. Email sent via Firebase template to
   `/reset-password?mode=verifyEmail&oobCode=…`.
6. Verify page calls `applyActionCode(oobCode)`. On success, redirects to app.
7. Web & iOS poll `user.reload()` every 4s on the verify screen to auto-advance.

> **Email deliverability:** Firebase's default sender is
> `noreply@vaahana-fb9b8.firebaseapp.com`, which Gmail aggressively
> spam-filters. The planned fix is a custom sender domain (DNS records for
> `vaahana.app` pending — SPF + DKIM CNAMEs, see session notes).

Forgot-password uses a managed callable `sendManagedPasswordResetEmail`
(Cloud Function at [functions/index.js:1465](functions/index.js#L1465)) that
enforces the current-password-hash check before sending — prevents reset-email
spam for accounts where the attacker doesn't know the current password.

### 4.2 Rider: posting a ride

Same on iOS and web. Required inputs:

- **Pickup** + **Drop-off** (address + geocoded coords)
  - iOS uses MapKit search
  - Web uses Nominatim autocomplete with state/city disambiguation
- **Distance (mi)** — auto-calculated from route
  - iOS: MapKit route calculation
  - Web: OSRM driving distance, falls back to haversine great-circle
- **Pickup time** (datetime picker)
- **Active for** — 30 min / 1 hr / 5 hr / 1 day. Controls `hotDuration`.
- **Notes** (optional)
- **Name**, **Phone (+ country code)**, **WhatsApp phone** (same by default)

Writes a new `rides/{id}` with `status=posted`. Visible to all drivers
immediately via Firestore snapshot listener.

### 4.3 Driver: finding rides

- **Home tab (web) / Rides tab (iOS)** — chronological list of all
  `status=posted` rides, newest first.
- **Map tab** — Leaflet (web) / MapKit (iOS) with a pin for each hot ride.
  User's live location tracked via `watchPosition` (web) / CoreLocation (iOS).
  Web pin styling:
  - Blue "ME" pin = your own posted request
  - Green "WA" pin = WhatsApp-ingested request (matches iOS green badge)
  - White "•" pin = another Vaahana user's request

For rides missing coords (e.g. WhatsApp geocode failed), web does a
best-effort client-side Nominatim lookup so they still appear on the map;
any that still can't be located show in the bottom count pill as "*N without
location*".

### 4.4 Driver: contacting & accepting

- **WhatsApp pill** → opens `wa.me/<fullPhone>` with a prefilled message
  including driver name and route. This is the primary communication channel.
- **Call pill** → `tel:` link
- **Accept button** → Firestore transaction that atomically claims the ride:
  - Guards: ride must still be `posted`
  - Sets: `driverId = auth.uid`, copies driver contact info onto the ride
  - Transitions: `status = accepted`, `acceptedAt = now`

After accepting, the driver owns the progress flow:

`accepted → driverEnroute → driverArrived → rideStarted → completed`

Each transition is a single button tap on the Active tab, writing the
corresponding timestamp.

Either party can cancel while the ride is not yet completed.

### 4.5 WhatsApp ingestion

Cloud Function: `ingestWhatsAppMessages` ([functions/index.js:1064](functions/index.js#L1064))

Accepts a POST with raw WhatsApp group export text. Regex-parses messages
like *"Need ride from Boylston to Logan, 5pm today, reply +1617…"*. For each
match:

1. Extracts `from`, `to`, `pickupDate` (or defaults), `phone`
2. Looks up existing `users` by phone → links to a Vaahana account, or
   creates a `whatsappRiders` placeholder
3. Best-effort geocodes the pickup address via the project's configured
   geocoder
4. Writes a `rides/{id}` with `source: "whatsapp"`, `status: "posted"`,
   `hotDuration: 1440` (24 h so non-urgent WhatsApp requests don't disappear)
5. Logs to `whatsappIngestionLogs`

The sidekick Node bot in `Whatsapp BOT/` pulls message exports and POSTs them
to this endpoint.

---

## 5. Code layout

```
Vaahana/
├── Vaahana/                         # iOS app (SwiftUI)
│   ├── VaahanaApp.swift             # @main, UserState, auth flow
│   ├── ContentView.swift            # root tabs + RideStorage + Ride model + all rider/driver screens (2900+ lines)
│   ├── PhoneAuthView.swift          # email/password signup/login/verify/forgot
│   ├── RoleSelectionView.swift      # rider vs driver (permanent)
│   ├── ActiveRideView.swift         # in-progress ride UI
│   ├── RideHistoryView.swift        # completed/cancelled/expired
│   ├── ProfileView.swift            # settings
│   ├── BidListView.swift            # rider sees driver bids
│   ├── DriverBidsView.swift         # driver sees their placed bids
│   ├── DriverBidsStore.swift        # driver bid feed state
│   ├── PlaceBidSheet.swift          # driver places/edits/withdraws bid
│   ├── RideBid.swift                # Bid model + BidStatus enum
│   ├── RideService.swift            # transactional state transitions (acceptRide, updateRideStatus, placeBid)
│   ├── LocationPickerView.swift     # MapKit address search
│   ├── RatingView.swift             # post-ride rating
│   ├── AdminView.swift              # in-app admin console (logs/users/rides tabs)
│   └── Assets.xcassets              # colors, app icon
│
├── dashboard/public/                # Firebase Hosting root
│   ├── index.html                   # auth (signup/login/verify/forgot) — dark monochrome
│   ├── app.html                     # main SPA: unified home + map + active + history + profile
│   ├── reset-password.html          # Firebase action handler — dispatches on ?mode=resetPassword|verifyEmail|recoverEmail
│   ├── admin/index.html             # legacy admin dashboard
│   └── assets/
│       ├── styles.css               # dark theme, iOS-aligned color palette
│       ├── firebase.js              # SDK init + re-exports (auth, firestore, functions)
│       ├── rides.js                 # rides CRUD, listeners, unified history query
│       ├── geo.js                   # Nominatim search + OSRM routeDistanceMiles + haversine
│       └── util.js                  # el(), toast(), fullPhone(), whatsappLink(), telLink(), fmtPickup(), timeAgo(), prefillWhatsAppMessage()
│
├── functions/                       # Cloud Functions (Node.js)
│   └── index.js                     # all functions in one file, ~1600 lines
│
├── Whatsapp BOT/                    # ingestion sidekick
│
├── firebase.json                    # hosting rewrites + cache headers, functions config
├── firestore.rules                  # security rules (users, rides, bids, etc.)
├── firestore.indexes.json           # composite indexes
└── DESIGN.md                        # this file
```

---

## 6. Visual language

**Dark, matte, iOS-aligned.** The web app mirrors the iOS app's color usage
precisely so the two feel like the same product.

```
Background   #0a0a0a
Surface      #121212 / #1a1a1a / #222222
Border       #262626 / #333333
Text         #f2f2f2 / #c7c7c7 (secondary) / #8a8a8a (muted)

Blue   #0a84ff   primary actions, active tab, "ME" map pin
Green  #30d158   WhatsApp badge + pill, accepted/started status, driver progress
Red    #ff453a   cancel, drop-off route dot, cancelled badge
Orange #ff9f0a   enroute/arrived status banners
```

All with 14% opacity tints (`--blue-10`, `--green-10`, etc.) for capsule
backgrounds, matching iOS's `Color.blue.opacity(0.1)` convention.

**Icons:** Lucide via CDN, chosen to match SF Symbols. Mapping:

| iOS SF Symbol | Lucide | Where |
|---|---|---|
| `car.fill` | `car` | rideStarted status, next-action |
| `mappin.circle.fill` | `map-pin` | arrived status, location |
| `phone.fill` | `phone` | Call pill, Contact section |
| `message.fill` | `message-circle` | WhatsApp badge + pill |
| `clock` | `clock` | waiting status |
| `clock.arrow.circlepath` | `history` | History tab |
| `checkmark.circle.fill` | `check-circle-2` | completed |
| `xmark` | `x` | cancel buttons |
| `plus` | `plus` | header Post button |
| `slider.horizontal.3` | `sliders-horizontal` | Details section header |
| `text.bubble` | `message-square` | Notes section header |
| `point...curvepath` | `route` | Route section header |
| `navigation` (→ | `navigation` | enroute, Active tab |

---

## 7. Deployment

### Web

```
firebase deploy --only hosting
```

Served at:
- `https://vaahana-fb9b8.web.app` (Firebase default)
- `https://vaahana.app` (custom domain, Namecheap → Firebase A record `199.36.158.100` + TXT verification)

HTML files are sent with `Cache-Control: no-cache, no-store, must-revalidate`
so redeploys are instant. Static assets under `/assets/**` cache for 5 min.
Stylesheets carry `?v=N` cache-bust suffix; bump N when ship-critical.

### Firestore

```
firebase deploy --only firestore:rules,firestore:indexes
```

New indexes take 2–5 min to build after deploy; queries fail until ready.

### Cloud Functions

```
firebase deploy --only functions
```

### iOS

Xcode archive → App Store Connect. Project at `Vaahana.xcodeproj`.

---

## 8. Key design decisions & why

**Why no role split on the web?** iOS's role (`rider` vs `driver`, permanent)
came from a product assumption that a phone user commits to one mode. On the
web, the context is looser — someone might want to post a ride today and
offer one tomorrow. Unified UX cuts a step and lets a user do both without
creating two accounts. The iOS role remains valid; web just ignores it.

**Why WhatsApp over in-app messaging?** It's where the community already
coordinates. Building a chat feature would fragment conversation away from
the group threads that made the product possible. The app's job is to
surface the *request*, not own the conversation.

**Why no pricing?** The original design had bid-with-price negotiation. That
was ripped out because (a) drivers treated it as insulting given the
community/volunteer dynamics, and (b) it put Vaahana on a regulatory path
(transportation network company) the product shouldn't be on. Current
message-based bids (iOS-only) are informational — "I can be there in
10 min" — not financial.

**Why Firestore's `rides` is world-readable?** Drivers need to see all hot
requests without being authenticated yet (on iOS the app checks auth before
rendering, but the admin dashboard and legacy WhatsApp-ingest debug tooling
both read without auth). The tradeoff is that rider names and rough
locations are public. Accepted.

**Why Nominatim + OSRM instead of Google Maps?** Both are free and don't
require API keys. Nominatim is rate-limited (~1/s) but for a community app
the volume is well within the limit. If the user base grows, swap in a paid
provider (Mapbox, HERE) without touching the UI — the `geo.js` module is the
only integration point.

**Why a single `ContentView.swift` with 2900+ lines on iOS?** Technical
debt. It grew organically and a split is overdue. Not a priority while
product is still in flux.

---

## 9. Open issues / TODOs

- **Custom email sender domain for `vaahana.app`** (SPF + DKIM DNS records
  pending in Namecheap). Until then, verification emails from
  `noreply@vaahana-fb9b8.firebaseapp.com` spam-filter on Gmail.
- **Driver's in-app bid UX** on iOS is still present but becoming vestigial
  as WhatsApp-first contact takes over. Deprecate or keep? Open question.
- **Rider can't edit an active ride on web.** iOS supports editing pre-accept;
  web currently doesn't. Low priority since most rides are posted and
  accepted within minutes.
- **No push notifications on web.** iOS has FCM hooks. Web would need
  `navigator.serviceWorker` + `messaging.getToken()`. Backlog.
- **Admin dashboard is desktop-only** and dated. Eventual migration to the
  new stack, or rebuild inside `app.html` gated on `isAdmin`.

---

## 10. Quick operational links

- Firebase Console: https://console.firebase.google.com/project/vaahana-fb9b8
- Live web app: https://vaahana.app (primary) · https://vaahana-fb9b8.web.app
- Admin dashboard: https://vaahana.app/admin
- Reset/verify handler: https://vaahana.app/reset-password
- GitHub: https://github.com/Puneet-Ramini/Vaahana
- Git branch: `firebase-integration` (active), `main`, `V1`
