const admin = require("firebase-admin");
const serviceAccount = require("./serviceAccountKey.json");

const brokenProxyValues = new Set([
  "http://127.0.0.1:9",
  "https://127.0.0.1:9",
  "127.0.0.1:9",
]);

for (const key of [
  "HTTP_PROXY",
  "HTTPS_PROXY",
  "ALL_PROXY",
  "http_proxy",
  "https_proxy",
  "all_proxy",
]) {
  const value = process.env[key];
  if (value && brokenProxyValues.has(value.trim())) {
    delete process.env[key];
  }
}

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();
const auth = admin.auth();

module.exports = {
  admin,
  db,
  auth
};
