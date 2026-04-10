import makeWASocket, {
  useMultiFileAuthState,
  DisconnectReason,
  isJidGroup,
  fetchLatestBaileysVersion,
} from '@whiskeysockets/baileys'
import { Boom } from '@hapi/boom'
import axios from 'axios'
import pino from 'pino'
import qrcode from 'qrcode-terminal'
import 'dotenv/config'


// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

const API_KEY = process.env.API_KEY
const API_ENDPOINT =
  'https://us-central1-vaahana-fb9b8.cloudfunctions.net/ingestWhatsAppMessages'

// Comma-separated group names in .env
//   TARGET_GROUPS=NH Rides,Rides Test 1,Rides Test 2
const TARGET_GROUPS = (process.env.TARGET_GROUPS || '')
  .split(',')
  .map((s) => s.trim())
  .filter(Boolean)

if (!API_KEY || API_KEY === 'your_api_key_here') {
  console.error('ERROR: Set API_KEY in .env before running.')
  process.exit(1)
}

if (TARGET_GROUPS.length === 0) {
  console.error('ERROR: Set TARGET_GROUPS in .env (comma-separated group names).')
  process.exit(1)
}

console.log(`[Config] Watching ${TARGET_GROUPS.length} group(s):`)
TARGET_GROUPS.forEach((g) => console.log(`  • "${g}"`))

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

// Map: groupJid -> groupName  (only whitelisted groups)
const allowedJids = new Map()
// Groups already confirmed as NOT in the whitelist — skip without fetching
const deniedJids = new Set()
// Map: LID (no domain) -> real phone number e.g. "110866309587147" -> "+15551234567"
const lidToPhone = new Map()

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function getTimestamp(messageTimestamp) {
  return new Date(Number(messageTimestamp) * 1000).toISOString()
}

function extractPhone(senderJid) {
  const [local, domain] = senderJid.split('@')
  const id = local.split(':')[0]

  // LID is a privacy alias — resolve to real phone if we have it
  if (domain === 'lid') {
    return lidToPhone.get(id) ?? null
  }

  return '+' + id
}

function extractText(message) {
  if (!message) return null
  if (message.conversation) return message.conversation
  if (message.extendedTextMessage?.text) return message.extendedTextMessage.text
  return null // images, video, stickers, polls etc. → ignored
}

async function sendToAPI(groupName, phone, name, text, timestamp) {
  const payload = {
    groupName,
    messages: [{ phone, name, text, timestamp }],
  }

  try {
    const res = await axios.post(API_ENDPOINT, payload, {
      headers: { 'x-api-key': API_KEY, 'Content-Type': 'application/json' },
      timeout: 10_000,
    })
    const r = res.data
    console.log(`[${groupName}] ${name || phone} | ingested:${r.ingested} skipped:${r.skipped} dup:${r.duplicate} | "${text.slice(0, 50)}"`)

  } catch (err) {
    const detail = err.response
      ? `HTTP ${err.response.status}: ${JSON.stringify(err.response.data)}`
      : err.message
    console.error(`[API] Error — ${detail}`)
  }
}

// ---------------------------------------------------------------------------
// Group discovery
// ---------------------------------------------------------------------------

async function discoverGroups(sock) {
  try {
    console.log('[Bot] Fetching joined groups…')
    const groups = await sock.groupFetchAllParticipating()

    for (const [jid, meta] of Object.entries(groups)) {
      if (TARGET_GROUPS.includes(meta.subject)) {
        allowedJids.set(jid, meta.subject)
        console.log(`[Bot] ✓ Found "${meta.subject}"`)

        // Build LID -> phone map from participants
        for (const p of meta.participants ?? []) {
          if (p.lid && p.jid) {
            const lid = p.lid.split('@')[0].split(':')[0]
            const phone = '+' + p.jid.split('@')[0].split(':')[0]
            lidToPhone.set(lid, phone)
          }
        }
      }
    }

    const missing = TARGET_GROUPS.filter(
      (name) => ![...allowedJids.values()].includes(name)
    )
    if (missing.length > 0) {
      console.warn(`[Bot] ⚠ Not found (not a member?): ${missing.map((n) => `"${n}"`).join(', ')}`)
    }

    console.log(`[Bot] Listening to ${allowedJids.size}/${TARGET_GROUPS.length} groups.`)
  } catch (err) {
    console.error('[Bot] Failed to fetch groups:', err.message)
  }
}

// Resolve a JID we haven't seen before
async function resolveJid(sock, jid) {
  if (allowedJids.has(jid) || deniedJids.has(jid)) return

  try {
    const meta = await sock.groupMetadata(jid)
    if (TARGET_GROUPS.includes(meta.subject)) {
      allowedJids.set(jid, meta.subject)
      console.log(`[Bot] ✓ Resolved on message: "${meta.subject}"`)
    } else {
      deniedJids.add(jid)
    }
  } catch {
    deniedJids.add(jid)
  }
}

// ---------------------------------------------------------------------------
// Message handler
// ---------------------------------------------------------------------------

async function handleMessages(sock, messages) {
  for (const msg of messages) {
    try {
      const jid = msg.key.remoteJid

      if (!isJidGroup(jid)) continue
      if (deniedJids.has(jid)) continue
      if (!msg.message) continue
      if (msg.key.fromMe) continue // ignore messages sent by this account

      if (!allowedJids.has(jid)) {
        await resolveJid(sock, jid)
      }
      if (!allowedJids.has(jid)) continue

      const text = extractText(msg.message)
      if (!text || !text.trim()) continue

      const groupName = allowedJids.get(jid)
      const senderJid = msg.key.participant || msg.key.remoteJid
      const phone = extractPhone(senderJid)
      if (!phone) {
        console.warn(`[Bot] Could not resolve phone for JID: ${senderJid} — skipping`)
        continue
      }
      const name = msg.pushName || null
      const timestamp = getTimestamp(msg.messageTimestamp)

      await sendToAPI(groupName, phone, name, text.trim(), timestamp)
    } catch (err) {
      console.error('[Bot] Error processing message:', err.message)
    }
  }
}

// ---------------------------------------------------------------------------
// Connection
// ---------------------------------------------------------------------------

async function connectToWhatsApp() {
  const { version, isLatest } = await fetchLatestBaileysVersion()
  console.log(`[Bot] WhatsApp Web v${version.join('.')} (latest: ${isLatest})`)

  const { state, saveCreds } = await useMultiFileAuthState('auth_session')

  const sock = makeWASocket({
    version,
    auth: state,
    logger: pino({ level: 'silent' }),
    markOnlineOnConnect: false,
    syncFullHistory: false,
  })

  sock.ev.on('creds.update', saveCreds)

  sock.ev.on('connection.update', async (update) => {
    const { connection, lastDisconnect, qr } = update

    if (qr) {
      console.log('\n[Bot] Scan this QR with WhatsApp → Settings → Linked Devices:\n')
      qrcode.generate(qr, { small: true })
    }

    if (connection === 'open') {
      console.log('[Bot] Connected!')
      await discoverGroups(sock)
    }

    if (connection === 'close') {
      const statusCode = new Boom(lastDisconnect?.error)?.output?.statusCode
      const loggedOut = statusCode === DisconnectReason.loggedOut

      if (loggedOut) {
        console.log('[Bot] Logged out. Delete auth_session/ and restart.')
        process.exit(1)
      } else {
        console.log(`[Bot] Disconnected (${statusCode}). Reconnecting in 3s…`)
        allowedJids.clear()
        deniedJids.clear()
        setTimeout(connectToWhatsApp, 3000)
      }
    }
  })

  sock.ev.on('messages.upsert', async ({ messages, type }) => {
    if (type !== 'notify') return
    await handleMessages(sock, messages)
  })
}

connectToWhatsApp().catch((err) => {
  console.error('[Bot] Fatal:', err)
  process.exit(1)
})
