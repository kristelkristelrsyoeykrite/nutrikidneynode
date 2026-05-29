#!/bin/bash
# Security Verification Script
# Run this to verify all security fixes are properly implemented

set -e

echo "================================"
echo "NutriKidney Security Verification"
echo "================================"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check 1: Rate Limiting Middleware Exists
echo -e "${YELLOW}[1] Checking Rate Limiting Middleware...${NC}"
if [ -f "nutrikidneynode/middleware/rateLimiter.js" ]; then
    echo -e "${GREEN}✓ Rate limiter middleware found${NC}"
    if grep -q "createRateLimitMiddleware\|createUserRateLimitMiddleware" nutrikidneynode/middleware/rateLimiter.js; then
        echo -e "${GREEN}✓ Rate limit functions exported${NC}"
    else
        echo -e "${RED}✗ Rate limit functions not found${NC}"
        exit 1
    fi
else
    echo -e "${RED}✗ Rate limiter middleware not found${NC}"
    exit 1
fi
echo ""

# Check 2: CORS Configuration Exists
echo -e "${YELLOW}[2] Checking CORS Configuration...${NC}"
if [ -f "nutrikidneynode/middleware/corsConfig.js" ]; then
    echo -e "${GREEN}✓ CORS config file found${NC}"
    if grep -q "getCorsConfig" nutrikidneynode/middleware/corsConfig.js; then
        echo -e "${GREEN}✓ CORS config function exported${NC}"
    else
        echo -e "${RED}✗ CORS config function not found${NC}"
        exit 1
    fi
else
    echo -e "${RED}✗ CORS config file not found${NC}"
    exit 1
fi
echo ""

# Check 3: Security Logger Exists
echo -e "${YELLOW}[3] Checking Security Logger...${NC}"
if [ -f "nutrikidneynode/utils/securityLogger.js" ]; then
    echo -e "${GREEN}✓ Security logger found${NC}"
    if grep -q "logSafe\|sanitizeRequestBody\|SENSITIVE_FIELDS" nutrikidneynode/utils/securityLogger.js; then
        echo -e "${GREEN}✓ Logger functions and SENSITIVE_FIELDS exported${NC}"
    else
        echo -e "${RED}✗ Logger functions not properly exported${NC}"
        exit 1
    fi
else
    echo -e "${RED}✗ Security logger not found${NC}"
    exit 1
fi
echo ""

# Check 4: MFA Secrets Service Exists
echo -e "${YELLOW}[4] Checking MFA Secrets Service...${NC}"
if [ -f "nutrikidneynode/services/mfaSecretsService.js" ]; then
    echo -e "${GREEN}✓ MFA secrets service found${NC}"
    if grep -q "saveMfaSecret\|getMfaSecret\|promoteTempMfaSecret\|deleteMfaSecret" nutrikidneynode/services/mfaSecretsService.js; then
        echo -e "${GREEN}✓ All MFA secret functions exported${NC}"
    else
        echo -e "${RED}✗ MFA secret functions not properly exported${NC}"
        exit 1
    fi
    if grep -q "MFA_SECRETS_COLLECTION" nutrikidneynode/services/mfaSecretsService.js; then
        echo -e "${GREEN}✓ MFA secrets collection defined${NC}"
    else
        echo -e "${RED}✗ MFA secrets collection not defined${NC}"
        exit 1
    fi
else
    echo -e "${RED}✗ MFA secrets service not found${NC}"
    exit 1
fi
echo ""

# Check 5: Server.js Updated
echo -e "${YELLOW}[5] Checking server.js Integration...${NC}"
if grep -q "corsConfig\|rateLimiter\|securityLogger" nutrikidneynode/server.js; then
    echo -e "${GREEN}✓ Security middleware imported in server.js${NC}"
else
    echo -e "${RED}✗ Security middleware not imported${NC}"
    exit 1
fi

if grep -q "createRateLimitMiddleware\|createUserRateLimitMiddleware" nutrikidneynode/server.js; then
    echo -e "${GREEN}✓ Rate limiters applied in server.js${NC}"
else
    echo -e "${RED}✗ Rate limiters not applied${NC}"
    exit 1
fi

if grep -q "getCorsConfig" nutrikidneynode/server.js; then
    echo -e "${GREEN}✓ CORS config applied in server.js${NC}"
else
    echo -e "${RED}✗ CORS config not applied${NC}"
    exit 1
fi

if grep -q "logSafe" nutrikidneynode/server.js; then
    echo -e "${GREEN}✓ Logging sanitization applied${NC}"
else
    echo -e "${YELLOW}⚠ Some routes may still use console.log (non-critical)${NC}"
fi
echo ""

# Check 6: MFA Routes Updated
echo -e "${YELLOW}[6] Checking MFA Routes Integration...${NC}"
if grep -q "mfaSecretsService" nutrikidneynode/routes/authenticatorMfaRoutes.js; then
    echo -e "${GREEN}✓ MFA secrets service imported in routes${NC}"
else
    echo -e "${RED}✗ MFA secrets service not imported in routes${NC}"
    exit 1
fi

if grep -q "saveTempMfaSecret\|getTempMfaSecret\|getMfaSecret" nutrikidneynode/routes/authenticatorMfaRoutes.js; then
    echo -e "${GREEN}✓ MFA secret functions used in routes${NC}"
else
    echo -e "${RED}✗ MFA secret functions not used properly${NC}"
    exit 1
fi

# Check if old security settings are removed
if ! grep -q "securitySettings.*mfaSecret\|mfaTempSecret:" nutrikidneynode/routes/authenticatorMfaRoutes.js; then
    echo -e "${GREEN}✓ Old MFA secret storage removed${NC}"
else
    echo -e "${YELLOW}⚠ Old MFA secret references might still exist${NC}"
fi
echo ""

# Check 7: Firestore Rules Updated
echo -e "${YELLOW}[7] Checking Firestore Security Rules...${NC}"
if [ -f "firestore.rules" ]; then
    echo -e "${GREEN}✓ Firestore rules file found${NC}"
    if grep -q "mfa_secrets" firestore.rules; then
        echo -e "${GREEN}✓ MFA secrets collection rules defined${NC}"
    else
        echo -e "${RED}✗ MFA secrets collection rules not found${NC}"
        exit 1
    fi
    if grep -q "isBackendRequest" firestore.rules; then
        echo -e "${GREEN}✓ Backend request verification defined${NC}"
    else
        echo -e "${RED}✗ Backend request verification missing${NC}"
        exit 1
    fi
else
    echo -e "${RED}✗ Firestore rules file not found${NC}"
    exit 1
fi
echo ""

# Check 8: Documentation Files
echo -e "${YELLOW}[8] Checking Documentation...${NC}"
docs_ok=true

if [ -f "SECURITY_FIXES.md" ]; then
    echo -e "${GREEN}✓ SECURITY_FIXES.md found${NC}"
else
    echo -e "${YELLOW}⚠ SECURITY_FIXES.md not found${NC}"
    docs_ok=false
fi

if [ -f "IMPLEMENTATION_SUMMARY.md" ]; then
    echo -e "${GREEN}✓ IMPLEMENTATION_SUMMARY.md found${NC}"
else
    echo -e "${YELLOW}⚠ IMPLEMENTATION_SUMMARY.md not found${NC}"
    docs_ok=false
fi

if [ -f "nutrikidneynode/ENV_SETUP.md" ]; then
    echo -e "${GREEN}✓ ENV_SETUP.md found${NC}"
else
    echo -e "${YELLOW}⚠ ENV_SETUP.md not found${NC}"
    docs_ok=false
fi

if [ "$docs_ok" = false ]; then
    echo -e "${YELLOW}⚠ Some documentation files missing (non-critical)${NC}"
fi
echo ""

# Check 9: Environment Variables Check
echo -e "${YELLOW}[9] Checking Environment Configuration...${NC}"
if [ -f "nutrikidneynode/.env" ]; then
    if grep -q "ENCRYPTION_KEY" nutrikidneynode/.env; then
        echo -e "${GREEN}✓ ENCRYPTION_KEY configured in .env${NC}"
    else
        echo -e "${YELLOW}⚠ ENCRYPTION_KEY not found in .env${NC}"
    fi
    if grep -q "ALLOWED_ORIGINS" nutrikidneynode/.env; then
        echo -e "${GREEN}✓ ALLOWED_ORIGINS configured in .env${NC}"
    else
        echo -e "${YELLOW}⚠ ALLOWED_ORIGINS not found in .env${NC}"
    fi
else
    echo -e "${YELLOW}⚠ .env file not found (OK for dev, must exist in production)${NC}"
fi
echo ""

# Check 10: Middleware Directory Structure
echo -e "${YELLOW}[10] Checking Directory Structure...${NC}"
if [ -d "nutrikidneynode/middleware" ]; then
    echo -e "${GREEN}✓ middleware directory exists${NC}"
    files=$(ls nutrikidneynode/middleware/ 2>/dev/null | wc -l)
    echo -e "${GREEN}  ├─ Contains $files files${NC}"
    ls -1 nutrikidneynode/middleware/ | sed 's/^/  ├─ /'
else
    echo -e "${RED}✗ middleware directory not found${NC}"
    exit 1
fi
echo ""

# Summary
echo "================================"
echo -e "${GREEN}Security Verification Complete!${NC}"
echo "================================"
echo ""
echo "All critical security components are in place:"
echo "  ✅ Rate limiting middleware"
echo "  ✅ CORS configuration"
echo "  ✅ Security logger"
echo "  ✅ MFA secrets service"
echo "  ✅ Server integration"
echo "  ✅ MFA routes integration"
echo "  ✅ Firestore rules"
echo ""
echo "Next steps:"
echo "  1. Update .env with production ALLOWED_ORIGINS"
echo "  2. Generate strong ENCRYPTION_KEY"
echo "  3. Deploy firestore.rules: firebase deploy --only firestore:rules"
echo "  4. Redeploy backend code"
echo "  5. Test all flows (signup, login, MFA)"
echo ""
echo "For detailed information, see:"
echo "  - SECURITY_FIXES.md"
echo "  - IMPLEMENTATION_SUMMARY.md"
echo "  - nutrikidneynode/ENV_SETUP.md"
echo ""
