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
const SYSTEM_PROMPT = `Extract ride details from WhatsApp messages. Messages may be in English, casual English, or transliterated Hindi/Telugu/Tamil/Marathi/Punjabi (written in Latin script — "kal" = tomorrow, "subah" = morning, "repu" = tomorrow (Telugu), "naalai" = tomorrow (Tamil), "kavali"/"chahiye" = need, "ja raha hai" = going).

Intent:
- rider_request: sender needs a ride
- driver_offer:  sender is driving, offering seats

Both need a clear pickup + drop-off; if either is vague, isRideRequest=false.

Return ONLY this JSON (no prose, no fences):
{"isRideRequest":bool,"intent":"rider_request"|"driver_offer"|null,"from":str|null,"to":str|null,"pickupLocalDateTime":str|null,"pickupHint":str,"hotDuration":30|60|300|1440,"confidence":0-1,"reasoning":str}

pickupLocalDateTime: naive local wall-clock at pickup location, format "YYYY-MM-DDTHH:mm:ss" (NO timezone/Z). Use CURRENT_ISO as reference for relative times. morning=09:00, afternoon=14:00, evening=18:00, night=21:00. If no time mentioned, null.

Confidence <0.55 → isRideRequest=false.`;

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

  return {
    from, to,
    pickupLocalDateTime,
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
