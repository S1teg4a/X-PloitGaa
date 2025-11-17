// api/validate.js
// Vercel Serverless function to validate keys
const fs = require("fs");
const path = require("path");

const KEYS_FILE = path.join(__dirname, "..", "keys.json");
const API_SECRET = process.env.API_SECRET || "";

function loadKeys() {
  try {
    const raw = fs.readFileSync(KEYS_FILE, "utf8");
    return JSON.parse(raw);
  } catch (e) {
    const init = { free: {}, lifetime: {} };
    try { fs.writeFileSync(KEYS_FILE, JSON.stringify(init, null, 2)); } catch (e2) {}
    return init;
  }
}

function saveKeys(keys) {
  try {
    fs.writeFileSync(KEYS_FILE, JSON.stringify(keys, null, 2));
    return true;
  } catch (e) {
    console.error("saveKeys error", e);
    return false;
  }
}

module.exports = async (req, res) => {
  // Only POST allowed
  if (req.method !== "POST") {
    res.setHeader("Allow", "POST");
    return res.status(405).json({ success: false, reason: "method-not-allowed" });
  }

  // Check secret header
  const header = req.headers["x-api-secret"] || req.headers["X-API-SECRET"] || "";
  if (!API_SECRET || header !== API_SECRET) {
    return res.status(403).json({ success: false, reason: "bad-secret" });
  }

  const key = (req.body && req.body.key) ? String(req.body.key).trim() : "";
  if (!key) return res.status(400).json({ success: false, reason: "empty-key" });

  const keys = loadKeys();

  // lifetime keys
  if (keys.lifetime && keys.lifetime[key]) {
    return res.json({ success: true, type: "vvip", consumed: false, source: "server" });
  }

  // free keys
  if (keys.free && typeof keys.free[key] !== "undefined") {
    const uses = Number(keys.free[key]) || 0;
    if (uses <= 0) {
      return res.json({ success: false, reason: "no-uses-left", type: "free", uses_left: 0 });
    }
    keys.free[key] = Math.max(0, uses - 1);
    const ok = saveKeys(keys);
    return res.json({ success: true, type: "free", consumed: true, uses_left: keys.free[key], source: ok ? "server" : "server-nosave" });
  }

  // not found
  return res.json({ success: false, reason: "invalid-key" });
};
