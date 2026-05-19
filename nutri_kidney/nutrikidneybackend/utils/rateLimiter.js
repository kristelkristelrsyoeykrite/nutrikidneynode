function normalizeIdentifier(value) {
  return String(value || "").trim().toLowerCase();
}

function createRateLimiter({
  windowMs = 60 * 1000,
  max = 10,
  keyPrefix = "default",
  keyGenerator,
  message = "Too many attempts. Please try again later.",
} = {}) {
  const attempts = new Map();

  return function rateLimit(req, res, next) {
    const now = Date.now();
    const generatedKey =
      typeof keyGenerator === "function" ? keyGenerator(req) : req.ip;
    const key = `${keyPrefix}:${normalizeIdentifier(generatedKey || req.ip)}`;
    const existing = attempts.get(key);

    if (!existing || existing.resetAt <= now) {
      attempts.set(key, { count: 1, resetAt: now + windowMs });
      return next();
    }

    existing.count += 1;
    if (existing.count > max) {
      res.set("Retry-After", String(Math.ceil((existing.resetAt - now) / 1000)));
      return res.status(429).json({
        success: false,
        error: message,
      });
    }

    return next();
  };
}

function identityKey(req, fields = []) {
  const body = req.body && typeof req.body === "object" ? req.body : {};
  const identity = fields
    .map((field) => normalizeIdentifier(body[field]))
    .find(Boolean);
  return `${req.ip}:${identity || "anonymous"}`;
}

module.exports = {
  createRateLimiter,
  identityKey,
};
