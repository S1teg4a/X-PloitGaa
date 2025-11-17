// server.js
// Simple key server + discord bot
// Endpoints:
//  GET /           -> alive page
//  POST /validate  -> { key } with header X-API-SECRET
//  POST /admin/generate/free  -> { uses } (X-API-SECRET)
//  POST /admin/generate/life  -> (X-API-SECRET)
//  POST /admin/delete         -> { key } (X-API-SECRET)
//  GET  /admin/list           -> (X-API-SECRET)

const fs = require("fs");
const path = require("path");
const express = require("express");
const bodyParser = require("body-parser");
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
const API_SECRET = process.env.API_SECRET || "change_me";
const BOT_TOKEN = process.env.BOT_TOKEN || "";
const OWNER_ID = process.env.OWNER_ID || ""; // optional

const KEYS_FILE = path.resolve(__dirname, "keys.json");

// load or init keys file
function loadKeys() {
  try {
    const raw = fs.readFileSync(KEYS_FILE, "utf8");
    return JSON.parse(raw);
  } catch (e) {
    const init = { free: {}, lifetime: {} };
    fs.writeFileSync(KEYS_FILE, JSON.stringify(init, null, 2), "utf8");
    return init;
  }
}
function saveKeys(k) {
  fs.writeFileSync(KEYS_FILE, JSON.stringify(k, null, 2), "utf8");
}
let keys = loadKeys();

// helper generator
function genKey(prefix = "KEY") {
  return `${prefix}-${Math.random().toString(36).slice(2,10).toUpperCase()}`;
}

// Express app
const app = express();
app.use(bodyParser.json());

// root
app.get("/", (req, res) => {
  res.setHeader("Content-Type","text/plain");
  res.send("XPG Key Server (alive). POST /validate with X-API-SECRET header.");
});

// validate endpoint
app.post("/validate", (req, res) => {
  const secret = req.header("X-API-SECRET");
  if (!secret || secret !== API_SECRET) {
    // We still allow requests without secret? No — require secret for server API calls from clients.
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
    saveKeys(keys);
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
  saveKeys(keys);
  return res.json({ success:true, key, uses });
});

app.post("/admin/generate/life", requireSecret, (req,res) => {
  const key = genKey("VVIP");
  keys.lifetime[key] = true;
  saveKeys(keys);
  return res.json({ success:true, key });
});

app.post("/admin/delete", requireSecret, (req,res) => {
  const key = (req.body && req.body.key) ? String(req.body.key).trim() : "";
  if (!key) return res.status(400).json({ success:false, reason:"empty-key" });
  let removed = false;
  if (keys.free[key]) { delete keys.free[key]; removed = true; }
  if (keys.lifetime[key]) { delete keys.lifetime[key]; removed = true; }
  if (removed) { saveKeys(keys); return res.json({ success:true, removed:key }); }
  return res.json({ success:false, reason:"not-found" });
});

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

      /**
       * MESSAGE-BASED TRIGGER
       * - Owner sends: !panel
       * - Bot will send a message containing a panel of buttons:
       *    [Generate Free] [Generate Lifetime] [Delete Key] [List Keys]
       *
       * - Generate Free / Delete Key open a modal for input (uses / key)
       * - Buttons and modals are owner-only (checked by OWNER_ID). Non-owner presses will receive ephemeral denial.
       *
       * NOTE: This replaces the previous text commands with a button panel as requested.
       */

      client.on("messageCreate", async (msg) => {
        if (msg.author.bot) return;
        const content = (msg.content || "").trim();
        if (OWNER_ID && msg.author.id !== OWNER_ID) return; // only owner can use bot panel
        if (!content) return;

        // send panel when owner types !panel
        if (content === "!panel") {
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
        }
      });

      // Interaction handler for buttons and modals
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

              const firstRow = new ActionRowBuilder().addComponents(usesInput);
              modal.addComponents(firstRow);

              await interaction.showModal(modal);
            } else if (id === "gen_life") {
              // create lifetime key immediately
              const newKey = genKey("VVIP");
              keys.lifetime[newKey] = true;
              saveKeys(keys);
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
              // prepare list (limited to safe length)
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
              saveKeys(keys);
              await interaction.reply({ content: `✅ Free key created: \`${newKey}\` (uses: ${uses})`, ephemeral: true });
            } else if (id === "modal_del_key") {
              const keyToDel = interaction.fields.getTextInputValue("delkey") || "";
              const k = String(keyToDel).trim();
              if (!k) return interaction.reply({ content: "❌ Key kosong.", ephemeral: true });
              let removed = false;
              if (keys.free[k]) { delete keys.free[k]; removed = true; }
              if (keys.lifetime[k]) { delete keys.lifetime[k]; removed = true; }
              if (removed) { saveKeys(keys); return interaction.reply({ content: `🗑 Key removed: \`${k}\``, ephemeral: true }); }
              return interaction.reply({ content: `Key not found: \`${k}\``, ephemeral: true });
            }
          }
        } catch (err) {
          console.error("Interaction handler error:", err);
          try {
            if (interaction && interaction.replied === false && interaction.deferred === false) {
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
  });
}

startServer().catch(e => console.error(e));
