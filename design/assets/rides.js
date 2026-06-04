// Firestore ride + user service for Vaahana web.
// Matches the Swift Ride model in ContentView.swift:84 and state transitions
// in RideService.swift.

import {
  db,
  doc, getDoc, setDoc, updateDoc,
  collection, query, where, orderBy, limit, onSnapshot,
  runTransaction, getDocs, Timestamp,
} from "./firebase.js";
import { uuidv4, asDate } from "./util.js";

// ----- Users -----

export async function getUserProfile(uid) {
  const snap = await getDoc(doc(db, "users", uid));
  return snap.exists() ? { uid, ...snap.data() } : null;
}

export async function saveUserProfile(uid, patch) {
  const ref = doc(db, "users", uid);
  await setDoc(ref, { ...patch, updatedAt: Timestamp.now() }, { merge: true });
}

// ----- Rides -----

export function newRide({
  riderId, name, phone, phoneCountryCode, whatsappPhone, whatsappCountryCode,
  from, to, miles, pickupLat, pickupLng, hotDuration, pickupDate, notes,
}) {
  const now = Timestamp.now();
  return {
    id: uuidv4(),
    riderId,
    status: "posted",
    createdAt: now,
    updatedAt: null,
    name, phone, phoneCountryCode,
    whatsappPhone, whatsappCountryCode,
    from, to, miles: Number(miles) || 0,
    pickupLat: pickupLat ?? null, pickupLng: pickupLng ?? null,
    source: "web",
    hotDuration: Number(hotDuration) || 30,
    pickupDate: Timestamp.fromDate(pickupDate instanceof Date ? pickupDate : new Date(pickupDate)),
    driverId: null, driverName: null, driverPhone: null, driverWhatsapp: null,
    acceptedAt: null, driverEnrouteAt: null, arrivedAt: null,
    startedAt: null, completedAt: null, cancelledAt: null,
    cancelledBy: null, cancellationReasonCode: null,
    notes: notes || null,
    bidCount: 0, selectedBidId: null, latestBidAt: null,
  };
}

export async function postRide(ride) {
  await setDoc(doc(db, "rides", ride.id), ride);
  return ride.id;
}

export async function updateRide(rideId, patch) {
  await updateDoc(doc(db, "rides", rideId), { ...patch, updatedAt: Timestamp.now() });
}

// Driver claims a ride (web flow — no bid needed).
// Only succeeds if still `posted`. Mirrors RideService.acceptRide.
export async function driverAcceptRide(rideId, driverProfile) {
  await runTransaction(db, async (tx) => {
    const ref = doc(db, "rides", rideId);
    const snap = await tx.get(ref);
    if (!snap.exists()) throw new Error("Ride no longer exists.");
    const r = snap.data();
    if (r.status !== "posted") throw new Error("Ride is no longer available.");
    tx.update(ref, {
      status: "accepted",
      driverId: driverProfile.uid,
      driverName: driverProfile.displayName || "",
      driverPhone: `${driverProfile.phoneCountryCode || ""}${driverProfile.phone || ""}`,
      driverWhatsapp: `${driverProfile.whatsappCountryCode || driverProfile.phoneCountryCode || ""}${driverProfile.whatsappPhone || driverProfile.phone || ""}`,
      acceptedAt: Timestamp.now(),
      updatedAt: Timestamp.now(),
    });
  });
}

export async function setRideStatus(rideId, status, extra = {}) {
  const ts = Timestamp.now();
  const fieldForStatus = {
    driverEnroute: "driverEnrouteAt",
    driverArrived: "arrivedAt",
    rideStarted:   "startedAt",
    completed:     "completedAt",
    cancelled:     "cancelledAt",
  }[status];
  const patch = { status, updatedAt: ts, ...extra };
  if (fieldForStatus) patch[fieldForStatus] = ts;
  await updateDoc(doc(db, "rides", rideId), patch);
}

export async function cancelRide(rideId, byUid) {
  await setRideStatus(rideId, "cancelled", { cancelledBy: byUid });
}

// ----- Listeners -----

// Live feed of posted rides (driver view). Rules allow public read.
export function listenPostedRides(cb) {
  const q = query(
    collection(db, "rides"),
    where("status", "==", "posted"),
    orderBy("createdAt", "desc"),
    limit(100),
  );
  return onSnapshot(q, (snap) => {
    const rides = snap.docs
      .map((d) => normalize(d.id, d.data()))
      .filter((r) => r.isHot);
    cb(rides);
  });
}

// Rider's active request (if any).
export function listenMyActiveRide(uid, cb) {
  const q = query(
    collection(db, "rides"),
    where("riderId", "==", uid),
    where("status", "in", ["posted", "accepted", "driverEnroute", "driverArrived", "rideStarted"]),
  );
  return onSnapshot(q, (snap) => {
    const rides = snap.docs.map((d) => normalize(d.id, d.data()));
    rides.sort((a, b) => (b.createdAtMs || 0) - (a.createdAtMs || 0));
    cb(rides[0] || null);
  });
}

// Driver's active ride (one they've claimed).
export function listenMyActiveDriverRide(uid, cb) {
  const q = query(
    collection(db, "rides"),
    where("driverId", "==", uid),
    where("status", "in", ["accepted", "driverEnroute", "driverArrived", "rideStarted"]),
  );
  return onSnapshot(q, (snap) => {
    const rides = snap.docs.map((d) => normalize(d.id, d.data()));
    rides.sort((a, b) => (b.createdAtMs || 0) - (a.createdAtMs || 0));
    cb(rides[0] || null);
  });
}

// Unified history — rides where the user was rider OR driver.
export async function loadRideHistory(uid) {
  const done = ["completed", "cancelled", "expired"];
  const [asRider, asDriver] = await Promise.all([
    getDocs(query(
      collection(db, "rides"),
      where("riderId", "==", uid),
      where("status", "in", done),
      orderBy("updatedAt", "desc"),
      limit(50),
    )),
    getDocs(query(
      collection(db, "rides"),
      where("driverId", "==", uid),
      where("status", "in", done),
      orderBy("updatedAt", "desc"),
      limit(50),
    )),
  ]);
  const rides = [...asRider.docs, ...asDriver.docs].map((d) => normalize(d.id, d.data()));
  // De-dup by id, sort newest first.
  const byId = new Map(rides.map((r) => [r.id, r]));
  return [...byId.values()].sort((a, b) => {
    const at = (a.updatedAt || a.createdAt || new Date(0)).getTime();
    const bt = (b.updatedAt || b.createdAt || new Date(0)).getTime();
    return bt - at;
  });
}

function normalize(id, r) {
  const createdAt = asDate(r.createdAt);
  const pickupDate = asDate(r.pickupDate);
  const hotUntil = createdAt ? new Date(createdAt.getTime() + (r.hotDuration || 30) * 60 * 1000) : null;
  return {
    ...r,
    id,
    createdAt,
    createdAtMs: createdAt ? createdAt.getTime() : 0,
    pickupDate,
    updatedAt: asDate(r.updatedAt),
    acceptedAt: asDate(r.acceptedAt),
    driverEnrouteAt: asDate(r.driverEnrouteAt),
    arrivedAt: asDate(r.arrivedAt),
    startedAt: asDate(r.startedAt),
    completedAt: asDate(r.completedAt),
    cancelledAt: asDate(r.cancelledAt),
    hotUntil,
    isHot: hotUntil ? hotUntil.getTime() > Date.now() : false,
  };
}

export { normalize as normalizeRide };
