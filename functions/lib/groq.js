"use strict";

/**
 * Groq LLM parser for WhatsApp ride messages. Primary parser; regex is
 * fallback. Handles formal English, casual English, and transliterated
 * Indian-language phrasings (Hindi/Telugu/Tamil/Marathi in Latin script).
 *
 * Output (null on failure):
 *   { from, to, pickupLocalDateTime, hotDuration, rawTimeHint, intent,
 *     _llm: { confidence, model, reasoning } }
 */

const GROQ_URL  = "https://api.groq.com/openai/v1/chat/completions";
const MODEL     = "llama-3.1-8b-instant";
const TIMEOUT_MS = 8_000;
const MIN_CONFIDENCE = 0.55;

// Compact prompt — every token costs free-tier TPM budget.
const SYSTEM_PROMPT = `Extract ride details from WhatsApp messages. Messages may be English, casual English, or transliterated Indian languages (Hindi/Telugu/Tamil/Marathi/Punjabi in Latin script).

Hinglish/Tenglish vocabulary:
- tomorrow: "kal" (Hindi), "repu" (Telugu), "naalai" (Tamil), "udya" (Marathi)
- today:    "aaj" (Hindi), "eroju" (Telugu), "indru" (Tamil)
- need:     "kavali"/"kaavali" (Telugu), "chahiye"/"chaiye" (Hindi), "hona"/"ho" (Hindi informal), "venum" (Tamil)
- I:        "naaku"/"naku" (Telugu), "mujhe"/"mereko" (Hindi)
- from:     "nunchi" (Telugu), "se" (Hindi), "irundu" (Tamil)
- to:       "ki"/"ku" (Telugu/Hindi), "varai" (Tamil)
- going:    "ja raha hai"/"ja raha hu" (Hindi), "veltunna"/"veltunnanu" (Telugu)
- morning:  "subah", "morning"
- evening:  "shaam", "saayantram"
- night:    "raat"

Intent:
- rider_request: sender needs a ride
- driver_offer:  sender is driving, offering seats

Both need clear pickup AND drop-off. If either is vague, isRideRequest=false.

Return ONLY this JSON (no prose, no fences):
{"isRideRequest":bool,"intent":"rider_request"|"driver_offer"|null,"from":str|null,"to":str|null,"pickupLocalDateTime":str|null,"pickupHint":str,"hotDuration":30|60|300|1440,"confidence":0-1,"reasoning":str}

pickupLocalDateTime: naive local wall-clock at pickup, format "YYYY-MM-DDTHH:mm:ss" (NO timezone, NO "Z"). Use CURRENT_ISO as the reference date.
- IMPORTANT: If the message contains ANY time signal (explicit time, "tomorrow", "kal", "repu", "morning", "evening", "6pm", "in 20 min"), you MUST output pickupLocalDateTime. Do NOT return null when a signal exists — even if you have to make a reasonable inference.
- Examples:
    CURRENT_ISO 2026-04-22T02:00:00Z + "repu 6pm ki"   → "2026-04-22T18:00:00" (tomorrow ET was still 22nd local)
    CURRENT_ISO 2026-04-22T14:00:00Z + "kal subah 7"   → "2026-04-23T07:00:00"
    CURRENT_ISO 2026-04-22T14:00:00Z + "tomorrow 5pm"  → "2026-04-23T17:00:00"
    "in 20 min" → add 20 min to CURRENT_ISO and output wall-clock
- Only return null if the message has NO time signal at all.
- morning=09:00, afternoon=14:00, evening=18:00, night=21:00.

Confidence <0.55 → set isRideRequest=false.`;

async function callGroqWithRetry(apiKey, body, retries = 1) {
  for (let attempt = 0; attempt <= retries; attempt++) {
    const ctl = new AbortController();
    const timer = setTimeout(() => ctl.abort(), TIMEOUT_MS);
    let res;
    try {
      res = await fetch(GROQ_URL, {
        method: "POST",
        headers: { "Authorization": `Bearer ${apiKey}`, "Content-Type": "application/json" },
        body: JSON.stringify(body),
        signal: ctl.signal,
      });
    } catch (err) {
      clearTimeout(timer);
      console.warn(`[groq] network/abort (attempt ${attempt}): ${err.message}`);
      if (attempt < retries) { await sleep(400); continue; }
      return null;
    }
    clearTimeout(timer);

    if (res.status === 429 && attempt < retries) {
      // Respect Retry-After if present; cap at 4s to stay within function timeout.
      const retryAfter = Math.min(parseFloat(res.headers.get("retry-after") || "2") * 1000, 4_000);
      console.warn(`[groq] 429 — waiting ${retryAfter}ms before retry ${attempt + 1}`);
      await sleep(retryAfter);
      continue;
    }
    if (!res.ok) {
      const txt = await res.text().catch(() => "");
      console.warn(`[groq] HTTP ${res.status}: ${txt.slice(0, 200)}`);
      return null;
    }
    return res.json().catch((err) => { console.warn(`[groq] bad JSON: ${err.message}`); return null; });
  }
  return null;
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function extractRideDataLLM(text, messageTs, apiKey) {
  if (!text || typeof text !== "string" || text.trim().length < 3) return null;
  if (!apiKey) throw new Error("GROQ_API_KEY missing");

  const currentIso = (messageTs instanceof Date ? messageTs : new Date()).toISOString();
  const userPrompt = `CURRENT_ISO: ${currentIso}\n\nMESSAGE:\n${text.trim()}`;

  const payload = await callGroqWithRetry(apiKey, {
    model: MODEL,
    temperature: 0,
    max_tokens: 250,
    response_format: { type: "json_object" },
    messages: [
      { role: "system", content: SYSTEM_PROMPT },
      { role: "user",   content: userPrompt },
    ],
  });
  if (!payload) return null;

  const content = payload?.choices?.[0]?.message?.content;
  if (!content) { console.warn("[groq] no content"); return null; }

  let parsed;
  try { parsed = JSON.parse(content); }
  catch { console.warn(`[groq] model output not JSON: ${String(content).slice(0, 200)}`); return null; }

  if (!parsed.isRideRequest) return null;

  const intent = parsed.intent === "driver_offer" ? "driver_offer" : "rider_request";

  const confidence = Number(parsed.confidence);
  if (!Number.isFinite(confidence) || confidence < MIN_CONFIDENCE) {
    console.log(`[groq] low confidence (${confidence}) — skipping`);
    return null;
  }

  const from = typeof parsed.from === "string" ? parsed.from.trim() : "";
  const to   = typeof parsed.to   === "string" ? parsed.to.trim()   : "";
  if (!from || !to) return null;

  const raw = typeof parsed.pickupLocalDateTime === "string" ? parsed.pickupLocalDateTime.trim() : "";
  const pickupLocalDateTime = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2})?$/.test(raw) ? raw : null;

  const ALLOWED_HOT = [30, 60, 300, 1440];
  let hotDuration = Number(parsed.hotDuration);
  if (!ALLOWED_HOT.includes(hotDuration)) hotDuration = 1440;

  // Always return a usable pickupDate so the ingest loop has something to
  // persist even if pickupLocalDateTime is null. Caller may overwrite this
  // after geocoding + timezone lookup using the naive pickupLocalDateTime.
  const fallbackMs = (messageTs instanceof Date ? messageTs : new Date()).getTime() + 30 * 60 * 1000;
  const pickupDate = new Date(fallbackMs);

  return {
    from, to,
    pickupLocalDateTime,
    pickupDate, // fallback; overwritten by caller when pickupLocalDateTime + tz resolve
    hotDuration,
    intent,
    rawTimeHint: typeof parsed.pickupHint === "string" ? parsed.pickupHint : "",
    _llm: {
      confidence,
      model: MODEL,
      reasoning: typeof parsed.reasoning === "string" ? parsed.reasoning.slice(0, 280) : "",
    },
  };
}

module.exports = { extractRideDataLLM, MODEL, MIN_CONFIDENCE };
