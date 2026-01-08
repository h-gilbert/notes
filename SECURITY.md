# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in this project, please report it responsibly:

1. **Do not** create a public GitHub issue for security vulnerabilities
2. Email the maintainer directly with details of the vulnerability
3. Include steps to reproduce the issue
4. Allow reasonable time for a fix before public disclosure

## Security Audit Summary

This document summarizes the security posture of the Notes App and provides recommendations for production deployment.

### Implemented Security Features

The following security measures have been implemented:

| Feature | Status | Details |
|---------|--------|---------|
| CORS Origin Validation | ✅ Implemented | Origins validated against `ALLOWED_ORIGINS` env var |
| WebSocket Origin Check | ✅ Implemented | Origin validated before WebSocket upgrade |
| Security Headers | ✅ Implemented | X-Frame-Options, X-Content-Type-Options, etc. |
| Rate Limiting | ✅ Implemented | General API + stricter auth endpoint limits |
| JWT Access/Refresh Tokens | ✅ Implemented | 1-hour access tokens, 7-day refresh tokens |
| Password Requirements | ✅ Implemented | Minimum 12 characters, alphanumeric usernames |
| Input Validation | ✅ Implemented | Max lengths, note type enum validation |
| Request Size Limits | ✅ Implemented | Configurable via `MAX_REQUEST_BODY_MB` |
| Security Logging | ✅ Implemented | Auth events logged with IP addresses |
| iOS Keychain Storage | ✅ Implemented | Tokens stored securely in iOS Keychain |
| Debug Logging Guards | ✅ Implemented | `#if DEBUG` guards and debug logging utilities |
| Production Secret Validation | ✅ Implemented | Server fails to start without required secrets |
| Frontend Cookie Security | ✅ Implemented | Secure, SameSite=Strict cookies |

### Remaining Recommendations

#### Medium Priority

1. **JWT Token in WebSocket Query Parameter**
   - **Location**: `backend/internal/handlers/websocket.go`, `web/composables/useWebSocket.ts`
   - **Issue**: Token passed in URL query string for WebSocket connections
   - **Mitigation**: Token is validated server-side; use HTTPS in production
   - **Future**: Consider WebSocket subprotocol for auth header support

2. **Token Revocation / Logout**
   - **Current**: Logout clears client tokens; server tokens remain valid until expiry
   - **Recommendation**: Implement token blacklist for immediate revocation

3. **Database SSL**
   - **Current**: `sslmode=disable` in default config
   - **Recommendation**: Use `sslmode=require` for production databases

4. **iOS Certificate Pinning**
   - **Current**: Uses standard iOS TLS validation
   - **Recommendation**: Implement certificate pinning for additional MITM protection

#### Low Priority

1. **CSRF Protection**
   - Current SameSite=Strict cookies provide basic protection
   - Consider adding explicit CSRF tokens for additional security

2. **Audit Trail**
   - Add note modification logging for compliance requirements

## Environment Configuration

### Required for Production

```env
# REQUIRED - Server will fail to start without these in production
ENVIRONMENT=production
JWT_SECRET=<generate-with-openssl-rand-base64-32>
ALLOWED_ORIGINS=https://your-frontend-domain.com

# Database with SSL
DATABASE_URL=postgres://user:pass@host:5432/notes?sslmode=require
```

### Configuration Options

```env
# Token expiry
JWT_EXPIRY_MINUTES=60          # Access token lifetime (default: 60)
REFRESH_EXPIRY_HOURS=168       # Refresh token lifetime (default: 168 = 7 days)

# Rate limiting
RATE_LIMIT_REQUESTS=100        # Requests per minute (default: 100)
RATE_LIMIT_BURST=20            # Burst size (default: 20)

# Request limits
MAX_REQUEST_BODY_MB=10         # Maximum request body size (default: 10MB)
```

### Generating a Secure JWT Secret

```bash
openssl rand -base64 32
```

## API Authentication

The API uses JWT-based authentication with access and refresh tokens:

### Token Response Format

```json
{
  "access_token": "eyJhbGc...",
  "refresh_token": "eyJhbGc...",
  "expires_in": 3600,
  "token_type": "Bearer",
  "user": {
    "id": "uuid",
    "username": "string"
  }
}
```

### Token Refresh

POST `/api/auth/refresh` with body:
```json
{
  "refresh_token": "your-refresh-token"
}
```

## Deployment Checklist

Before deploying to production:

- [x] CORS restricted to specific origins
- [x] Security headers implemented
- [x] Rate limiting enabled
- [x] JWT tokens use short expiry with refresh
- [x] Password requirements enforced (12+ chars)
- [x] Input validation on all endpoints
- [ ] Set `ENVIRONMENT=production`
- [ ] Generate and set strong `JWT_SECRET` (32+ characters)
- [ ] Configure `ALLOWED_ORIGINS` with your frontend domain(s)
- [ ] Enable database SSL (`sslmode=require`)
- [ ] Configure HTTPS/TLS termination (nginx, load balancer)
- [ ] Review and rotate any exposed secrets
- [ ] Enable GitHub Dependabot for dependency scanning
- [ ] Run `npm audit` on frontend dependencies

## Dependency Security

Enable automated dependency scanning:

1. **GitHub Dependabot**: Enable in repository settings
2. **npm audit**: Run `npm audit` in the `web/` directory
3. **Go vulnerabilities**: Run `govulncheck ./...` in the `backend/` directory
