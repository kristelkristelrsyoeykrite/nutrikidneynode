/**
 * Security Logger Utility
 * Sanitizes sensitive data from logs to prevent exposing health information,
 * credentials, personal identifiers, and other sensitive data.
 */

const SENSITIVE_FIELDS = [
  'password',
  'idToken',
  'refreshToken',
  'sessionToken',
  'code',
  'mfaSecret',
  'mfaTempSecret',
  'secret',
  'token',
  'accessToken',
  'apiKey',
  'apiSecret',
  'privateKey',
  'privateKeyId',
  'credentials',
  'authorizationHeader',
  'uid',
  'userId',
  'email',
  'phoneNumber',
  'phone',
  // Health-sensitive fields
  'medications',
  'labValues',
  'medicalHistory',
  'diagnosis',
  'prescription',
  'healthData',
  'bloodPressure',
  'bloodGlucose',
  'kidneyFunction',
  'creatinine',
  'egfr',
  'phosphorus',
  'potassium',
  'sodium',
  'fluid_limit_ml',
  'fluidLimitMl',
  'ocrText',
];

/**
 * Recursively sanitize an object, removing or redacting sensitive fields
 * @param {*} obj - Object to sanitize
 * @param {string} depth - Current depth (to prevent infinite recursion)
 * @returns {*} Sanitized object
 */
function sanitize(obj, depth = 0) {
  if (depth > 10) return '[REDACTED_DEEP_NESTING]';
  if (obj === null || obj === undefined) return obj;

  // Handle primitives
  if (typeof obj !== 'object') return obj;

  // Handle arrays
  if (Array.isArray(obj)) {
    return obj.map((item) => sanitize(item, depth + 1));
  }

  // Handle objects
  const sanitized = {};
  for (const [key, value] of Object.entries(obj)) {
    const lowerKey = String(key).toLowerCase();

    // Check if this key is sensitive
    const isSensitive = SENSITIVE_FIELDS.some((field) =>
      lowerKey.includes(field.toLowerCase())
    );

    if (isSensitive) {
      // Redact sensitive fields
      if (typeof value === 'string' && value.length > 0) {
        sanitized[key] = '[REDACTED]';
      } else if (typeof value === 'number') {
        sanitized[key] = '[REDACTED]';
      } else if (typeof value === 'boolean') {
        sanitized[key] = '[REDACTED]';
      } else {
        sanitized[key] = '[REDACTED]';
      }
    } else if (typeof value === 'object' && value !== null) {
      // Recursively sanitize nested objects
      sanitized[key] = sanitize(value, depth + 1);
    } else {
      sanitized[key] = value;
    }
  }

  return sanitized;
}

/**
 * Log data with sensitive fields redacted
 * @param {string} message - Log message prefix
 * @param {*} data - Data to log (will be sanitized)
 */
function logSafe(message, data) {
  const sanitized = sanitize(data);
  console.log(message, sanitized);
}

/**
 * Create a safe version of request body for logging
 * @param {object} body - Request body
 * @returns {object} Sanitized request body
 */
function sanitizeRequestBody(body) {
  return sanitize(body);
}

/**
 * Create a safe version of data for error logging
 * @param {*} data - Data to sanitize
 * @returns {*} Sanitized data
 */
function sanitizeErrorData(data) {
  if (typeof data === 'string') {
    return data;
  }
  return sanitize(data);
}

module.exports = {
  sanitize,
  logSafe,
  sanitizeRequestBody,
  sanitizeErrorData,
  SENSITIVE_FIELDS,
};
