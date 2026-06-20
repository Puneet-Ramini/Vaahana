# Vaahana Cloud Functions

Server-side lifecycle and integrity layer for Vaahana rides.

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
| `createRideRequest` | Callable | Create a rider-owned posted ride with single-active-ride enforcement |
| `claimRideAsDriver` | Callable | Assign a posted ride to a driver with availability and active-ride checks |
| `advanceRideStatus` | Callable | Move an assigned ride through its allowed status transitions |
| `cancelManagedRide` | Callable | Cancel a ride and clear both rider/driver active-ride links |
| `getAdminDashboardStats` | Callable (admin) | Return real backend counts for the admin dashboard |
| `reconcileRecentRides` | Every 5 min | Clear stale legacy response data, stale rider/driver state, and repair final rides |
| `reconcileUserLocks` | Every 5 min | Legacy no-op retained for deploy stability after pricing removal |
| `reconcileDriverAssignments` | Every 5 min | Clear stale `activeRideId` links for users no longer attached to an active ride |
| `reconcileRide` | Callable (admin) | Deep single-ride inspection + repair |

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
| `POSTED_RIDE_HAS_SELECTED_DRIVER` | Posted ride has stale driverId/selectedBidId/finalCoins | Yes — cleared |
| `STALE_ACTIVE_RIDE_LINK` | User's activeRideId points to missing or final ride | Yes — cleared |
| `MISSING_DRIVER_ON_ACTIVE_RIDE` | Active/in-progress ride has no driverId | No — logged only |
