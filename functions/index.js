"use strict";

/**
 * Vaahana — Cloud Functions
 *
 *  ingestWhatsAppMessages     — HTTP POST endpoint
 *    Accepts raw WhatsApp group export text (or pre-split message array).
 *    Parses ride requests with regex, deduplicates, matches phone numbers to
 *    existing users, and creates rides documents visible to drivers.
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
const { onCall, HttpsError, onRequest } = require("firebase-functions/v2/https");
const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const { defineSecret } = require("firebase-functions/params");
const crypto = require("crypto");

const WHATSAPP_API_KEY = defineSecret("WHATSAPP_INGEST_API_KEY");

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

// ─── WhatsApp Ingestion Pipeline ─────────────────────────────────────────────
//
// Input (POST /ingestWhatsAppMessages):
//   Either raw export text:
//     { "rawExport": "[5:34 PM, 4/9/2026] +1 (203) 823-2473: Anybody travelling..." }
//   Or pre-split array:
//     { "messages": [{ "phone": "+12038232473", "text": "...", "timestamp": "..." }] }
//
// Pipeline:
//   1. Parse raw export into { phone, text, timestamp } objects
//   2. Regex-classify each message (ride request vs. irrelevant)
//   3. Extract route fields: from, to, pickupDate, hotDuration
//   4. Deduplicate against recent rides (same phone + from + date within 24h)
//   5. Phone-match to existing Vaahana user (or create placeholder)
//   6. Write ride document with source="whatsapp"

// ── 1. Parse raw WhatsApp export text ────────────────────────────────────────

/**
 * Parses a raw WhatsApp group export string into individual message objects.
 *
 * Handles both formats:
 *   "[5:34 PM, 4/9/2026] +1 (203) 823-2473: message text"
 *   "5:34 PM, 4/9/2026 - +1 (203) 823-2473: message text"  (Android export)
 */
function parseWhatsAppExport(rawText) {
  const messages = [];

  // Match lines starting with a timestamp + phone number
  // Supports: [H:MM PM, M/D/YYYY] or [HH:MM, DD/MM/YYYY] formats
  const lineRegex = /^\[(\d{1,2}:\d{2}(?::\d{2})?\s*(?:AM|PM)?),?\s*(\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4})\]\s*([+\d][\d\s\-().]+?):\s*(.+)$/im;

  // Split on message boundaries (lines that start with a bracket timestamp)
  const boundaryRegex = /(?=^\[)/m;
  const chunks = rawText.split(/\r?\n(?=\[)/);

  for (const chunk of chunks) {
    const trimmed = chunk.trim();
    if (!trimmed) continue;

    const match = trimmed.match(/^\[(\d{1,2}:\d{2}(?::\d{2})?\s*(?:AM|PM)?),?\s*(\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4})\]\s*([+\d][\d\s\-().]{6,20}?):\s*([\s\S]+)$/i);
    if (!match) continue;

    const [, timePart, datePart, rawPhone, text] = match;
    const phone = normalizePhone(rawPhone.trim());
    if (!phone) continue;

    // Parse timestamp — try M/D/YYYY first (iOS), then D/M/YYYY (Android)
    const timestamp = parseMessageTimestamp(datePart.trim(), timePart.trim());

    messages.push({ phone, text: text.trim().replace(/\n/g, " "), timestamp });
  }

  return messages;
}

// ── 2. Phone normalization ────────────────────────────────────────────────────

/**
 * Normalises a phone number string to E.164 format (e.g. "+12038232473").
 * Returns null if the input doesn't look like a real phone number.
 */
function normalizePhone(raw) {
  // Strip everything except digits and leading +
  const digits = raw.replace(/[^\d+]/g, "");
  if (digits.length < 7) return null;

  if (digits.startsWith("+")) return digits;

  // 10-digit US number → prepend +1
  if (digits.length === 10) return `+1${digits}`;

  // 11-digit starting with 1 → +1XXXXXXXXXX
  if (digits.length === 11 && digits.startsWith("1")) return `+${digits}`;

  // Indian numbers: 10-digit starting with 6-9
  if (digits.length === 10 && /^[6-9]/.test(digits)) return `+91${digits}`;
  if (digits.length === 12 && digits.startsWith("91")) return `+${digits}`;

  return `+${digits}`;
}

// ── 3. Timestamp parsing ──────────────────────────────────────────────────────

function parseMessageTimestamp(datePart, timePart) {
  try {
    // datePart: "4/9/2026" or "09/04/2026"
    const datePieces = datePart.split(/[\/\-]/).map(Number);
    let month, day, year;

    if (datePieces[2] > 31) {
      // M/D/YYYY (iOS)
      [month, day, year] = datePieces;
    } else if (datePieces[0] > 12) {
      // D/M/YYYY (Android, day > 12 disambiguates)
      [day, month, year] = datePieces;
    } else {
      // Ambiguous — assume M/D/YYYY (iOS is primary target)
      [month, day, year] = datePieces;
    }

    if (year < 100) year += 2000;

    // timePart: "5:34 PM" or "17:34"
    const timeMatch = timePart.match(/(\d{1,2}):(\d{2})(?::\d{2})?\s*(AM|PM)?/i);
    if (!timeMatch) return new Date(year, month - 1, day);

    let hours = parseInt(timeMatch[1]);
    const minutes = parseInt(timeMatch[2]);
    const ampm = timeMatch[3]?.toUpperCase();
    if (ampm === "PM" && hours < 12) hours += 12;
    if (ampm === "AM" && hours === 12) hours = 0;

    return new Date(year, month - 1, day, hours, minutes);
  } catch {
    return new Date();
  }
}

// ── 4. Ride request classification & field extraction ─────────────────────────

const RIDE_KEYWORDS = /\b(need\s+ride|need\s+a\s+ride|looking\s+for\s+(?:a\s+)?ride|anybody\s+(?:going|travelling|traveling)|anyone\s+(?:going|travelling|traveling)|travelling\s+by\s+road|traveling\s+by\s+road|shared\s+ride|carpool|ride\s+share|rideshare|ride\s+from|ride\s+to|going\s+from|going\s+to)\b/i;

const DISCARD_KEYWORDS = /\b(accommodation|apartment|room\s+for|room\s+available|bed\s+available|sublet|looking\s+for\s+room|looking\s+for\s+accommodation|house|flat\s+available|roommate|room\s+mate)\b/i;

// Patterns for "from X to Y"
const FROM_TO_PATTERNS = [
  /\bfrom\s+([A-Za-z0-9\s,./]+?)\s+to\s+([A-Za-z0-9\s,./]+?)(?:\s+(?:at|by|around|on|tomorrow|tonight|today|next|\d)|[,.]|$)/i,
  /\bfrom\s+([A-Za-z0-9\s,./]+?)\s+to\s+([A-Za-z0-9\s,./]+?)$/i,
];

// "from X" with no destination
const FROM_ONLY_PATTERN = /\bfrom\s+([A-Za-z0-9\s,./]+?)(?:\s+(?:at|by|around|on|tomorrow|tonight|today|\d)|[,.]|$)/i;

// "in X at TIME" (no explicit from/to like "Need ride in Lowell at 8am")
const IN_LOCATION_PATTERN = /\brides?\s+in\s+([A-Za-z0-9\s,./]+?)(?:\s+(?:at|by|around|on|tomorrow|tonight|today|\d)|[,.]|$)/i;

// Time patterns
const TIME_PATTERN = /\b(?:at\s+)?(\d{1,2}(?::\d{2})?\s*(?:AM|PM|am|pm)|midnight|noon)\b/i;

// Urgency keywords for hotDuration inference
const URGENCY_TONIGHT   = /\b(tonight|right now|asap|urgent|immediately|now)\b/i;
const URGENCY_TODAY     = /\b(today|this\s+(?:morning|afternoon|evening)|in\s+\d+\s+(?:hour|min))\b/i;
const URGENCY_TOMORROW  = /\b(tomorrow|tmrw|tmr)\b/i;
const URGENCY_VAGUE     = /\b(next\s+(?:few\s+)?(?:days?|weeks?)|sometime|soon|whenever|flexible)\b/i;

// Explicit calendar date: "April 15", "April 15th", "on the 15th", "15th of April"
const MONTH_NAMES = {
  january:1, february:2, march:3, april:4, may:5, june:6,
  july:7, august:8, september:9, october:10, november:11, december:12,
  jan:1, feb:2, mar:3, apr:4, jun:6, jul:7, aug:8, sep:9, oct:10, nov:11, dec:12,
};
const EXPLICIT_DATE_PATTERN = /\b(january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sep|oct|nov|dec)\s+(\d{1,2})(?:st|nd|rd|th)?\b|\b(\d{1,2})(?:st|nd|rd|th)?\s+(?:of\s+)?(january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sep|oct|nov|dec)\b/i;

/**
 * Attempts to extract an explicit calendar date from message text.
 * Returns a Date set to that date (current or next year if in the past), or null.
 */
function extractExplicitDate(text) {
  const m = text.match(EXPLICIT_DATE_PATTERN);
  if (!m) return null;

  let month, day;
  if (m[1] && m[2]) {
    // "April 15"
    month = MONTH_NAMES[m[1].toLowerCase()];
    day   = parseInt(m[2]);
  } else if (m[3] && m[4]) {
    // "15th of April"
    day   = parseInt(m[3]);
    month = MONTH_NAMES[m[4].toLowerCase()];
  }
  if (!month || !day) return null;

  const now = new Date();
  let year  = now.getFullYear();
  const candidate = new Date(year, month - 1, day, 8, 0, 0);
  // If the date is in the past (more than 1 day ago), roll to next year
  if (candidate < new Date(Date.now() - 24 * 60 * 60 * 1000)) {
    candidate.setFullYear(year + 1);
  }
  return candidate;
}

/**
 * Attempts to classify and extract structured ride data from a message.
 * Returns null if the message is not a ride request.
 */
function extractRideData(text, messageTimestamp) {
  // Discard non-ride messages (accommodation, etc.)
  if (DISCARD_KEYWORDS.test(text)) return null;

  // Must match at least one ride keyword
  if (!RIDE_KEYWORDS.test(text)) return null;

  // Extract from / to
  let from = null;
  let to = null;

  for (const pattern of FROM_TO_PATTERNS) {
    const m = text.match(pattern);
    if (m) {
      from = cleanLocation(m[1]);
      to   = cleanLocation(m[2]);
      break;
    }
  }

  if (!from) {
    const m = text.match(FROM_ONLY_PATTERN);
    if (m) from = cleanLocation(m[1]);
  }

  if (!from) {
    const m = text.match(IN_LOCATION_PATTERN);
    if (m) from = cleanLocation(m[1]);
  }

  // Still no location at all — too vague to create a ride
  if (!from) return null;

  if (!to) to = "Destination TBD";

  // Extract time
  const timeMatch = text.match(TIME_PATTERN);
  const timeStr = timeMatch ? timeMatch[1] : null;

  // Infer pickup date from urgency cues + message timestamp
  const pickupDate = inferPickupDate(text, timeStr, messageTimestamp);

  // Infer hot duration
  const hotDuration = inferHotDuration(text, pickupDate, messageTimestamp);

  return { from, to, pickupDate, hotDuration, rawTimeHint: timeStr };
}

function cleanLocation(str) {
  return str.trim().replace(/\s+/g, " ").replace(/[.,]+$/, "").trim();
}

/**
 * Infers the pickup date from urgency cues in the message text.
 * Falls back to the message timestamp date if no cue found.
 */
function inferPickupDate(text, timeStr, msgTimestamp) {
  const base = new Date(msgTimestamp);
  let targetDate = new Date(base);

  // 1. Explicit calendar date takes highest priority ("April 15", "15th of May")
  const explicitDate = extractExplicitDate(text);
  if (explicitDate) {
    targetDate = explicitDate;
    // Still apply extracted time on top of explicit date
    if (timeStr) {
      const parsed = parseTimeString(timeStr, targetDate);
      if (parsed) return parsed;
    }
    return targetDate;
  }

  // 2. Relative urgency cues
  // Always anchor to NOW (not message timestamp) so older messages still resolve correctly
  if (URGENCY_TONIGHT.test(text)) {
    targetDate = new Date();
    // If a specific time is given, parseTimeString will override; otherwise default to 8pm
    if (!timeStr) { targetDate.setHours(20, 0, 0, 0); return targetDate; }
  } else if (URGENCY_TOMORROW.test(text)) {
    targetDate = new Date();
    targetDate.setDate(targetDate.getDate() + 1);
  } else if (URGENCY_TODAY.test(text)) {
    targetDate = new Date();
  } else if (URGENCY_VAGUE.test(text)) {
    // Use 3 days from now as a reasonable midpoint
    targetDate = new Date();
    targetDate.setDate(targetDate.getDate() + 3);
  } else {
    // No date cue at all — treat as needed now.
    // Set pickup to current time + 30 minutes.
    targetDate = new Date(Date.now() + 30 * 60 * 1000);
  }

  // Apply extracted time if present
  if (timeStr) {
    const parsed = parseTimeString(timeStr, targetDate);
    if (parsed) return parsed;
  }

  // Default to 8am on the target date
  targetDate.setHours(8, 0, 0, 0);
  return targetDate;
}

function parseTimeString(timeStr, baseDate) {
  try {
    const t = timeStr.toLowerCase().trim();
    if (t === "midnight") {
      const d = new Date(baseDate); d.setHours(0, 0, 0, 0); return d;
    }
    if (t === "noon") {
      const d = new Date(baseDate); d.setHours(12, 0, 0, 0); return d;
    }
    const m = t.match(/(\d{1,2})(?::(\d{2}))?\s*(am|pm)?/);
    if (!m) return null;
    let h = parseInt(m[1]);
    const min = parseInt(m[2] || "0");
    const ampm = m[3];
    if (ampm === "pm" && h < 12) h += 12;
    if (ampm === "am" && h === 12) h = 0;
    // If no am/pm: times 1-6 are likely PM for rides (heuristic)
    if (!ampm && h >= 1 && h <= 6) h += 12;
    const d = new Date(baseDate);
    d.setHours(h, min, 0, 0);
    return d;
  } catch {
    return null;
  }
}

/**
 * Infers how long a ride should stay "hot" (visible to drivers) based on urgency.
 *   tonight/explicit time today  → 60 min
 *   tomorrow / tomorrow + time   → 480 min (8h)
 *   vague / "next few weeks"     → 2880 min (48h)
 */
function inferHotDuration(text, pickupDate, msgTimestamp) {
  if (URGENCY_TONIGHT.test(text))  return 60;
  if (URGENCY_TODAY.test(text))    return 120;
  if (URGENCY_TOMORROW.test(text)) return 480;
  if (URGENCY_VAGUE.test(text))    return 2880;
  // Explicit date: stay hot until the pickup day arrives (max 48h cap)
  if (extractExplicitDate(text))   return 2880;
  // No date cue — treat as immediate, short hot window
  return 60;

  // Fallback: compare pickup date to message date
  const msUntilPickup = pickupDate.getTime() - new Date(msgTimestamp).getTime();
  const hoursUntil = msUntilPickup / (1000 * 60 * 60);

  if (hoursUntil <= 6)  return 60;
  if (hoursUntil <= 24) return 240;
  if (hoursUntil <= 72) return 480;
  return 2880;
}

// ── 5. Phone → Vaahana user lookup ───────────────────────────────────────────

/**
 * Looks up a Vaahana user by phone number (exact E.164 match).
 * Returns { uid, displayName } or null.
 *
 * Tries both the normalized phone and common variants (+1 vs. without country code).
 */
async function findUserByPhone(phone) {
  const snap = await db.collection("users")
    .where("phone", "==", phone)
    .limit(1)
    .get();

  if (!snap.empty) {
    const doc = snap.docs[0];
    return { uid: doc.id, displayName: doc.data().displayName || "Rider" };
  }

  // Also try whatsapp field
  const snap2 = await db.collection("users")
    .where("whatsapp", "==", phone)
    .limit(1)
    .get();

  if (!snap2.empty) {
    const doc = snap2.docs[0];
    return { uid: doc.id, displayName: doc.data().displayName || "Rider" };
  }

  return null;
}

/**
 * Returns a stable placeholder riderId for phone numbers with no Vaahana account.
 * Creates a minimal user doc in `whatsappRiders` so we can link them later
 * when they sign up.
 */
async function getOrCreatePlaceholderRider(phone, displayName) {
  const placeholderRef = db.collection("whatsappRiders").doc(
    // Stable ID: sha256 of the phone number so re-ingestion reuses the same doc
    crypto.createHash("sha256").update(phone).digest("hex").slice(0, 20)
  );

  const existing = await placeholderRef.get();
  if (existing.exists) return placeholderRef.id;

  await placeholderRef.set({
    phone,
    displayName: displayName || "WhatsApp Rider",
    source: "whatsapp",
    createdAt: FieldValue.serverTimestamp(),
  });

  return placeholderRef.id;
}

// ── 6. Deduplication ─────────────────────────────────────────────────────────

/**
 * Returns true if we've already ingested a ride from this phone with the same
 * origin within the last 24 hours.
 */
async function isDuplicate(phone, from, to, pickupDate) {
  // Query only on whatsappPhone (single-field, no composite index needed).
  // Filter source, recency, and route match in-process.
  const snap = await db.collection("rides")
    .where("whatsappPhone", "==", phone)
    .get();

  if (snap.empty) return false;

  const oneDayAgo = new Date(Date.now() - 24 * 60 * 60 * 1000);
  const fromNorm  = from.toLowerCase().trim();
  const toNorm    = to.toLowerCase().trim();
  const pickupDay = pickupDate.toDateString();

  for (const doc of snap.docs) {
    const data = doc.data();
    if (data.source !== "whatsapp") continue;

    // Only consider rides ingested in the last 24h
    const createdAt = data.createdAt?.toDate?.() ?? null;
    if (createdAt && createdAt < oneDayAgo) continue;

    const existingFrom   = (data.from || "").toLowerCase().trim();
    const existingTo     = (data.to   || "").toLowerCase().trim();
    const existingPickup = data.pickupDate?.toDate?.()?.toDateString?.() ?? "";

    if (existingFrom === fromNorm && existingTo === toNorm && existingPickup === pickupDay) return true;
  }

  return false;
}

// ── 7. HTTP endpoint ──────────────────────────────────────────────────────────

exports.ingestWhatsAppMessages = onRequest(
  {
    secrets: [WHATSAPP_API_KEY],
    cors: false,
    timeoutSeconds: 120,
    memory: "512MiB",
  },
  async (req, res) => {
    // ── Auth ──────────────────────────────────────────────────────────────────
    if (req.method !== "POST") {
      res.status(405).json({ error: "Method not allowed" });
      return;
    }

    const providedKey = (req.headers["x-api-key"] || req.body?.apiKey || "").trim();
    if (!providedKey || providedKey !== WHATSAPP_API_KEY.value().trim()) {
      res.status(401).json({ error: "Unauthorized" });
      return;
    }

    // ── Input normalisation ───────────────────────────────────────────────────
    // Accept either:
    //   { rawExport: "..." }           — full WhatsApp export text
    //   { messages: [{...}] }          — pre-parsed array from scraper
    //   { groupName: "...", rawExport / messages }

    const groupName = req.body?.groupName ?? "Unknown Group";
    let rawMessages = []; // [{phone, text, timestamp}]

    if (req.body?.rawExport) {
      rawMessages = parseWhatsAppExport(req.body.rawExport);
    } else if (Array.isArray(req.body?.messages)) {
      rawMessages = req.body.messages.map((m) => ({
        phone:     normalizePhone(String(m.phone ?? "")),
        text:      String(m.text ?? "").trim(),
        timestamp: m.timestamp ? new Date(m.timestamp) : new Date(),
      })).filter((m) => m.phone);
    } else {
      res.status(400).json({ error: "Provide rawExport (string) or messages (array)" });
      return;
    }

    // ── Process each message ──────────────────────────────────────────────────

    const results = {
      total:     rawMessages.length,
      ingested:  0,
      skipped:   0,
      duplicate: 0,
      errors:    0,
      rides:     [],   // IDs of created ride docs
    };

    for (const msg of rawMessages) {
      try {
        // 1. Extract ride data
        const rideData = extractRideData(msg.text, msg.timestamp);
        if (!rideData) {
          console.log(`[ingest] SKIP not_ride_request | ${msg.phone} | "${msg.text.slice(0,80)}"`);
          results.skipped++; continue;
        }

        // 2. Skip if pickup date is in the past (more than 1 hour ago)
        const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000);
        if (rideData.pickupDate < oneHourAgo) {
          console.log(`[ingest] SKIP past_pickup | ${msg.phone} | pickup=${rideData.pickupDate.toISOString()} | "${msg.text.slice(0,80)}"`);
          results.skipped++; continue;
        }

        // 3. Dedup
        const dup = await isDuplicate(msg.phone, rideData.from, rideData.to, rideData.pickupDate);
        if (dup) { results.duplicate++; continue; }

        // 4. Resolve rider identity
        const vaahanaUser = await findUserByPhone(msg.phone);
        let riderId, riderName;

        if (vaahanaUser) {
          riderId   = vaahanaUser.uid;
          riderName = vaahanaUser.displayName;
        } else {
          riderId   = await getOrCreatePlaceholderRider(msg.phone, null);
          riderName = "WhatsApp Rider";
        }

        // 5. Build ride document
        const rideId = crypto.randomUUID();
        const rideDoc = {
          id:                  rideId,
          riderId,
          status:              "posted",
          source:              "whatsapp",
          groupName,
          whatsappPhone:       msg.phone,
          isLinkedUser:        !!vaahanaUser,

          // Contact
          name:                riderName,
          phone:               msg.phone,
          phoneCountryCode:    msg.phone.startsWith("+91") ? "+91" : "+1",
          whatsappCountryCode: msg.phone.startsWith("+91") ? "+91" : "+1",

          // Route
          from:                rideData.from,
          to:                  rideData.to,
          miles:               0,            // unknown until driver maps it
          pickupLat:           null,
          pickupLng:           null,

          // Timing
          coins:               0,            // driver makes an offer via bid
          hotDuration:         rideData.hotDuration,
          pickupDate:          rideData.pickupDate,

          // Coin state
          coinStatus:          "none",
          coinsLocked:         0,
          coinsTransferred:    0,

          // Bid marketplace
          bidCount:            0,
          selectedBidId:       null,
          finalCoins:          null,
          lowestBidCoins:      null,
          latestBidAt:         null,

          // Driver (empty until accepted)
          driverId:            null,
          driverName:          null,
          driverPhone:         null,
          driverWhatsapp:      null,

          // Metadata
          rawText:             msg.text,
          rawTimeHint:         rideData.rawTimeHint,
          createdAt:           FieldValue.serverTimestamp(),
          updatedAt:           FieldValue.serverTimestamp(),
        };

        await db.collection("rides").doc(rideId).set(rideDoc);

        // 6. Log ingestion
        await db.collection("whatsappIngestionLogs").add({
          rideId,
          phone:     msg.phone,
          rawText:   msg.text,
          timestamp: msg.timestamp,
          groupName,
          parsedFrom:    rideData.from,
          parsedTo:      rideData.to,
          parsedPickup:  rideData.pickupDate,
          linkedUser:    !!vaahanaUser,
          createdAt:     FieldValue.serverTimestamp(),
        });

        results.ingested++;
        results.rides.push(rideId);
      } catch (err) {
        console.error("[ingestWhatsAppMessages] Error processing message:", err.message, msg);
        results.errors++;
      }
    }

    console.log(`[ingestWhatsAppMessages] group=${groupName} total=${results.total} ingested=${results.ingested} skipped=${results.skipped} dup=${results.duplicate} errors=${results.errors}`);
    res.status(200).json(results);
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
