"use strict";

/**
 * Vaahana — Reconciliation & Integrity Layer
 *
 * Four Cloud Functions:
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
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");

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

// ─── Function 4: reconcileRide (callable) ────────────────────────────────────

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
