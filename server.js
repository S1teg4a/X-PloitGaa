// server.js
// Key server + discord bot with:
//  - /validate (server API)
//  - admin endpoints (generate/delete/list)
//  - token-based claim flow (create-claim, token check, redeem)
//  - claim page /claim (OAuth2 optional) + redeem flow
//  - rate-limit for create-claim (per Discord ID, per IP)
//  - random key selection from pool
//
// Required env:
//  API_SECRET (server->client secret), BOT_TOKEN (optional), OWNER_ID (optional),
//  BASE_URL (optional, default http://localhost:PORT)
// Optional for OAuth2:
//  OAUTH_CLIENT_ID, OAUTH_CLIENT_SECRET, OAUTH_CALLBACK_URL
//
// NOTE: keep API_SECRET private. For production, add stronger rate-limiting, persistent DB, HTTPS, etc.

const fs = require("fs");
const path = require("path");
const express = require("express");
const bodyParser = require("body-parser");
const fetch = require("node-fetch"); // npm i node-fetch@2
const session = require("express-session"); // npm i express-session
const {
  Client,
  GatewayIntentBits,
  ActionRowBuilder,
  ButtonBuilder,
  ButtonStyle,
  ModalBuilder,
  TextInputBuilder,
  TextInputStyle
} = require("discord.js");

const PORT = process.env.PORT || 3000;
const API_SECRET = process.env.API_SECRET || "ranggskecil35_secret_dont_open";
const BOT_TOKEN = process.env.BOT_TOKEN || "";
const OWNER_ID = process.env.OWNER_ID || ""; // optional
const BASE_URL = process.env.BASE_URL || `http://localhost:${PORT}`;

const OAUTH_CLIENT_ID = process.env.OAUTH_CLIENT_ID || "";
const OAUTH_CLIENT_SECRET = process.env.OAUTH_CLIENT_SECRET || "";
const OAUTH_CALLBACK_URL = process.env.OAUTH_CALLBACK_URL || `${BASE_URL.replace(/\/$/,'')}/auth/callback`;

// Files
const KEYS_FILE = path.resolve(__dirname, "keys.json");
const TOKENS_FILE = path.resolve(__dirname, "tokens.json");

// --- helpers to load/save JSON files
function safeLoad(filePath, defaultVal) {
  try {
    const raw = fs.readFileSync(filePath, "utf8");
    return JSON.parse(raw);
  } catch (e) {
    try {
      fs.writeFileSync(filePath, JSON.stringify(defaultVal, null, 2), "utf8");
    } catch (e2) {}
    return defaultVal;
  }
}
function safeSave(filePath, obj) {
  try {
    fs.writeFileSync(filePath, JSON.stringify(obj, null, 2), "utf8");
    return true;
  } catch (e) {
    console.error("Failed to save", filePath, e);
    return false;
  }
}

// load or init keys file
let keys = safeLoad(KEYS_FILE, { free: {}, lifetime: {} });
function saveKeys() { safeSave(KEYS_FILE, keys); }

// tokens store
let tokens = safeLoad(TOKENS_FILE, {}); // { token: { discordId, createdAt, expiresAt, used:bool } }
function saveTokens() { safeSave(TOKENS_FILE, tokens); }

// helper generator
function genKey(prefix = "KEY") {
  return `${prefix}-${Math.random().toString(36).slice(2,10).toUpperCase()}`;
}

// create token (expires in minutes)
function createToken(discordId, minutes = 10) {
  const t = Math.random().toString(36).slice(2,16).toUpperCase();
  const now = Date.now();
  tokens[t] = {
    discordId: String(discordId || ""),
    createdAt: now,
    expiresAt: now + (minutes * 60 * 1000),
    used: false
  };
  saveTokens();
  return t;
}

function getTokenInfo(token) {
  const rec = tokens[token];
  if (!rec) return { ok:false, reason: "not-found" };
  if (rec.used) return { ok:false, reason: "used" };
  if (Date.now() > rec.expiresAt) return { ok:false, reason: "expired" };
  return { ok:true, info:rec };
}

function useToken(token) {
  const rec = tokens[token];
  if (!rec) return { ok:false, reason: "not-found" };
  if (rec.used) return { ok:false, reason: "used" };
  if (Date.now() > rec.expiresAt) return { ok:false, reason: "expired" };
  rec.used = true;
  saveTokens();
  return { ok:true, info:rec };
}

// pick a key from pool randomly: prefer free keys with uses>0; else random lifetime key
function consumeKeyFromPool() {
  const freeKeys = Object.entries(keys.free || {}).filter(([k,v]) => Number(v) > 0);
  if (freeKeys.length > 0) {
    const idx = Math.floor(Math.random() * freeKeys.length);
    const [k, v] = freeKeys[idx];
    keys.free[k] = Math.max(0, Number(v) - 1);
    saveKeys();
    return { ok:true, key:k, type:"free", uses_left: keys.free[k] };
  }
  const lifetimeKeys = Object.keys(keys.lifetime || {});
  if (lifetimeKeys.length > 0) {
    const idx = Math.floor(Math.random() * lifetimeKeys.length);
    const k = lifetimeKeys[idx];
    return { ok:true, key:k, type: "vvip" };
  }
  return { ok:false, reason: "no-keys-available" };
}

// ---------------- Rate limiting ----------------
// Per-Discord-ID: allow 1 token per 5 minutes (default)
const RATE_LIMIT_WINDOW_MS = (parseInt(process.env.RATE_LIMIT_MINUTES || "5", 10) || 5) * 60 * 1000;
const rateLimitByDiscord = {}; // { discordId: lastCreatedAt }
const rateLimitByIP = {}; // simple IP rate limit: allow 5 per hour
const IP_WINDOW_MS = 60*60*1000;
const IP_MAX_PER_WINDOW = parseInt(process.env.IP_MAX_PER_WINDOW || "20", 10) || 20;
const ipCounters = {}; // { ip: {count, windowStart} }

// ---------------- Express setup ----------------
const app = express();
app.use(bodyParser.json());
app.use(express.urlencoded({ extended: true }));

// session for OAuth
app.use(session({
  secret: process.env.SESSION_SECRET || "change_session_secret",
  resave: false,
  saveUninitialized: true,
  cookie: { secure: false } // set true if HTTPS
}));

// root
app.get("/", (req, res) => {
  res.setHeader("Content-Type","text/plain");
  res.send("XPG Key Server (alive). POST /validate with X-API-SECRET header.");
});

// validate endpoint (used by clients/scripts)
app.post("/validate", (req, res) => {
  const secret = req.header("X-API-SECRET");
  if (!secret || secret !== API_SECRET) {
    return res.status(401).json({ success:false, reason:"bad-secret" });
  }
  const key = (req.body && req.body.key) ? String(req.body.key).trim() : "";
  if (!key) return res.status(400).json({ success:false, reason:"empty-key" });

  // lifetime check
  if (keys.lifetime && keys.lifetime[key]) {
    return res.json({ success: true, type: "vvip", consumed: false, source: "server" });
  }
  // free check
  if (keys.free && keys.free[key] && Number(keys.free[key]) > 0) {
    // decrement uses
    keys.free[key] = Math.max(0, Number(keys.free[key]) - 1);
    saveKeys();
    return res.json({ success: true, type: "free", consumed: true, uses_left: keys.free[key], source: "server" });
  }

  return res.json({ success: false, reason: "invalid-key" });
});

// admin endpoints (protected by same API_SECRET)
function requireSecret(req, res, next) {
  const secret = req.header("X-API-SECRET");
  if (!secret || secret !== API_SECRET) {
    return res.status(401).json({ success:false, reason:"bad-secret" });
  }
  return next();
}

app.get("/admin/list", requireSecret, (req,res) => {
  return res.json({ success:true, keys });
});

app.post("/admin/generate/free", requireSecret, (req,res) => {
  const uses = parseInt((req.body && req.body.uses) || 3, 10) || 3;
  const key = genKey("FREE");
  keys.free[key] = uses;
  saveKeys();
  return res.json({ success:true, key, uses });
});

app.post("/admin/generate/life", requireSecret, (req,res) => {
  const key = genKey("VVIP");
  keys.lifetime[key] = true;
  saveKeys();
  return res.json({ success:true, key });
});

app.post("/admin/delete", requireSecret, (req,res) => {
  const key = (req.body && req.body.key) ? String(req.body.key).trim() : "";
  if (!key) return res.status(400).json({ success:false, reason:"empty-key" });
  let removed = false;
  if (keys.free[key]) { delete keys.free[key]; removed = true; }
  if (keys.lifetime[key]) { delete keys.lifetime[key]; removed = true; }
  if (removed) { saveKeys(); return res.json({ success:true, removed:key }); }
  return res.json({ success:false, reason:"not-found" });
});

// ----------------- TOKEN / CLAIM endpoints -----------------

// helper: check and increment IP counter
function checkIpRateLimit(ip) {
  const now = Date.now();
  let rec = ipCounters[ip];
  if (!rec) {
    rec = { count: 1, windowStart: now };
    ipCounters[ip] = rec;
    return { ok:true };
  }
  if (now - rec.windowStart > IP_WINDOW_MS) {
    rec.count = 1;
    rec.windowStart = now;
    return { ok:true };
  }
  rec.count += 1;
  if (rec.count > IP_MAX_PER_WINDOW) {
    return { ok:false, reason: "ip-rate-limit" };
  }
  return { ok:true };
}

// Create claim token (bot calls this). Rate-limited per Discord ID and per IP.
app.post("/create-claim", (req, res) => {
  // optional: require secret for external calls
  const secret = req.header("X-API-SECRET");
  // You can force secret by uncommenting next lines:
  // if (!secret || secret !== API_SECRET) return res.status(401).json({ success:false, reason:"bad-secret" });

  const discordId = (req.body && req.body.discordId) ? String(req.body.discordId) : "";
  const minutes = parseInt((req.body && req.body.minutes) || 10, 10) || 10;
  const ip = req.ip || req.connection.remoteAddress || "unknown";

  // IP rate-limit
  const ipOk = checkIpRateLimit(ip);
  if (!ipOk.ok) return res.status(429).json({ success:false, reason: ipOk.reason });

  // Discord ID rate-limit
  if (discordId) {
    const last = rateLimitByDiscord[discordId] || 0;
    const now = Date.now();
    if (now - last < RATE_LIMIT_WINDOW_MS) {
      const waitMs = RATE_LIMIT_WINDOW_MS - (now - last);
      return res.status(429).json({ success:false, reason:"discord-rate-limit", retry_after_ms: waitMs });
    }
    rateLimitByDiscord[discordId] = now;
  }

  const token = createToken(discordId, minutes);
  const url = `${BASE_URL.replace(/\/$/,'')}/claim?token=${token}`;
  return res.json({ success:true, token, url, expires_in_minutes: minutes });
});

// Check token
app.get("/token/:token", (req, res) => {
  const t = String(req.params.token || "");
  const info = getTokenInfo(t);
  if (!info.ok) return res.json({ success:false, reason: info.reason });
  return res.json({ success:true, token:t, info: info.info });
});

// Redeem token -> optionally require OAuth verification (if token has discordId)
app.post("/redeem/:token", async (req, res) => {
  const t = String(req.params.token || "");
  const check = getTokenInfo(t);
  if (!check.ok) return res.status(400).json({ success:false, reason: check.reason });

  const rec = check.info;
  // If token has discordId and request indicates discord verification required,
  // caller should provide 'discordId' in body (from OAuth session) or server should enforce.
  const enforceDiscordMatch = (req.body && req.body.enforceDiscord) ? true : false;
  if (enforceDiscordMatch && rec.discordId) {
    const callerDiscordId = (req.body && req.body.discordId) ? String(req.body.discordId) : "";
    if (!callerDiscordId || callerDiscordId !== String(rec.discordId)) {
      return res.status(403).json({ success:false, reason:"discord-mismatch" });
    }
  }

  // mark token used
  const used = useToken(t);
  if (!used.ok) return res.status(400).json({ success:false, reason: used.reason });

  // try to consume a key
  const consumed = consumeKeyFromPool();
  if (!consumed.ok) {
    return res.status(400).json({ success:false, reason: "no-keys-available" });
  }

  return res.json({ success:true, key: consumed.key, type: consumed.type, uses_left: consumed.uses_left });
});

// Minimal claim page (static HTML + client-side fetch + OAuth support)
app.get("/claim", (req, res) => {
  const token = String(req.query.token || "");
  const oauthAvailable = OAUTH_CLIENT_ID && OAUTH_CLIENT_SECRET && OAUTH_CALLBACK_URL;
  const html = `<!doctype html>
<html>
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width,initial-scale=1" />
<title>Claim Key</title>
<style>
body{font-family:system-ui,-apple-system,Segoe UI,Roboto,Arial;background:#0e0f12;color:#e6fff8;display:flex;align-items:center;justify-content:center;height:100vh;margin:0}
.card{background:#121214;padding:24px;border-radius:12px;max-width:640px;width:100%;box-shadow:0 6px 30px rgba(0,0,0,0.6)}
h1{margin:0 0 12px 0;color:#00f0c8}
p{color:#bdbdbd}
button{background:#00f0c8;border:0;padding:10px 14px;border-radius:8px;font-weight:600;cursor:pointer}
pre{background:#0b0b0b;padding:12px;border-radius:8px;color:#dff;white-space:pre-wrap;word-break:break-word}
.small{font-size:13px;color:#98f}
.note{margin-top:8px;color:#aab}
</style>
</head>
<body>
  <div class="card">
    <h1>Claim Key</h1>
    <p class="small">Token: <strong id="token">${token || ""}</strong></p>
    <div id="status">Checking token...</div>
    <div style="margin-top:12px" id="actionArea"></div>
    <div id="result" style="margin-top:12px"></div>
    <div class="note">Link ini valid singkat; jangan sebarkan token publik.</div>
  </div>
<script>
(async function(){
  const token = "${token}";
  const status = document.getElementById('status');
  const actionArea = document.getElementById('actionArea');
  const result = document.getElementById('result');
  const oauthAvailable = ${oauthAvailable ? 'true' : 'false'};

  if(!token) {
    status.textContent = "No token provided in URL.";
    return;
  }

  try {
    const r = await fetch('/token/' + token);
    const j = await r.json();
    if(!j.success) {
      status.textContent = 'Invalid token: ' + (j.reason || 'unknown');
      return;
    }
    status.textContent = 'Token valid. Expires at: ' + new Date(j.info.expiresAt).toLocaleString();
    // If token tied to discordId and OAuth available, ask user to authenticate first
    const needAuth = !!j.info.discordId && oauthAvailable;
    if (needAuth) {
      const authBtn = document.createElement('button');
      authBtn.textContent = 'Authenticate with Discord';
      authBtn.onclick = function() {
        // redirect to OAuth entry point
        window.location.href = '/auth/discord?next=' + encodeURIComponent(location.href);
      };
      actionArea.appendChild(authBtn);
      const info = document.createElement('div'); info.className='note'; info.textContent = 'Token restricted to a Discord account — authenticate to continue.'; actionArea.appendChild(info);
      return;
    }

    const btn = document.createElement('button');
    btn.textContent = 'Redeem Key';
    btn.onclick = async function() {
      btn.disabled = true;
      status.textContent = 'Redeeming...';
      try {
        const rr = await fetch('/redeem/' + token, { method: 'POST', headers: {'Content-Type':'application/json'} });
        const jj = await rr.json();
        if(jj.success) {
          status.textContent = 'Success! Here is your key:';
          result.innerHTML = '<pre>' + (jj.key || '') + '</pre>';
        } else {
          status.textContent = 'Redeem failed: ' + (jj.reason || 'unknown');
        }
      } catch(e) {
        status.textContent = 'Redeem error: ' + e.message;
      } finally {
        btn.disabled = false;
      }
    };
    actionArea.appendChild(btn);
  } catch (e) {
    status.textContent = 'Error checking token: ' + e.message;
  }
})();
</script>
</body>
</html>`;
  res.setHeader("Content-Type","text/html");
  res.send(html);
});

// ----------------- OAuth endpoints (Discord) -----------------
// Start OAuth flow (redirect to Discord)
app.get("/auth/discord", (req, res) => {
  if (!OAUTH_CLIENT_ID || !OAUTH_CLIENT_SECRET) {
    return res.status(500).send("OAuth not configured on server.");
  }
  // store next URL
  const next = req.query.next || '/claim';
  req.session.next = next;
  const state = Math.random().toString(36).slice(2);
  req.session.oauthState = state;
  const scope = encodeURIComponent("identify");
  const redirect = encodeURIComponent(OAUTH_CALLBACK_URL);
  const url = `https://discord.com/api/oauth2/authorize?client_id=${OAUTH_CLIENT_ID}&redirect_uri=${redirect}&response_type=code&scope=${scope}&state=${state}`;
  res.redirect(url);
});

// OAuth callback
app.get("/auth/callback", async (req, res) => {
  const code = req.query.code;
  const state = req.query.state;
  if (!code || !state || state !== req.session.oauthState) {
    return res.status(400).send("Invalid OAuth state or missing code.");
  }

  // exchange code for token
  const params = new URLSearchParams();
  params.append("client_id", OAUTH_CLIENT_ID);
  params.append("client_secret", OAUTH_CLIENT_SECRET);
  params.append("grant_type", "authorization_code");
  params.append("code", code);
  params.append("redirect_uri", OAUTH_CALLBACK_URL);
  try {
    const tokenRes = await fetch("https://discord.com/api/oauth2/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: params.toString()
    });
    const tokenJson = await tokenRes.json();
    if (!tokenJson.access_token) {
      return res.status(400).send("Failed to get access token.");
    }
    // get user
    const userRes = await fetch("https://discord.com/api/users/@me", {
      headers: { Authorization: `Bearer ${tokenJson.access_token}` }
    });
    const userJson = await userRes.json();
    // store user id in session
    req.session.discordUser = { id: userJson.id, username: userJson.username, discriminator: userJson.discriminator };
    // redirect back to next
    const next = req.session.next || '/claim';
    return res.redirect(next);
  } catch (e) {
    console.error("OAuth error:", e);
    return res.status(500).send("OAuth error");
  }
});

// Helper route for claim page to redeem with OAuth - this endpoint expects session with discordUser
// It will call /redeem/:token with enforceDiscord and discordId from session
app.post("/redeem-with-oauth/:token", async (req, res) => {
  const token = String(req.params.token || "");
  const sessionUser = req.session && req.session.discordUser;
  if (!sessionUser) return res.status(401).json({ success:false, reason:"not-authenticated" });
  // call internal redeem logic: pass discordId in body
  // We can call the redeem function directly instead of HTTP to ensure enforcement
  const check = getTokenInfo(token);
  if (!check.ok) return res.status(400).json({ success:false, reason: check.reason });
  const rec = check.info;
  if (rec.discordId && rec.discordId !== String(sessionUser.id)) {
    return res.status(403).json({ success:false, reason:"discord-mismatch" });
  }
  const used = useToken(token);
  if (!used.ok) return res.status(400).json({ success:false, reason: used.reason });
  const consumed = consumeKeyFromPool();
  if (!consumed.ok) return res.status(400).json({ success:false, reason: consumed.reason });
  return res.json({ success:true, key: consumed.key, type: consumed.type, uses_left: consumed.uses_left });
});

// ----------------- End token endpoints -----------------

// Start express server after optionally init bot
async function startServer() {
  // If BOT_TOKEN present, start bot
  if (BOT_TOKEN) {
    try {
      const client = new Client({
        intents: [
          GatewayIntentBits.Guilds,
          GatewayIntentBits.GuildMessages,
          GatewayIntentBits.MessageContent
        ]
      });

      client.once("ready", () => {
        console.log("Discord bot ready:", client.user && client.user.tag);
      });

      // Owner-only panel remains (for admin key management)
      client.on("messageCreate", async (msg) => {
        if (msg.author.bot) return;
        const content = (msg.content || "").trim();

        // Owner commands
        if (content === "!panel") {
          if (OWNER_ID && msg.author.id !== OWNER_ID) {
            return msg.reply("❌ Kamu bukan owner — akses ditolak.");
          }
          const row = new ActionRowBuilder().addComponents(
            new ButtonBuilder()
              .setCustomId("gen_free")
              .setLabel("Generate Free")
              .setStyle(ButtonStyle.Primary),
            new ButtonBuilder()
              .setCustomId("gen_life")
              .setLabel("Generate Lifetime")
              .setStyle(ButtonStyle.Success),
            new ButtonBuilder()
              .setCustomId("del_key")
              .setLabel("Delete Key")
              .setStyle(ButtonStyle.Danger),
            new ButtonBuilder()
              .setCustomId("list_keys")
              .setLabel("List Keys")
              .setStyle(ButtonStyle.Secondary)
          );

          await msg.channel.send({
            content: "Panel Tombol — pilih aksi:",
            components: [row]
          });
          return;
        }

        // Public getfree command -> create token and send claim link
        if (content === "!getfree") {
          // rate-limit: check per discord id
          const last = rateLimitByDiscord[msg.author.id] || 0;
          const now = Date.now();
          if (now - last < RATE_LIMIT_WINDOW_MS) {
            const waitMs = RATE_LIMIT_WINDOW_MS - (now - last);
            const waitSec = Math.ceil(waitMs/1000);
            return msg.reply(`⏳ Tunggu ${waitSec} detik sebelum meminta token baru.`);
          }
          rateLimitByDiscord[msg.author.id] = now;

          const token = createToken(msg.author.id, 10); // 10 minutes
          const url = `${BASE_URL.replace(/\/$/,'')}/claim?token=${token}`;
          try {
            // try DM first
            await msg.author.send(`Klik link ini untuk klaim key gratis (valid 10 menit):\n${url}`);
            await msg.reply({ content: "✅ Link klaim telah dikirim lewat DM. Cek inbox (atau buka tautan):" });
          } catch (e) {
            // fallback: reply in channel (non-DM)
            await msg.reply({ content: `Klik link ini untuk klaim key gratis (valid 10 menit):\n${url}` });
          }
          return;
        }
      });

      // Interaction handler for admin panel buttons and modals
      client.on("interactionCreate", async (interaction) => {
        try {
          // Button interactions
          if (interaction.isButton && interaction.isButton()) {
            // owner-only guard
            if (OWNER_ID && interaction.user.id !== OWNER_ID) {
              return interaction.reply({ content: "❌ Kamu bukan owner — akses ditolak.", ephemeral: true });
            }

            const id = interaction.customId;
            if (id === "gen_free") {
              // show modal to ask for uses
              const modal = new ModalBuilder()
                .setCustomId("modal_gen_free")
                .setTitle("Generate Free Key");

              const usesInput = new TextInputBuilder()
                .setCustomId("uses")
                .setLabel("Jumlah uses (kosong = 3)")
                .setStyle(TextInputStyle.Short)
                .setRequired(false)
                .setPlaceholder("3");

              modal.addComponents(new ActionRowBuilder().addComponents(usesInput));
              await interaction.showModal(modal);
            } else if (id === "gen_life") {
              // create lifetime key immediately
              const newKey = genKey("VVIP");
              keys.lifetime[newKey] = true;
              saveKeys();
              await interaction.reply({ content: `💎 Lifetime key created: \`${newKey}\``, ephemeral: true });
            } else if (id === "del_key") {
              // show modal to ask for key to delete
              const modal = new ModalBuilder()
                .setCustomId("modal_del_key")
                .setTitle("Delete Key");

              const keyInput = new TextInputBuilder()
                .setCustomId("delkey")
                .setLabel("Key yang ingin dihapus")
                .setStyle(TextInputStyle.Short)
                .setRequired(true)
                .setPlaceholder("e.g. FREE-ABC12345");

              modal.addComponents(new ActionRowBuilder().addComponents(keyInput));
              await interaction.showModal(modal);
            } else if (id === "list_keys") {
              const f = Object.entries(keys.free).map(([k,v])=>`${k} (free:${v})`).slice(0,50);
              const l = Object.keys(keys.lifetime).slice(0,50).map(k=>`${k} (vvip)`);
              const out = ["Free:", ...f, "Lifetime:", ...l].join("\n");
              const safeOut = out.length > 1900 ? out.slice(0,1900) + "\n\n…(truncated)" : out || "none";
              await interaction.reply({ content: "🔑 Keys:\n```\n" + safeOut + "\n```", ephemeral: true });
            } else {
              await interaction.reply({ content: "Unknown button.", ephemeral: true });
            }
            return;
          }

          // Modal submit handling
          if (interaction.isModalSubmit && interaction.isModalSubmit()) {
            // owner-only guard
            if (OWNER_ID && interaction.user.id !== OWNER_ID) {
              return interaction.reply({ content: "❌ Kamu bukan owner — akses ditolak.", ephemeral: true });
            }

            const id = interaction.customId;
            if (id === "modal_gen_free") {
              const usesVal = interaction.fields.getTextInputValue("uses") || "";
              let uses = parseInt(usesVal, 10);
              if (isNaN(uses) || uses <= 0) uses = 3;
              const newKey = genKey("FREE");
              keys.free[newKey] = uses;
              saveKeys();
              await interaction.reply({ content: `✅ Free key created: \`${newKey}\` (uses: ${uses})`, ephemeral: true });
            } else if (id === "modal_del_key") {
              const keyToDel = interaction.fields.getTextInputValue("delkey") || "";
              const k = String(keyToDel).trim();
              if (!k) return interaction.reply({ content: "❌ Key kosong.", ephemeral: true });
              let removed = false;
              if (keys.free[k]) { delete keys.free[k]; removed = true; }
              if (keys.lifetime[k]) { delete keys.lifetime[k]; removed = true; }
              if (removed) { saveKeys(); return interaction.reply({ content: `🗑 Key removed: \`${k}\``, ephemeral: true }); }
              return interaction.reply({ content: `Key not found: \`${k}\``, ephemeral: true });
            }
          }
        } catch (err) {
          console.error("Interaction handler error:", err);
          try {
            if (interaction && !interaction.replied && !interaction.deferred) {
              await interaction.reply({ content: "⚠️ Terjadi kesalahan saat memproses aksi.", ephemeral: true });
            }
          } catch (e) {
            // ignore
          }
        }
      });

      await client.login(BOT_TOKEN).catch(e => {
        console.error("Discord login failed:", e && e.message ? e.message : e);
      });
    } catch (err) {
      console.error("Bot startup error:", err);
    }
  } else {
    console.log("BOT_TOKEN not set — Discord bot disabled.");
  }

  app.listen(PORT, () => {
    console.log(`Key server running on port ${PORT}`);
    console.log(`Validate endpoint: POST http://<host>:${PORT}/validate with header X-API-SECRET: ${API_SECRET}`);
    console.log(`Claim base URL: ${BASE_URL}/claim?token=...`);
    if (OAUTH_CLIENT_ID && OAUTH_CLIENT_SECRET) {
      console.log(`OAuth callback: ${OAUTH_CALLBACK_URL}`);
    } else {
      console.log("OAuth not configured (OAUTH_CLIENT_ID/OAUTH_CLIENT_SECRET not set).");
    }
  });
}

startServer().catch(e => console.error(e));
