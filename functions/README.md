# Vaahana Cloud Functions

Reconciliation and integrity layer for the Vaahana ride marketplace.

## Setup

```bash
# Install Node.js 20+ (https://nodejs.org or via nvm)
nvm install 20 && nvm use 20

# Install Firebase CLI
npm install -g firebase-tools

# Authenticate
firebase login

# Install function dependencies
cd functions
npm install
```

## Deploy

```bash
# From the repo root
firebase deploy --only functions
```

## Functions

| Function | Trigger | Purpose |
|---|---|---|
| `reconcileRecentRides` | Every 5 min | Close stale bids, refund leaked coins, clear posted-ride stale fields |
| `reconcileUserLocks` | Every 5 min | Recompute `coinsLocked` from actual active rides |
| `reconcileDriverAssignments` | Every 5 min | Clear stale `activeRideId` links pointing to final or missing rides |
| `reconcileRide` | Callable (on demand) | Deep single-ride inspection + repair |

## Calling reconcileRide manually

From the Firebase console → Functions → `reconcileRide`, or from your app:

```swift
let functions = Functions.functions()
functions.httpsCallable("reconcileRide").call(["rideId": "some-uuid"]) { result, error in
    print(result?.data ?? error ?? "done")
}
```

## Logs

All issues and repairs are written to the `reconciliationLogs` Firestore collection:

```
reconciliationLogs/{logId}
  entityType:  "ride" | "user"
  entityId:    string
  severity:    "info" | "warning" | "error" | "critical"
  issueCode:   string (see IssueCode in index.js)
  actionTaken: string
  details:     object
  detectedAt:  timestamp
```

Query logs in the Firebase console or with:

```js
db.collection("reconciliationLogs")
  .where("severity", "==", "error")
  .orderBy("detectedAt", "desc")
  .limit(50)
  .get()
```

## Issue Codes

| Code | Meaning | Auto-repaired? |
|---|---|---|
| `FINAL_RIDE_HAS_ACTIVE_BIDS` | Bids still active on completed/cancelled/expired ride | Yes — closed |
| `LOCKED_COINS_ON_CANCELLED_RIDE` | Coins still locked after ride cancelled/expired | Yes — refunded |
| `POSTED_RIDE_HAS_SELECTED_DRIVER` | Posted ride has stale driverId/selectedBidId/finalCoins | Yes — cleared |
| `STALE_ACTIVE_RIDE_LINK` | User's activeRideId points to missing or final ride | Yes — cleared |
| `LOCKED_COINS_MISMATCH` | User's coinsLocked doesn't match sum of active ride locks | Yes — corrected |
| `MISSING_DRIVER_ON_ACTIVE_RIDE` | Active/in-progress ride has no driverId | No — logged only |
| `MISSING_COIN_TRANSACTION` | Completed ride has no entry in coinTransactions | No — logged only |
