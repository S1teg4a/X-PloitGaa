// server.js — combined HTTP key-server + Discord admin bot
// usage: set env BOT_TOKEN, OWNER_ID, API_SECRET, PORT (optional)

const fs = require("fs");
const path = "./keys.json";
const express = require("express");
const bodyParser = require("body-parser");
const rateLimit = require("express-rate-limit"); // lightweight limiter (optional)
const { Client, GatewayIntentBits } = require("discord.js");

// --- helper to load/save keys.json ---
function loadKeys() {
  try {
    const raw = fs.readFileSync(path, "utf8");
    return JSON.parse(raw);
  } catch (e) {
    const init = { free: {}, lifetime: {} };
    fs.writeFileSync(path, JSON.stringify(init, null, 2));
    return init;
  }
}
function saveKeys(keys) {
  fs.writeFileSync(path, JSON.stringify(keys, null, 2));
}

// --- config from env ---
const BOT_TOKEN = process.env.BOT_TOKEN || "";
const OWNER_ID = process.env.OWNER_ID || ""; // Discord user id of owner
const API_SECRET = process.env.API_SECRET || "replace_me_secret";
const PORT = parseInt(process.env.PORT || process.env.VERCEL_PORT || 3000, 10);

// --- express app ---
const app = express();
app.use(bodyParser.json());

// Basic in-memory rate limiter per IP (to avoid abuse on /validate)
const ipCounts = {};
const RATE_WINDOW_MS = 60 * 1000; // 1 minute
const RATE_MAX = 20; // per minute

function tooManyRequests(ip) {
  const now = Date.now();
  if (!ipCounts[ip]) ipCounts[ip] = { t: now, c: 1 };
  else {
    if (now - ipCounts[ip].t > RATE_WINDOW_MS) {
      ipCounts[ip].t = now; ipCounts[ip].c = 1;
    } else {
      ipCounts[ip].c += 1;
    }
  }
  return ipCounts[ip].c > RATE_MAX;
}

// Health endpoint
app.get("/", (req, res) => {
  res.json({ ok: true, message: "XPG key server running" });
});

// Validate endpoint (POST { key })
app.post("/validate", (req, res) => {
  try {
    const secret = req.header("X-API-SECRET") || "";
    if (secret !== API_SECRET) return res.status(401).json({ success:false, reason:"bad-secret" });

    const ip = req.ip || req.connection.remoteAddress || "unknown";
    if (tooManyRequests(ip)) return res.status(429).json({ success:false, reason:"rate-limit" });

    const key = (req.body && req.body.key) ? String(req.body.key).trim() : "";
    if (!key) return res.status(400).json({ success:false, reason:"empty-key" });

    const keys = loadKeys();

    // lifetime check
    if (keys.lifetime && keys.lifetime[key]) {
      return res.json({ success:true, type:"vvip", consumed:false, uses_left:null });
    }
    // free check
    if (keys.free && typeof keys.free[key] === "number") {
      const uses = keys.free[key];
      if (uses <= 0) {
        return res.json({ success:false, reason:"no-uses-left" });
      }
      // decrement and save
      keys.free[key] = Math.max(0, uses - 1);
      saveKeys(keys);
      return res.json({ success:true, type:"free", consumed:true, uses_left: keys.free[key] });
    }
    // not found
    return res.json({ success:false, reason:"invalid-key" });
  } catch (err) {
    console.error("validate err:", err);
    return res.status(500).json({ success:false, reason:"server-error" });
  }
});

// Admin endpoints (optional protection via BOT owner secret)
app.post("/admin/generate/free", (req, res) => {
  const secret = req.header("X-API-SECRET") || "";
  if (secret !== API_SECRET) return res.status(401).json({ success:false, reason:"bad-secret" });
  const uses = parseInt(req.body.uses || 3, 10) || 3;
  const key = `FREE-${Math.random().toString(36).slice(2,10).toUpperCase()}`;
  const keys = loadKeys();
  keys.free[key] = uses;
  saveKeys(keys);
  res.json({ success:true, key, uses });
});
app.post("/admin/generate/life", (req, res) => {
  const secret = req.header("X-API-SECRET") || "";
  if (secret !== API_SECRET) return res.status(401).json({ success:false, reason:"bad-secret" });
  const key = `VVIP-${Math.random().toString(36).slice(2,10).toUpperCase()}`;
  const keys = loadKeys();
  keys.lifetime[key] = true;
  saveKeys(keys);
  res.json({ success:true, key });
});

// start HTTP server
const server = app.listen(PORT, () => {
  console.log(`Key server listening on port ${PORT}`);
  console.log(`API_SECRET: ${API_SECRET ? "SET" : "NOT-SET"}`);
});

// ---- Discord bot section ----
if (!BOT_TOKEN) {
  console.log("BOT_TOKEN not provided — Discord commands disabled.");
} else {
  const client = new Client({
    intents: [GatewayIntentBits.Guilds, GatewayIntentBits.GuildMessages, GatewayIntentBits.MessageContent, GatewayIntentBits.DirectMessages],
    partials: ["CHANNEL"]
  });

  client.on("ready", () => {
    console.log("Discord bot ready:", client.user && client.user.tag);
  });

  function genKey(prefix="KEY") {
    return `${prefix}-${Math.random().toString(36).slice(2,10).toUpperCase()}`;
  }

  client.on("messageCreate", async (msg) => {
    try {
      if (!msg || !msg.content) return;
      if (msg.author.bot) return;
      const content = msg.content.trim();
      // allow only owner
      if (!OWNER_ID || String(msg.author.id) !== String(OWNER_ID)) return;

      // !gen free [uses]
      if (content.startsWith("!gen free")) {
        const parts = content.split(/\s+/);
        const uses = parseInt(parts[2], 10) || 3;
        const keys = loadKeys();
        const key = genKey("FREE");
        keys.free[key] = uses;
        saveKeys(keys);
        return msg.reply(`✅ Free key created: \`${key}\` (uses: ${uses})`);
      }

      if (content.startsWith("!gen life") || content.startsWith("!gen vvip")) {
        const keys = loadKeys();
        const key = genKey("VVIP");
        keys.lifetime[key] = true;
        saveKeys(keys);
        return msg.reply(`💎 Lifetime key created: \`${key}\``);
      }

      if (content.startsWith("!del ")) {
        const parts = content.split(/\s+/);
        const key = parts[1];
        const keys = loadKeys();
        let removed = false;
        if (keys.free && keys.free[key] !== undefined) { delete keys.free[key]; removed = true; }
        if (keys.lifetime && keys.lifetime[key]) { delete keys.lifetime[key]; removed = true; }
        saveKeys(keys);
        return msg.reply(removed ? `🗑 Key removed: \`${key}\`` : `Key not found: \`${key}\``);
      }

      if (content === "!listkeys") {
        const keys = loadKeys();
        const freeEntries = Object.entries(keys.free || {});
        const lifetimeEntries = Object.keys(keys.lifetime || {});
        let out = "Free keys:\n";
        freeEntries.slice(0,50).forEach(([k,v]) => out += `${k} (uses:${v})\n`);
        out += "\nLifetime keys:\n";
        lifetimeEntries.slice(0,50).forEach(k => out += `${k}\n`);
        // split if too long
        const chunks = [];
        while (out.length) {
          chunks.push(out.slice(0,1900));
          out = out.slice(1900);
        }
        for (const c of chunks) await msg.channel.send("```" + c + "```");
        return;
      }

    } catch (err) {
      console.error("bot message error:", err);
    }
  });

  client.login(BOT_TOKEN).catch(e => console.error("Discord login failed:", e.message));
}
