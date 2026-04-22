// Free geocoding + routing helpers.
// Uses OpenStreetMap Nominatim (search) and OSRM public demo (route distance).
// Nominatim ToS: identify via User-Agent and keep rate <=1/s per IP.

const NOMINATIM = "https://nominatim.openstreetmap.org/search";
const OSRM      = "https://router.project-osrm.org/route/v1/driving";

// Tiny in-memory cache to avoid hammering Nominatim during type-ahead.
const cache = new Map();

export async function searchPlaces(q, { limit = 6 } = {}) {
  const query = q.trim();
  if (query.length < 3) return [];
  if (cache.has(query)) return cache.get(query);

  const url = `${NOMINATIM}?format=jsonv2&addressdetails=1&limit=${limit}&q=${encodeURIComponent(query)}`;
  const res = await fetch(url, {
    headers: { "Accept-Language": navigator.language || "en" },
  });
  if (!res.ok) return [];
  const data = await res.json();
  const out = data.map((d) => ({
    displayName: d.display_name,
    short: shortenName(d),
    lat: parseFloat(d.lat),
    lng: parseFloat(d.lon),
    type: d.type,
  }));
  cache.set(query, out);
  return out;
}

function shortenName(d) {
  const a = d.address || {};
  const head = d.name || a.road || a.neighbourhood || a.suburb || a.city || a.town || a.village || "";
  const city = a.city || a.town || a.village || a.hamlet || "";
  const region = a.state_code || a.state || "";
  const parts = [head, city, region].filter(Boolean);
  // Dedup consecutive (e.g. head == city)
  const deduped = parts.filter((x, i) => x !== parts[i - 1]);
  if (deduped.length) return deduped.join(", ");
  return d.display_name.split(",").slice(0, 3).join(",");
}

export async function routeDistanceMiles(a, b) {
  if (!a || !b) return null;
  const url = `${OSRM}/${a.lng},${a.lat};${b.lng},${b.lat}?overview=false`;
  try {
    const res = await fetch(url);
    if (!res.ok) return null;
    const data = await res.json();
    const meters = data?.routes?.[0]?.distance;
    if (typeof meters !== "number") return null;
    return meters / 1609.344;
  } catch {
    return null;
  }
}

// Straight-line haversine (for "near me" sort fallback).
export function haversineMiles(a, b) {
  const R = 3958.8;
  const toRad = (d) => (d * Math.PI) / 180;
  const dLat = toRad(b.lat - a.lat);
  const dLng = toRad(b.lng - a.lng);
  const s =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(a.lat)) * Math.cos(toRad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(s));
}
