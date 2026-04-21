// Small shared helpers.

export function el(tag, attrs = {}, ...children) {
  const node = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs || {})) {
    if (k === "class") node.className = v;
    else if (k === "html") node.innerHTML = v;
    else if (k.startsWith("on") && typeof v === "function") node.addEventListener(k.slice(2).toLowerCase(), v);
    else if (v === false || v == null) continue;
    else if (v === true) node.setAttribute(k, "");
    else node.setAttribute(k, v);
  }
  for (const c of children.flat()) {
    if (c == null || c === false) continue;
    node.append(c.nodeType ? c : document.createTextNode(String(c)));
  }
  return node;
}

export function uuidv4() {
  if (crypto.randomUUID) return crypto.randomUUID();
  return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    return (c === "x" ? r : (r & 0x3) | 0x8).toString(16);
  });
}

export function timeAgo(dateLike) {
  if (!dateLike) return "";
  const d = dateLike instanceof Date ? dateLike : new Date(dateLike);
  const secs = Math.floor((Date.now() - d.getTime()) / 1000);
  if (secs < 60) return "just now";
  if (secs < 3600) return `${Math.floor(secs / 60)}m ago`;
  if (secs < 86400) return `${Math.floor(secs / 3600)}h ago`;
  return `${Math.floor(secs / 86400)}d ago`;
}

export function fmtPickup(dateLike) {
  if (!dateLike) return "";
  const d = dateLike instanceof Date ? dateLike : new Date(dateLike);
  return d.toLocaleString(undefined, {
    month: "short", day: "numeric",
    hour: "numeric", minute: "2-digit",
  });
}

export function debounce(fn, ms = 300) {
  let t;
  return (...args) => {
    clearTimeout(t);
    t = setTimeout(() => fn(...args), ms);
  };
}

// Firestore Timestamp or Date -> Date
export function asDate(v) {
  if (!v) return null;
  if (v instanceof Date) return v;
  if (typeof v?.toDate === "function") return v.toDate();
  if (typeof v === "string" || typeof v === "number") return new Date(v);
  if (typeof v === "object" && "seconds" in v) return new Date(v.seconds * 1000);
  return null;
}

// Normalize a phone into a full international-format string.
// Handles both "4155551234" + cc "+1" (iOS-style) AND "+14155551234" already
// containing the country code (WhatsApp-ingested rides).
export function fullPhone(countryCode, phone) {
  const raw = String(phone || "").trim();
  if (!raw) return "";
  if (raw.startsWith("+")) return raw.replace(/[^\d+]/g, "");
  return `${countryCode || ""}${raw}`.replace(/[^\d+]/g, "");
}

export function whatsappLink(countryCode, phone, message) {
  const num = fullPhone(countryCode, phone).replace(/[^\d]/g, "");
  const text = message ? `?text=${encodeURIComponent(message)}` : "";
  return `https://wa.me/${num}${text}`;
}

export function telLink(countryCode, phone) {
  return `tel:${fullPhone(countryCode, phone)}`;
}

export function escapeHtml(s) {
  return String(s || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

export function toast(message, { type = "info", ms = 2600 } = {}) {
  let host = document.getElementById("__toast");
  if (!host) {
    host = document.createElement("div");
    host.id = "__toast";
    host.style.cssText = "position:fixed;left:50%;bottom:96px;transform:translateX(-50%);z-index:9999;display:flex;flex-direction:column;gap:8px;pointer-events:none;";
    document.body.appendChild(host);
  }
  const t = document.createElement("div");
  t.textContent = message;
  const colors = {
    info:    "background:#ffffff;color:#000000;",
    error:   "background:#ffffff;color:#000000;border:1px solid #000;",
    success: "background:#ffffff;color:#000000;",
  };
  t.style.cssText = `${colors[type] || colors.info};padding:11px 16px;border-radius:10px;font-size:13px;font-weight:600;letter-spacing:-0.01em;box-shadow:0 8px 30px rgba(0,0,0,0.5);opacity:0;transform:translateY(8px);transition:all .2s;`;
  host.appendChild(t);
  requestAnimationFrame(() => { t.style.opacity = "1"; t.style.transform = "translateY(0)"; });
  setTimeout(() => {
    t.style.opacity = "0";
    setTimeout(() => t.remove(), 200);
  }, ms);
}

export function prefillWhatsAppMessage(rideFromApp, driverName) {
  const name = driverName ? ` This is ${driverName}` : "";
  return `Hi! I saw your ride request on Vaahana from ${rideFromApp.from} to ${rideFromApp.to}.${name}. I can help — are you still looking for a driver?`;
}
