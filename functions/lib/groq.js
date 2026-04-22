"use strict";

/**
 * Groq LLM parser for WhatsApp ride-request messages.
 *
 * Replaces (with regex fallback) the handwritten regex in
 * functions/index.js so that informal phrasings like
 *   "anyone going to jfk tmrw morn?"
 *   "need a lift to logan 5ish"
 *   "ride needed for my parents monday 3pm"
 * get correctly classified and extracted.
 *
 * Returns the same shape as the regex `extractRideData()` on success:
 *   { from, to, pickupDate: Date, hotDuration: number, rawTimeHint: string,
 *     _llm: { confidence, model, reasoning } }
 * Returns null when the message is not a ride request, the LLM call fails,
 * or the extracted confidence is below MIN_CONFIDENCE.
 */

const GROQ_URL  = "https://api.groq.com/openai/v1/chat/completions";
const MODEL     = "llama-3.1-8b-instant"; // cheapest/fastest Groq Llama
const TIMEOUT_MS = 8_000;
const MIN_CONFIDENCE = 0.55;              // below this → treat as null / review

const SYSTEM_PROMPT = `You extract ride-request details from informal WhatsApp chat messages.

Classify whether the message is a RIDER looking for a ride. Ignore driver offers ("I can drive"), accommodation, food, unrelated chit-chat, greetings.

A rider request must include intent to travel from somewhere to somewhere. A pickup location and drop-off location are both required — if either is clearly missing, return isRideRequest=false.

Return STRICT JSON with these exact keys:
{
  "isRideRequest": boolean,
  "from":          string | null,   // pickup location in Title Case
  "to":            string | null,   // drop-off location in Title Case
  "pickupIso":     string | null,   // ISO-8601 local pickup datetime or null
  "pickupHint":    string,          // the original time phrase from the message ("tomorrow 5pm", "in 20 min")
  "hotDuration":   number,          // how many minutes the request should stay visible: 30 / 60 / 300 / 1440. Default 1440.
  "confidence":    number,          // 0.0 — 1.0, how sure you are this is a ride request with clear from/to
  "reasoning":     string           // one short sentence
}

Rules for pickupIso:
- You will be told the current time (CURRENT_ISO). Use it to resolve relative phrases like "tomorrow", "tonight", "in 30 min", "5ish".
- "morning" → 9:00, "afternoon" → 14:00, "evening" → 18:00, "night" → 21:00 unless otherwise specified.
- If the message says no time at all, return pickupIso=null (the caller will default to "now").
- Never invent a time. If ambiguous, set pickupIso=null.

Rules for confidence:
- High (0.85–1.0): both from + to are explicit, intent is clearly a rider needing a ride.
- Medium (0.55–0.85): from + to are clear but phrasing is casual ("anyone going to X from Y?").
- Low (<0.55): from or to is vague ("somewhere near my place"), or it's unclear whether rider or driver. In this case, set isRideRequest=false.

Do NOT output anything other than the JSON object. No prose, no code fences.`;

/**
 * @param {string} text           raw WhatsApp message
 * @param {Date}   messageTs      timestamp of when the message was sent
 * @param {string} apiKey         Groq API key
 * @returns {Promise<object|null>}
 */
async function extractRideDataLLM(text, messageTs, apiKey) {
  if (!text || typeof text !== "string" || text.trim().length < 3) return null;
  if (!apiKey) throw new Error("GROQ_API_KEY missing");

  const currentIso = (messageTs instanceof Date ? messageTs : new Date()).toISOString();
  const userPrompt = `CURRENT_ISO: ${currentIso}\n\nMESSAGE:\n"""\n${text.trim()}\n"""`;

  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), TIMEOUT_MS);

  let res;
  try {
    res = await fetch(GROQ_URL, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: MODEL,
        temperature: 0,
        max_tokens: 400,
        response_format: { type: "json_object" },
        messages: [
          { role: "system", content: SYSTEM_PROMPT },
          { role: "user",   content: userPrompt },
        ],
      }),
      signal: ctl.signal,
    });
  } catch (err) {
    clearTimeout(timer);
    console.warn(`[groq] network/abort: ${err.message}`);
    return null;
  }
  clearTimeout(timer);

  if (!res.ok) {
    const body = await res.text().catch(() => "");
    console.warn(`[groq] HTTP ${res.status}: ${body.slice(0, 200)}`);
    return null;
  }

  let payload;
  try {
    payload = await res.json();
  } catch (err) {
    console.warn(`[groq] bad JSON envelope: ${err.message}`);
    return null;
  }

  const content = payload?.choices?.[0]?.message?.content;
  if (!content) {
    console.warn("[groq] no choices.message.content");
    return null;
  }

  let parsed;
  try {
    parsed = JSON.parse(content);
  } catch {
    console.warn(`[groq] model output not JSON: ${String(content).slice(0, 200)}`);
    return null;
  }

  // ── Validate & normalize ──────────────────────────────────────────────────
  if (!parsed.isRideRequest) return null;

  const confidence = Number(parsed.confidence);
  if (!Number.isFinite(confidence) || confidence < MIN_CONFIDENCE) {
    console.log(`[groq] low confidence (${confidence}) — skipping`);
    return null;
  }

  const from = typeof parsed.from === "string" ? parsed.from.trim() : "";
  const to   = typeof parsed.to   === "string" ? parsed.to.trim()   : "";
  if (!from || !to) return null;

  // Resolve pickup date
  let pickupDate = null;
  if (typeof parsed.pickupIso === "string" && parsed.pickupIso) {
    const d = new Date(parsed.pickupIso);
    if (!isNaN(d.getTime())) pickupDate = d;
  }
  if (!pickupDate) {
    // Default: 30 min from message timestamp — gives the rider a buffer.
    pickupDate = new Date((messageTs instanceof Date ? messageTs : new Date()).getTime() + 30 * 60 * 1000);
  }

  // Hot duration — clamp to allowed buckets.
  const ALLOWED = [30, 60, 300, 1440];
  let hotDuration = Number(parsed.hotDuration);
  if (!ALLOWED.includes(hotDuration)) hotDuration = 1440;

  return {
    from,
    to,
    pickupDate,
    hotDuration,
    rawTimeHint: typeof parsed.pickupHint === "string" ? parsed.pickupHint : "",
    _llm: {
      confidence,
      model: MODEL,
      reasoning: typeof parsed.reasoning === "string" ? parsed.reasoning.slice(0, 280) : "",
    },
  };
}

module.exports = { extractRideDataLLM, MODEL, MIN_CONFIDENCE };
