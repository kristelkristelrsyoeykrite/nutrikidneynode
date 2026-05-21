/**
 * Rate Limiting Middleware
 * Implements rate limiting for authentication endpoints to prevent brute force attacks
 */

// In-memory store for rate limit tracking
// In production, use Redis for distributed rate limiting
const rateLimitStore = new Map();

/**
 * Generate a rate limit key from request
 * Combines IP address and endpoint
 * @param {object} req - Express request
 * @param {string} endpoint - Endpoint identifier
 * @returns {string} Rate limit key
 */
function getRateLimitKey(req, endpoint) {
  const ip = req.ip || req.connection.remoteAddress || 'unknown';
  return `${endpoint}:${ip}`;
}

/**
 * Generate a user-based rate limit key
 * @param {string} identifier - User identifier (email, phone, uid)
 * @param {string} endpoint - Endpoint identifier
 * @returns {string} Rate limit key
 */
function getUserRateLimitKey(identifier, endpoint) {
  return `${endpoint}:user:${identifier}`;
}

/**
 * Check if request should be rate limited
 * @param {string} key - Rate limit key
 * @param {number} maxAttempts - Maximum attempts allowed
 * @param {number} windowMs - Time window in milliseconds
 * @returns {object} {allowed: boolean, remaining: number, resetTime: Date}
 */
function checkRateLimit(key, maxAttempts = 5, windowMs = 60000) {
  const now = Date.now();
  const record = rateLimitStore.get(key);

  if (!record || now - record.firstAttemptTime > windowMs) {
    // New window or expired record
    const newRecord = {
      firstAttemptTime: now,
      attempts: 1,
      resetTime: new Date(now + windowMs),
    };
    rateLimitStore.set(key, newRecord);
    return {
      allowed: true,
      remaining: maxAttempts - 1,
      resetTime: newRecord.resetTime,
    };
  }

  // Within current window
  record.attempts += 1;

  if (record.attempts > maxAttempts) {
    return {
      allowed: false,
      remaining: 0,
      resetTime: record.resetTime,
    };
  }

  return {
    allowed: true,
    remaining: maxAttempts - record.attempts,
    resetTime: record.resetTime,
  };
}

/**
 * Middleware factory for rate limiting
 * @param {object} options - Configuration options
 * @returns {function} Express middleware
 */
function createRateLimitMiddleware(options = {}) {
  const {
    windowMs = 60000, // 1 minute
    maxAttempts = 5,
    endpoint = 'api',
    keyGenerator = getRateLimitKey,
  } = options;

  return (req, res, next) => {
    const key = keyGenerator(req, endpoint);
    const result = checkRateLimit(key, maxAttempts, windowMs);

    // Set rate limit headers
    res.set('X-RateLimit-Limit', String(maxAttempts));
    res.set('X-RateLimit-Remaining', String(result.remaining));
    res.set('X-RateLimit-Reset', result.resetTime.toISOString());

    if (!result.allowed) {
      console.warn(`Rate limit exceeded for ${key}. Reset at ${result.resetTime}`);
      return res.status(429).json({
        success: false,
        error: 'Too many requests. Please try again later.',
        retryAfter: Math.ceil((result.resetTime - Date.now()) / 1000),
      });
    }

    next();
  };
}

/**
 * Middleware factory for user-based rate limiting
 * @param {object} options - Configuration options
 * @returns {function} Express middleware that expects req.body.uid or req.body.email
 */
function createUserRateLimitMiddleware(options = {}) {
  const {
    windowMs = 900000, // 15 minutes
    maxAttempts = 10,
    endpoint = 'user-endpoint',
  } = options;

  return (req, res, next) => {
    // Get identifier from various possible locations
    const identifier = req.body?.uid || req.body?.email || req.body?.phoneNumber;

    if (!identifier) {
      // If no identifier found, use IP-based limiting
      const key = getRateLimitKey(req, endpoint);
      const result = checkRateLimit(key, maxAttempts, windowMs);

      res.set('X-RateLimit-Limit', String(maxAttempts));
      res.set('X-RateLimit-Remaining', String(result.remaining));
      res.set('X-RateLimit-Reset', result.resetTime.toISOString());

      if (!result.allowed) {
        console.warn(`Rate limit exceeded for IP ${req.ip}. Reset at ${result.resetTime}`);
        return res.status(429).json({
          success: false,
          error: 'Too many requests. Please try again later.',
          retryAfter: Math.ceil((result.resetTime - Date.now()) / 1000),
        });
      }

      return next();
    }

    // Use user-based limiting
    const key = getUserRateLimitKey(identifier, endpoint);
    const result = checkRateLimit(key, maxAttempts, windowMs);

    res.set('X-RateLimit-Limit', String(maxAttempts));
    res.set('X-RateLimit-Remaining', String(result.remaining));
    res.set('X-RateLimit-Reset', result.resetTime.toISOString());

    if (!result.allowed) {
      console.warn(
        `User rate limit exceeded for ${identifier} on ${endpoint}. Reset at ${result.resetTime}`,
      );
      return res.status(429).json({
        success: false,
        error: 'Too many requests from this account. Please try again later.',
        retryAfter: Math.ceil((result.resetTime - Date.now()) / 1000),
      });
    }

    next();
  };
}

/**
 * Clean up expired rate limit records
 * Should be called periodically (e.g., every 5 minutes)
 */
function cleanupRateLimits() {
  const now = Date.now();
  let cleaned = 0;

  for (const [key, record] of rateLimitStore.entries()) {
    if (now - record.firstAttemptTime > 3600000) { // 1 hour
      rateLimitStore.delete(key);
      cleaned += 1;
    }
  }

  if (cleaned > 0) {
    console.log(`Cleaned up ${cleaned} expired rate limit records`);
  }
}

// Clean up rate limits every 5 minutes
setInterval(cleanupRateLimits, 300000);

module.exports = {
  createRateLimitMiddleware,
  createUserRateLimitMiddleware,
  checkRateLimit,
  getRateLimitKey,
  getUserRateLimitKey,
  cleanupRateLimits,
};
