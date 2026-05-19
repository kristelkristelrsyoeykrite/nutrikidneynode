# Backend Security Configuration Guide

## Environment Variables (.env files)

### Development Environment (.env)
```bash
# Server Configuration
NODE_ENV=development
PORT=3000

# Firebase Configuration
FIREBASE_PROJECT_ID=nutrikidney-dev
FIREBASE_DATABASE_URL=https://nutrikidney-dev.firebaseio.com

# Security: CORS Whitelist (comma-separated)
# Leave empty to use defaults (localhost)
ALLOWED_ORIGINS=http://localhost:3000,http://localhost:8080,http://127.0.0.1:3000

# Security: Encryption Key (32 bytes in hex format = 64 hex characters)
# Generate: node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
# DO NOT commit this to version control
ENCRYPTION_KEY=<your-dev-encryption-key-here>

# Rate Limiting (optional, can be customized in code)
RATE_LIMIT_WINDOW_MS=900000
RATE_LIMIT_MAX_ATTEMPTS=5

# Email Configuration (if using email sending)
SENDGRID_API_KEY=<optional>
```

### Production Environment (.env.production)
```bash
# Server Configuration
NODE_ENV=production
PORT=3000

# Firebase Configuration
FIREBASE_PROJECT_ID=nutrikidney-prod
FIREBASE_DATABASE_URL=https://nutrikidney-prod.firebaseio.com

# Security: CORS Whitelist (MUST BE CONFIGURED)
# Production MUST have explicit allowed origins
ALLOWED_ORIGINS=https://yourdomain.com,https://app.yourdomain.com,https://admin.yourdomain.com

# Security: Encryption Key (32 bytes in hex format)
# CRITICAL: Use strong, unique key for production
# Store in secure secrets manager, not in this file
ENCRYPTION_KEY=<your-prod-encryption-key-here>

# Rate Limiting
RATE_LIMIT_WINDOW_MS=900000
RATE_LIMIT_MAX_ATTEMPTS=5

# Logging
LOG_LEVEL=info
LOG_FORMAT=json

# Email Configuration
SENDGRID_API_KEY=<your-sendgrid-key>
```

---

## Security Best Practices

### 1. Encryption Key Management
- **Generate Strong Keys**: `node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"`
- **Never Commit**: Add `.env` files to `.gitignore`
- **Use Secrets Manager**: In production, use Google Cloud Secret Manager or AWS Secrets Manager
- **Rotate Keys**: Plan for key rotation strategy
- **Audit Access**: Log who has access to encryption keys

### 2. CORS Configuration
- **Production**: Always specify allowed origins explicitly
- **Never use**: `*` for production
- **Restrict**: Only include origins that actually need API access
- **Monitor**: Log and alert on CORS rejections

### 3. Rate Limiting
- **Adjust Thresholds**: Modify rate limit values based on expected usage
- **Monitor**: Watch for legitimate users hitting limits
- **Scale**: Use Redis for rate limiting across multiple servers

### 4. Logging
- **Sanitization**: All logs use `logSafe()` and `sanitizeRequestBody()`
- **Monitoring**: Set up log aggregation (Google Cloud Logging, Datadog, etc.)
- **Retention**: Keep logs for compliance requirements
- **Review**: Regularly review logs for suspicious activity

---

## Deployment Checklist

### Before Deploying to Production

```bash
# 1. Verify environment variables
cat .env.production | grep -E "ALLOWED_ORIGINS|ENCRYPTION_KEY|NODE_ENV"

# 2. Generate new encryption key
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"

# 3. Update ALLOWED_ORIGINS
# - Add your actual domain(s)
# - Remove localhost entries

# 4. Test rate limiting locally
npm test

# 5. Verify CORS headers
curl -I https://your-api.com/health -H "Origin: https://yourdomain.com"

# 6. Check Firestore rules are updated
firebase deploy --only firestore:rules

# 7. Deploy backend code
git push origin main  # CI/CD deploys automatically
# OR
npm run build && npm run deploy
```

---

## Docker / Container Deployment

### Dockerfile Example
```dockerfile
FROM node:18-alpine

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci --only=production

# Copy application code
COPY . .

# Set environment to production
ENV NODE_ENV=production

# Expose port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
  CMD node -e "require('http').get('http://localhost:3000/health', (r) => {if (r.statusCode !== 200) throw new Error(r.statusCode)})"

# Start server
CMD ["node", "server.js"]
```

### docker-compose.yml Example
```yaml
version: '3.8'

services:
  backend:
    build: .
    ports:
      - "3000:3000"
    environment:
      NODE_ENV: ${NODE_ENV:-production}
      ALLOWED_ORIGINS: ${ALLOWED_ORIGINS}
      ENCRYPTION_KEY: ${ENCRYPTION_KEY}
      FIREBASE_PROJECT_ID: ${FIREBASE_PROJECT_ID}
    volumes:
      - ./logs:/app/logs
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/health"]
      interval: 30s
      timeout: 3s
      retries: 3
      start_period: 40s
```

### Run with Environment File
```bash
# Load from .env.production and run
docker-compose --env-file .env.production up -d
```

---

## Monitoring & Troubleshooting

### Check CORS is Working
```bash
# Should succeed (200)
curl -X OPTIONS https://your-api.com/api/endpoint \
  -H "Origin: https://yourdomain.com" \
  -H "Access-Control-Request-Method: POST" -v

# Should fail (blocked)
curl -X OPTIONS https://your-api.com/api/endpoint \
  -H "Origin: https://evil-site.com" \
  -H "Access-Control-Request-Method: POST" -v
```

### Test Rate Limiting
```bash
# Single request (should succeed)
curl -X POST https://your-api.com/verify-phone-password \
  -H "Content-Type: application/json" \
  -d '{"phoneNumber":"+639123456789","password":"test"}'

# Multiple rapid requests (6th+ should get 429)
for i in {1..10}; do
  curl -X POST https://your-api.com/verify-phone-password \
    -H "Content-Type: application/json" \
    -d '{"phoneNumber":"+639123456789","password":"test"}'
  echo "Attempt $i"
done
```

### View Logs with Sanitization
```bash
# Check logs are properly redacting sensitive data
tail -f logs/app.log | grep -i "password\|token\|secret"
# Should show [REDACTED], not actual values
```

### Check MFA Secret Storage
```bash
# Verify secrets are in separate collection
firebase firestore:query mfa_secrets --database=(default) \
  | grep -v "secret\|mfaTempSecret"
# Secrets should be encrypted, not readable in logs
```

---

## Secrets Management (Advanced)

### Using Google Cloud Secret Manager
```javascript
// Load secrets from Google Cloud Secret Manager
const secretManager = require('@google-cloud/secret-manager');

async function getSecret(secretId) {
  const client = new secretManager.SecretManagerServiceClient();
  const name = client.secretVersionPath(
    process.env.GOOGLE_CLOUD_PROJECT,
    secretId,
    'latest'
  );
  const [version] = await client.accessSecretVersion({ name });
  return version.payload.data.toString('utf8');
}

// Usage
const encryptionKey = await getSecret('encryption-key');
const allowedOrigins = await getSecret('allowed-origins');
```

### Using AWS Secrets Manager
```javascript
// Load secrets from AWS Secrets Manager
const aws = require('aws-sdk');
const secretsManager = new aws.SecretsManager();

async function getSecret(secretName) {
  const params = { SecretId: secretName };
  const result = await secretsManager.getSecretValue(params).promise();
  if (result.SecretString) {
    return result.SecretString;
  }
}

// Usage
const encryptionKey = await getSecret('nutrikidney/encryption-key');
```

---

## Compliance & Audit

### Data Protection
- ✅ Encryption at rest (ENCRYPTION_KEY)
- ✅ Encryption in transit (HTTPS/TLS)
- ✅ Rate limiting (prevents brute force)
- ✅ CORS restrictions (prevents unauthorized access)
- ✅ Log sanitization (prevents data leaks in logs)
- ✅ MFA secrets in protected collection

### Recommended Audits
- [ ] Monthly security review of logs
- [ ] Quarterly penetration testing
- [ ] Annual encryption key rotation
- [ ] Regular dependency updates

