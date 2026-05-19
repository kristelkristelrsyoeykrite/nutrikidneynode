/**
 * CORS Configuration
 * Restricts allowed origins for better security
 */

/**
 * Get CORS configuration based on environment
 * @returns {object} CORS options
 */
function getCorsConfig() {
  const nodeEnv = process.env.NODE_ENV || 'development';
  const allowedOrigins = (process.env.ALLOWED_ORIGINS || '').split(',').filter(Boolean);

  // Default allowed origins if not configured
  const defaultOrigins = ['http://localhost:3000', 'http://localhost:8080'];

  // Production should explicitly configure allowed origins
  if (nodeEnv === 'production' && allowedOrigins.length === 0) {
    console.warn(
      'WARNING: No ALLOWED_ORIGINS configured in production. CORS is restricted to localhost only.',
    );
  }

  const origins = allowedOrigins.length > 0 ? allowedOrigins : defaultOrigins;

  return {
    origin: (origin, callback) => {
      if (!origin) {
        // Allow non-browser requests (mobile apps, curl, etc.)
        return callback(null, true);
      }

      if (origins.includes(origin)) {
        callback(null, true);
      } else if (nodeEnv === 'development') {
        // Allow any origin in development with warning
        console.warn(`CORS request from unregistered origin: ${origin}`);
        callback(null, true);
      } else {
        // Block in production
        callback(new Error(`Not allowed by CORS: ${origin}`));
      }
    },
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS', 'PATCH'],
    allowedHeaders: ['Content-Type', 'Authorization', 'X-Requested-With'],
    credentials: true,
    maxAge: 3600, // 1 hour
    optionsSuccessStatus: 200,
  };
}

module.exports = {
  getCorsConfig,
};
