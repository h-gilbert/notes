# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in this project, please report it responsibly:

1. **Do not** create a public GitHub issue for security vulnerabilities
2. Email the maintainer directly with details of the vulnerability
3. Include steps to reproduce the issue
4. Allow reasonable time for a fix before public disclosure

## Security Audit Summary

This document summarizes the security posture of the Notes App and provides recommendations for production deployment.

### Fixed Issues

The following security issues have been addressed:

| Issue | Severity | Status |
|-------|----------|--------|
| CORS wildcard origin (`*`) | Critical | Fixed |
| WebSocket CheckOrigin bypass | Critical | Fixed |
| Missing security headers | Medium | Fixed |
| Production secrets in repo | High | Fixed |

### Remaining Recommendations

#### High Priority

1. **JWT Token in WebSocket Query Parameter**
   - **Location**: `backend/internal/handlers/websocket.go:47`, `web/composables/useWebSocket.ts:52`
   - **Issue**: Token passed in URL query string, logged in server logs
   - **Recommendation**: Use Authorization header for WebSocket upgrades

2. **Weak Default JWT Secret**
   - **Location**: `backend/internal/config/config.go:36`
   - **Issue**: Default secret is insecure placeholder
   - **Recommendation**: Require JWT_SECRET environment variable, fail to start if not set

3. **Long JWT Expiry (7 days)**
   - **Location**: `backend/internal/config/config.go:37`
   - **Issue**: Extended access window for stolen tokens
   - **Recommendation**: Reduce to 1-2 hours, implement refresh token rotation

4. **iOS Token in UserDefaults**
   - **Location**: `ios/Notes/Notes/Services/AuthService.swift`
   - **Issue**: JWT stored in unencrypted UserDefaults
   - **Recommendation**: Use iOS Keychain with proper access control

5. **No Rate Limiting**
   - **Location**: `backend/cmd/server/main.go`
   - **Issue**: No rate limiting on auth endpoints
   - **Recommendation**: Add rate limiting middleware (5 attempts/15min for login)

6. **Password Requirements Too Weak**
   - **Location**: `backend/internal/models/dto.go:40`
   - **Issue**: Minimum 6 characters
   - **Recommendation**: Increase to 12+ characters or add complexity requirements

#### Medium Priority

1. **No CSRF Protection**
   - Add CSRF tokens for state-changing operations
   - Use SameSite=Strict cookie attribute

2. **Frontend Cookie Security**
   - **Location**: `web/stores/auth.ts:119`
   - **Issue**: Missing HttpOnly, Secure, SameSite flags
   - **Recommendation**: Set secure cookie attributes

3. **No Token Revocation**
   - Implement logout endpoint with token blacklist
   - Revoke tokens on password change

4. **Database SSL Disabled**
   - **Location**: `backend/internal/config/config.go:35`
   - **Issue**: `sslmode=disable` in default connection string
   - **Recommendation**: Use `sslmode=require` in production

5. **Debug Logging in iOS**
   - **Location**: Multiple files in `ios/Notes/Notes/Services/`
   - **Issue**: Print statements leak sensitive data
   - **Recommendation**: Wrap in `#if DEBUG` guards

6. **iOS Certificate Pinning**
   - **Location**: `ios/Notes/Notes/Services/APIClient.swift`
   - **Issue**: No certificate pinning implemented
   - **Recommendation**: Implement SSL pinning for production

#### Low Priority

1. **Input Validation Enhancement**
   - Add max length validation on note content/title
   - Validate NoteType against allowed enum values
   - Add username character restrictions

2. **Security Logging**
   - Log authentication attempts (success/failure)
   - Log authorization failures
   - Implement audit trail for note modifications

3. **Request Size Limits**
   - Set MaxRequestBodySize in server config
   - Enforce consistent limits across HTTP and WebSocket

## Environment Configuration

### Required for Production

```env
# REQUIRED - Must be set in production
ENVIRONMENT=production
JWT_SECRET=<generate-with-openssl-rand-base64-32>
ALLOWED_ORIGINS=https://your-frontend-domain.com

# Database with SSL
DATABASE_URL=postgres://user:pass@host:5432/notes?sslmode=require
```

### Generating a Secure JWT Secret

```bash
openssl rand -base64 32
```

## Deployment Checklist

Before deploying to production:

- [ ] Set `ENVIRONMENT=production`
- [ ] Generate and set strong `JWT_SECRET` (32+ characters)
- [ ] Configure `ALLOWED_ORIGINS` with your frontend domain(s)
- [ ] Enable database SSL (`sslmode=require`)
- [ ] Configure HTTPS/TLS termination (nginx, load balancer)
- [ ] Set up rate limiting at reverse proxy level
- [ ] Review and rotate any exposed secrets
- [ ] Enable GitHub Dependabot for dependency scanning
- [ ] Run `npm audit` on frontend dependencies

## Dependency Security

Enable automated dependency scanning:

1. **GitHub Dependabot**: Enable in repository settings
2. **npm audit**: Run `npm audit` in the `web/` directory
3. **Go vulnerabilities**: Run `govulncheck ./...` in the `backend/` directory
