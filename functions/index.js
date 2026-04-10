"use strict";

/**
 * Vaahana — Reconciliation & Integrity Layer
 *
 * Cloud Functions:
 *
 *  expireStaleRides           — scheduled every minute
 *    Marks posted rides as expired when their hotUntil time has passed.
 *    Server-side counterpart to the client-side expiry in RideStorage.
 *
 *  reconcileRecentRides       — scheduled every 5 min
 *    Scans non-final rides and recently-finalized rides (last 7 days).
 *    Repairs: stale active bids, locked-coin leaks, posted-ride stale fields.
 *    Logs:    missing drivers on active rides, missing coin transactions.
 *
 *  reconcileUserLocks         — scheduled every 5 min
 *    For every user with coinsLocked > 0, recomputes the expected lock amount
 *    from their active rides and patches any mismatch.
 *
 *  reconcileDriverAssignments — scheduled every 5 min
 *    For every user whose activeRideId is set, verifies the referenced ride
 *    still exists, is active, and belongs to them. Clears stale links.
 *
 *  reconcileRide              — callable (admin / debug)
 *    Deep single-ride inspection. Returns a structured result and applies all
 *    safe repairs. Useful for debugging one broken ride without waiting for cron.
 */

const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

initializeApp();
const db = getFirestore();

// ─── Constants ───────────────────────────────────────────────────────────────

const FINAL_STATUSES  = ["completed", "cancelled", "expired"];
const ACTIVE_STATUSES = ["accepted", "driver_enroute", "driver_arrived", "ride_started"];

const Severity = {
  INFO:     "info",
  WARNING:  "warning",
  ERROR:    "error",
  CRITICAL: "critical",
};

const IssueCode = {
  FINAL_RIDE_HAS_ACTIVE_BIDS:        "FINAL_RIDE_HAS_ACTIVE_BIDS",
  FINAL_RIDE_HAS_ACTIVE_DRIVER_LINK: "FINAL_RIDE_HAS_ACTIVE_DRIVER_LINK",
  MISSING_DRIVER_ON_ACTIVE_RIDE:     "MISSING_DRIVER_ON_ACTIVE_RIDE",
  POSTED_RIDE_HAS_SELECTED_DRIVER:   "POSTED_RIDE_HAS_SELECTED_DRIVER",
  LOCKED_COINS_ON_CANCELLED_RIDE:    "LOCKED_COINS_ON_CANCELLED_RIDE",
  LOCKED_COINS_MISMATCH:             "LOCKED_COINS_MISMATCH",
  MISSING_COIN_TRANSACTION:          "MISSING_COIN_TRANSACTION",
  SELECTED_BID_RIDE_MISMATCH:        "SELECTED_BID_RIDE_MISMATCH",
  STALE_ACTIVE_RIDE_LINK:            "STALE_ACTIVE_RIDE_LINK",
};

// ─── Helpers ─────────────────────────────────────────────────────────────────

/**
 * Writes one entry to the reconciliationLogs collection.
 * Never throws — reconciliation must not abort due to logging failures.
 */
async function writeLog({ entityType, entityId, severity, issueCode, actionTaken, details }) {
  try {
    await db.collection("reconciliationLogs").add({
      entityType,
      entityId,
      severity,
      issueCode,
      actionTaken: actionTaken || "logged",
      details:     details || {},
      detectedAt:  FieldValue.serverTimestamp(),
    });
  } catch (err) {
    console.error("[reconcile] Failed to write log:", err.message);
  }
}

// ─── Push Notification Helper ─────────────────────────────────────────────────

/**
 * Looks up the user's FCM token from Firestore and sends a push notification.
 * Never throws — a missing token or failed send is silently logged.
 */
async function sendToUser(uid, title, body, data = {}) {
  if (!uid) return;
  try {
    const userDoc = await db.collection("users").doc(uid).get();
    const token = userDoc.exists ? userDoc.data().fcmToken : null;
    if (!token) return;
    // FCM data values must all be strings
    const stringData = Object.fromEntries(
      Object.entries(data).map(([k, v]) => [k, String(v)])
    );
    await getMessaging().send({
      token,
      notification: { title, body },
      data: stringData,
      apns: { payload: { aps: { sound: "default" } } },
    });
  } catch (err) {
    console.warn(`[notify] send to ${uid} failed:`, err.message);
  }
}

// ─── Single-Ride Inspector ────────────────────────────────────────────────────

/**
 * Inspects one ride document and applies all safe repairs in-place.
 * Returns an array of { code, actionTaken, details } objects for each issue found.
 *
 * Safe auto-repairs applied here:
 *   - Close active bids on final rides
 *   - Refund locked coins on cancelled/expired rides
 *   - Clear stale driver/bid/finalCoins fields on posted rides
 *
 * Log-only (not auto-repaired):
 *   - Missing driver on active ride
 *   - Missing coin transaction on completed ride
 */
async function inspectRide(rideDoc) {
  const ride    = rideDoc.data();
  const rideRef = rideDoc.ref;
  const rideId  = rideDoc.id;
  const status  = ride.status;
  const isFinal = FINAL_STATUSES.includes(status);
  const issues  = [];

  // ── A1 & A5: Final rides — close active bids & refund locked coins ─────────

  if (isFinal) {
    // Close any bids still marked active
    const activeBidsSnap = await rideRef.collection("bids")
      .where("status", "==", "active")
      .get();

    if (!activeBidsSnap.empty) {
      const closeStatus = status === "completed" ? "autoClosed" : "expired";
      const batch = db.batch();
      for (const bidDoc of activeBidsSnap.docs) {
        batch.update(bidDoc.ref, {
          status:    closeStatus,
          updatedAt: FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();

      const issue = {
        code:       IssueCode.FINAL_RIDE_HAS_ACTIVE_BIDS,
        actionTaken: `auto_closed_${activeBidsSnap.size}_bids_as_${closeStatus}`,
        details: { rideStatus: status, bidCount: activeBidsSnap.size },
      };
      issues.push(issue);
      await writeLog({ entityType: "ride", entityId: rideId, severity: Severity.WARNING, ...issue });
    }

    // Refund locked coins on cancelled/expired rides
    const coinsLocked = ride.coinsLocked || 0;
    const needsRefund  = (status === "cancelled" || status === "expired") && coinsLocked > 0;

    if (needsRefund && ride.riderId) {
      const riderRef = db.collection("users").doc(ride.riderId);
      const batch    = db.batch();
      batch.update(riderRef, {
        coins:       FieldValue.increment(coinsLocked),
        coinsLocked: FieldValue.increment(-coinsLocked),
      });
      batch.update(rideRef, {
        coinStatus:  "refunded",
        coinsLocked: 0,
        updatedAt:   FieldValue.serverTimestamp(),
      });
      await batch.commit();

      const issue = {
        code:       IssueCode.LOCKED_COINS_ON_CANCELLED_RIDE,
        actionTaken: "auto_refunded",
        details: { rideStatus: status, riderId: ride.riderId, coinsLocked },
      };
      issues.push(issue);
      await writeLog({ entityType: "ride", entityId: rideId, severity: Severity.WARNING, ...issue });
    }

    // Log completed rides missing a coin transaction (manual review only)
    if (status === "completed") {
      const txSnap = await db.collection("coinTransactions")
        .where("rideId", "==", rideId)
        .limit(1)
        .get();

      if (txSnap.empty) {
        const issue = {
          code:       IssueCode.MISSING_COIN_TRANSACTION,
          actionTaken: "logged_for_manual_review",
          details: {
            driverId:        ride.driverId || null,
            coinsTransferred: ride.coinsTransferred || 0,
          },
        };
        issues.push(issue);
        await writeLog({ entityType: "ride", entityId: rideId, severity: Severity.ERROR, ...issue });
      }
    }
  }

  // ── A2: Active rides must have a driver ────────────────────────────────────

  if (ACTIVE_STATUSES.includes(status) && !ride.driverId) {
    const issue = {
      code:       IssueCode.MISSING_DRIVER_ON_ACTIVE_RIDE,
      actionTaken: "logged_for_manual_review",
      details: { rideStatus: status },
    };
    issues.push(issue);
    await writeLog({ entityType: "ride", entityId: rideId, severity: Severity.ERROR, ...issue });
  }

  // ── A3: Posted rides must have no driver assignment ────────────────────────

  if (status === "posted") {
    const staleFields = {};
    if (ride.driverId)      staleFields.driverId      = FieldValue.delete();
    if (ride.selectedBidId) staleFields.selectedBidId = FieldValue.delete();
    if (ride.finalCoins)    staleFields.finalCoins    = FieldValue.delete();
    if (ride.coinsLocked && ride.coinsLocked > 0) staleFields.coinsLocked = 0;

    if (Object.keys(staleFields).length > 0) {
      staleFields.updatedAt = FieldValue.serverTimestamp();
      await rideRef.update(staleFields);

      const issue = {
        code:       IssueCode.POSTED_RIDE_HAS_SELECTED_DRIVER,
        actionTaken: "auto_cleared_stale_fields",
        details: {
          clearedFields: Object.keys(staleFields).filter((k) => k !== "updatedAt"),
        },
      };
      issues.push(issue);
      await writeLog({ entityType: "ride", entityId: rideId, severity: Severity.WARNING, ...issue });
    }
  }

  return issues;
}

// ─── Function 1: reconcileRecentRides ────────────────────────────────────────

exports.reconcileRecentRides = onSchedule(
  {
    schedule:       "*/5 * * * *",
    timeoutSeconds: 540,
    memory:         "256MiB",
  },
  async () => {
    const sevenDaysAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);

    // Non-final rides (always scan — these are live)
    const nonFinalSnap = await db.collection("rides")
      .where("status", "in", [...ACTIVE_STATUSES, "posted"])
      .get();

    // Recently finalized rides (may still carry stale state)
    const recentFinalSnap = await db.collection("rides")
      .where("status", "in", FINAL_STATUSES)
      .where("updatedAt", ">=", sevenDaysAgo)
      .get();

    // Deduplicate by doc ID (a ride could match both queries if it transitioned recently)
    const seen = new Set();
    const allDocs = [];
    for (const doc of [...nonFinalSnap.docs, ...recentFinalSnap.docs]) {
      if (!seen.has(doc.id)) {
        seen.add(doc.id);
        allDocs.push(doc);
      }
    }

    console.log(`[reconcileRecentRides] Scanning ${allDocs.length} rides`);
    let totalIssues = 0;

    for (const rideDoc of allDocs) {
      try {
        const issues = await inspectRide(rideDoc);
        totalIssues += issues.length;
      } catch (err) {
        console.error(`[reconcileRecentRides] Error on ride ${rideDoc.id}:`, err.message);
      }
    }

    console.log(`[reconcileRecentRides] Done. Rides: ${allDocs.length}, Issues: ${totalIssues}`);
  }
);

// ─── Function 2: reconcileUserLocks ──────────────────────────────────────────

exports.reconcileUserLocks = onSchedule(
  {
    schedule:       "*/5 * * * *",
    timeoutSeconds: 540,
    memory:         "256MiB",
  },
  async () => {
    // All users who have locked coins
    const usersSnap = await db.collection("users")
      .where("coinsLocked", ">", 0)
      .get();

    console.log(`[reconcileUserLocks] Checking ${usersSnap.size} users with coinsLocked > 0`);
    let corrections = 0;

    for (const userDoc of usersSnap.docs) {
      try {
        const uid           = userDoc.id;
        const currentLocked = userDoc.data().coinsLocked || 0;

        // Fetch all rides where this rider has coins in locked state
        const lockedRidesSnap = await db.collection("rides")
          .where("riderId", "==", uid)
          .where("coinStatus", "==", "locked")
          .get();

        // Only count coins from non-final rides
        let expectedLocked = 0;
        for (const rideDoc of lockedRidesSnap.docs) {
          const rideData = rideDoc.data();
          if (!FINAL_STATUSES.includes(rideData.status)) {
            expectedLocked += rideData.coinsLocked || 0;
          }
        }

        if (currentLocked !== expectedLocked) {
          await db.collection("users").doc(uid).update({
            coinsLocked: expectedLocked,
            updatedAt:   FieldValue.serverTimestamp(),
          });
          corrections++;
          await writeLog({
            entityType: "user",
            entityId:   uid,
            severity:   Severity.WARNING,
            issueCode:  IssueCode.LOCKED_COINS_MISMATCH,
            actionTaken: "auto_corrected",
            details: {
              wasLocked:       currentLocked,
              nowLocked:       expectedLocked,
              lockedRideCount: lockedRidesSnap.size,
            },
          });
        }
      } catch (err) {
        console.error(`[reconcileUserLocks] Error on user ${userDoc.id}:`, err.message);
      }
    }

    console.log(`[reconcileUserLocks] Done. Users checked: ${usersSnap.size}, Corrected: ${corrections}`);
  }
);

// ─── Function 3: reconcileDriverAssignments ───────────────────────────────────

exports.reconcileDriverAssignments = onSchedule(
  {
    schedule:       "*/5 * * * *",
    timeoutSeconds: 300,
    memory:         "256MiB",
  },
  async () => {
    // All users with activeRideId set (stored as a non-empty UUID string)
    const usersSnap = await db.collection("users")
      .where("activeRideId", ">=", " ")
      .get();

    console.log(`[reconcileDriverAssignments] Checking ${usersSnap.size} users with activeRideId`);
    let clears = 0;

    for (const userDoc of usersSnap.docs) {
      try {
        const uid         = userDoc.id;
        const activeRideId = userDoc.data().activeRideId;

        const rideDoc = await db.collection("rides").doc(activeRideId).get();

        // Case 1: referenced ride doesn't exist
        if (!rideDoc.exists) {
          await userDoc.ref.update({ activeRideId: FieldValue.delete() });
          clears++;
          await writeLog({
            entityType: "user", entityId: uid,
            severity:   Severity.WARNING,
            issueCode:  IssueCode.STALE_ACTIVE_RIDE_LINK,
            actionTaken: "auto_cleared",
            details: { activeRideId, reason: "ride_not_found" },
          });
          continue;
        }

        const rideData   = rideDoc.data();
        const rideStatus = rideData.status;

        // Case 2: ride is in a final state
        if (FINAL_STATUSES.includes(rideStatus)) {
          await userDoc.ref.update({ activeRideId: FieldValue.delete() });
          clears++;
          await writeLog({
            entityType: "user", entityId: uid,
            severity:   Severity.WARNING,
            issueCode:  IssueCode.STALE_ACTIVE_RIDE_LINK,
            actionTaken: "auto_cleared",
            details: { activeRideId, rideStatus, reason: "ride_is_final" },
          });
          continue;
        }

        // Case 3: this user is not the driver on that ride
        if (rideData.driverId !== uid) {
          await userDoc.ref.update({ activeRideId: FieldValue.delete() });
          clears++;
          await writeLog({
            entityType: "user", entityId: uid,
            severity:   Severity.ERROR,
            issueCode:  IssueCode.STALE_ACTIVE_RIDE_LINK,
            actionTaken: "auto_cleared",
            details: {
              activeRideId,
              rideStatus,
              reason:          "driver_mismatch",
              actualDriverId:  rideData.driverId || null,
            },
          });
        }

        // All good — ride is active and belongs to this driver
      } catch (err) {
        console.error(`[reconcileDriverAssignments] Error on user ${userDoc.id}:`, err.message);
      }
    }

    console.log(`[reconcileDriverAssignments] Done. Users checked: ${usersSnap.size}, Links cleared: ${clears}`);
  }
);

// ─── Function 4: grantDailyCoins ─────────────────────────────────────────────

/**
 * Runs at midnight UTC every day.
 * Grants 100 coins to every user who hasn't already received them today
 * (checked via the `lastDailyCoinDate` field — "YYYY-MM-DD" string).
 *
 * The iOS app also does a client-side grant on launch as a failsafe,
 * but this function covers users who don't open the app that day.
 */
exports.grantDailyCoins = onSchedule(
  {
    schedule:       "0 0 * * *",   // midnight UTC
    timeoutSeconds: 540,
    memory:         "512MiB",
  },
  async () => {
    const today        = new Date().toISOString().split("T")[0]; // "2026-04-10"
    const allUsersSnap = await db.collection("users").get();

    const BATCH_SIZE = 450;
    let batch        = db.batch();
    let opCount      = 0;
    let grantCount   = 0;

    for (const userDoc of allUsersSnap.docs) {
      const lastGrant = userDoc.data().lastDailyCoinDate || "";
      if (lastGrant === today) continue; // already granted today

      batch.update(userDoc.ref, {
        coins:             FieldValue.increment(100),
        lastDailyCoinDate: today,
      });
      opCount++;
      grantCount++;

      if (opCount >= BATCH_SIZE) {
        await batch.commit();
        batch   = db.batch();
        opCount = 0;
      }
    }

    if (opCount > 0) await batch.commit();
    console.log(`[grantDailyCoins] Granted 100 coins to ${grantCount}/${allUsersSnap.size} users on ${today}`);
  }
);

// ─── Function 5: reconcileRide (callable) ────────────────────────────────────

/**
 * Admin/debug callable function for deep single-ride inspection.
 *
 * Call from your admin tool or Firebase console:
 *   reconcileRide({ rideId: "some-uuid" })
 *
 * Returns:
 *   { rideId, status, issues: [...], repairs: [...], clean: bool }
 */
exports.reconcileRide = onCall(
  { enforceAppCheck: false },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in.");
    }

    const rideId = request.data && request.data.rideId;
    if (!rideId || typeof rideId !== "string") {
      throw new HttpsError("invalid-argument", "rideId (string) is required.");
    }

    const rideDoc = await db.collection("rides").doc(rideId).get();
    if (!rideDoc.exists) {
      throw new HttpsError("not-found", `Ride ${rideId} not found.`);
    }

    const issues = await inspectRide(rideDoc);

    // Also write a single summary log entry when called manually
    if (issues.length > 0) {
      await writeLog({
        entityType: "ride",
        entityId:   rideId,
        severity:   Severity.WARNING,
        issueCode:  issues.map((i) => i.code).join(","),
        actionTaken: issues.map((i) => i.actionTaken).join(","),
        details: {
          triggeredBy: request.auth.uid,
          issueCount:  issues.length,
        },
      });
    }

    return {
      rideId,
      status:  rideDoc.data().status,
      issues:  issues.map((i) => ({ code: i.code, actionTaken: i.actionTaken })),
      clean:   issues.length === 0,
    };
  }
);

// ─── Function 6: expireStaleRides ────────────────────────────────────────────

/**
 * Runs every minute. Finds all rides with status="posted" whose hotUntil time
 * has passed (createdAt + hotDuration minutes <= now) and marks them "expired".
 *
 * This is the server-side counterpart to the client-side expiry in RideStorage.
 * It ensures rides expire even when no rider has the app open.
 */
exports.expireStaleRides = onSchedule(
  {
    schedule:       "* * * * *",   // every minute
    timeoutSeconds: 120,
    memory:         "256MiB",
  },
  async () => {
    const now = new Date();

    // Fetch all posted rides. We must filter hotUntil in-process because
    // Firestore can't query on a computed field — hotUntil = createdAt + hotDuration*60s.
    const postedSnap = await db.collection("rides")
      .where("status", "==", "posted")
      .get();

    if (postedSnap.empty) return;

    const BATCH_SIZE = 450;
    let batch    = db.batch();
    let opCount  = 0;
    let expired  = 0;

    for (const doc of postedSnap.docs) {
      const data        = doc.data();
      const createdAt   = data.createdAt?.toDate?.() ?? null;
      const hotDuration = typeof data.hotDuration === "number" ? data.hotDuration : 5;

      if (!createdAt) continue;

      const hotUntil = new Date(createdAt.getTime() + hotDuration * 60 * 1000);
      if (now < hotUntil) continue; // still hot

      batch.update(doc.ref, {
        status:    "expired",
        updatedAt: FieldValue.serverTimestamp(),
      });
      opCount++;
      expired++;

      if (opCount >= BATCH_SIZE) {
        await batch.commit();
        batch   = db.batch();
        opCount = 0;
      }
    }

    if (opCount > 0) await batch.commit();

    if (expired > 0) {
      console.log(`[expireStaleRides] Expired ${expired} stale posted rides`);
    }
  }
);

// ─── Function 7: onBidPlaced ──────────────────────────────────────────────────

/**
 * Fires when a driver places a new bid on a ride.
 * Notifies the rider so they don't have to keep the app open.
 */
exports.onBidPlaced = onDocumentCreated(
  { document: "rides/{rideId}/bids/{bidId}" },
  async (event) => {
    const bid    = event.data.data();
    const rideId = event.params.rideId;

    const rideDoc = await db.collection("rides").doc(rideId).get();
    if (!rideDoc.exists) return;
    const ride = rideDoc.data();
    if (ride.status !== "posted") return;

    const driverName = bid.driverName || "A driver";
    const coins      = bid.bidCoins   || 0;

    await sendToUser(
      ride.riderId,
      "New bid on your ride",
      `${driverName} offered ${coins} coins for ${ride.from} → ${ride.to}`,
      { type: "new_bid", rideId }
    );
  }
);

// ─── Function 7: onRideStatusChanged ─────────────────────────────────────────

/**
 * Fires whenever a ride document is updated.
 * Sends targeted push notifications based on the status transition.
 */
exports.onRideStatusChanged = onDocumentUpdated(
  { document: "rides/{rideId}" },
  async (event) => {
    const before   = event.data.before.data();
    const after    = event.data.after.data();
    const rideId   = event.params.rideId;

    if (before.status === after.status) return; // no status change

    const { riderId, driverId, from, to, driverName, name } = after;

    switch (after.status) {
      case "accepted":
        // Rider selected a bid — notify the driver they've been chosen
        if (driverId) {
          await sendToUser(
            driverId,
            "Your bid was accepted!",
            `Head to ${from} to pick up ${name || "your rider"}`,
            { type: "bid_accepted", rideId }
          );
        }
        break;

      case "driver_enroute":
        await sendToUser(
          riderId,
          "Driver is on the way",
          `${driverName || "Your driver"} is heading to ${from}`,
          { type: "driver_enroute", rideId }
        );
        break;

      case "driver_arrived":
        await sendToUser(
          riderId,
          "Driver has arrived",
          `${driverName || "Your driver"} is waiting at ${from}`,
          { type: "driver_arrived", rideId }
        );
        break;

      case "ride_started":
        await sendToUser(
          riderId,
          "Ride started",
          `You're on your way to ${to}. Enjoy the ride!`,
          { type: "ride_started", rideId }
        );
        break;

      case "completed":
        await sendToUser(
          riderId,
          "Ride completed",
          "Hope you had a great ride! Rate your driver.",
          { type: "ride_completed", rideId }
        );
        if (driverId) {
          await sendToUser(
            driverId,
            "Ride completed",
            "Coins have been transferred. Rate your rider!",
            { type: "ride_completed", rideId }
          );
        }
        break;

      case "cancelled":
        if (after.cancelledBy === riderId && driverId) {
          await sendToUser(
            driverId,
            "Ride cancelled",
            `${name || "The rider"} cancelled the ride (${from} → ${to})`,
            { type: "cancelled", rideId }
          );
        } else if (after.cancelledBy !== riderId) {
          await sendToUser(
            riderId,
            "Ride cancelled",
            `${driverName || "Your driver"} cancelled the ride`,
            { type: "cancelled", rideId }
          );
        }
        break;

      default:
        break;
    }
  }
);
