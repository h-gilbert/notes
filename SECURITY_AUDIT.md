# Security Audit Report - Notes App

**Date**: January 2025
**Scope**: Full-stack security audit for public GitHub repository
**Status**: Phase 1 Complete, Phase 2 Complete, Phase 3 Complete, Phase 4 Complete

---

## Executive Summary

This document details the comprehensive security audit and hardening performed on the Notes App, a real-time notes application with a Nuxt 3 frontend, Go/Gin backend, and native iOS app. The goal was to prepare the codebase for public release on GitHub while implementing security best practices.

---

## Table of Contents

1. [Objectives](#objectives)
2. [Initial Findings](#initial-findings)
3. [Completed Fixes](#completed-fixes)
4. [Remaining Work](#remaining-work)
5. [Configuration Guide](#configuration-guide)
6. [Breaking Changes](#breaking-changes)

---

## Objectives

### Primary Goals
1. **Prepare for Public Repository**: Remove sensitive data, secrets, and personal information from the codebase
2. **Implement Security Best Practices**: Harden authentication, authorization, and data handling
3. **Protect Against Common Attacks**: CORS, CSRF, XSS, brute force, injection attacks

### Secondary Goals
1. Improve code quality and maintainability
2. Add comprehensive security documentation
3. Create secure default configurations

---

## Initial Findings

### Critical Issues Found

| Issue | Severity | Location | Status |
|-------|----------|----------|--------|
| CORS wildcard origin (`*`) | Critical | `backend/internal/middleware/cors.go` | ✅ Fixed |
| WebSocket CheckOrigin bypass | Critical | `backend/internal/handlers/websocket.go` | ✅ Fixed |
| Production URL in tracked file | High | `web/.env.production` | ✅ Fixed |
| Weak default JWT secret | High | `backend/internal/config/config.go` | ✅ Fixed |
| JWT tokens in UserDefaults (iOS) | High | `ios/Notes/Notes/Services/AuthService.swift` | ✅ Fixed |
| No rate limiting | High | `backend/cmd/server/main.go` | ✅ Fixed |
| Weak password requirements (6 chars) | Medium | `backend/internal/models/dto.go` | ✅ Fixed |
| Missing security headers | Medium | Backend middleware | ✅ Fixed |
| Long JWT expiry (7 days) | Medium | `backend/internal/config/config.go` | ✅ Fixed |
| Debug logging in production (iOS) | Medium | Multiple iOS files | ✅ Fixed |
| No input validation | Medium | `backend/internal/handlers/notes.go` | ✅ Fixed |
| Hardcoded production URL (iOS) | Medium | `ios/Notes/Notes/Utilities/Constants.swift` | ✅ Fixed |

### Information Disclosure Found

| Item | Location | Status |
|------|----------|--------|
| Production domain exposed | `web/.env.production`, CI/CD workflows | ✅ Removed from tracking |
| Database username in .env | `backend/.env` (local only) | ✅ Not tracked |
| Deployment paths exposed | `deploy/README.md`, nginx configs | ⚠️ Acceptable (needed for docs) |
| GitHub username in configs | Various files | ⚠️ Acceptable (public info) |

---

## Completed Fixes

### Phase 1: Repository Cleanup (Commit: a4d1886)

#### Files Removed from Tracking
- `web/.env.production` - Contained production domain

#### .gitignore Updates
- Added iOS `build/` directory
- Added `*.pdf` files
- Added `commands.txt`
- Updated backend to ignore `.env.*` files

#### New Files Created
- `web/.env.production.example` - Template for production config
- `backend/internal/middleware/security.go` - Security headers middleware
- `SECURITY.md` - Security documentation

### Phase 3: Token Revocation & Database SSL (Pending Commit)

#### Token Revocation System
```
File: backend/internal/database/postgres.go
- Added token_blacklist table with indexes
- Stores revoked token IDs with expiry times
- Supports "revoke all" markers for logout-everywhere

File: backend/internal/repository/token_blacklist_repo.go (NEW)
- RevokeToken(): Add specific token to blacklist
- IsTokenRevoked(): Check if token is revoked
- RevokeAllUserTokens(): Revoke all tokens for a user
- CleanupExpired(): Remove expired entries (runs hourly)

File: backend/internal/services/auth_service.go
- checkTokenRevoked(): Validates tokens against blacklist
- Token rotation: Old refresh tokens revoked on refresh
- Logout(): Revokes access + refresh tokens
- LogoutAll(): Revokes all user tokens (logout everywhere)

File: backend/internal/handlers/auth.go
- POST /api/auth/logout: Revoke current tokens
- POST /api/auth/logout-all: Revoke all user tokens (requires auth)
```

#### Database SSL Validation
```
File: backend/internal/config/config.go
- Production rejects sslmode=disable by default
- DATABASE_SSL_SKIP_VALIDATION=true for internal Docker networks
- Clear error messages with remediation guidance

File: backend/docker-compose.prod.yml, deploy/docker-compose.services.yml
- ENVIRONMENT=production set
- DATABASE_SSL_SKIP_VALIDATION=true for internal networks
- Documentation comments for external DB configuration
```

#### iOS Certificate Pinning
```
File: ios/Notes/Notes/Utilities/CertificatePinning.swift (NEW)
- Public key pinning (survives cert renewals)
- SHA256 hash of server's public key
- Validates entire certificate chain
- Configurable via Info.plist:
  - PINNED_PUBLIC_KEY_HASHES: Array of base64 hashes
  - PINNED_DOMAINS: Domains to pin (empty = all HTTPS)
- Automatically disabled in DEBUG builds

File: ios/Notes/Notes/Services/APIClient.swift
- URLSession now uses CertificatePinningDelegate
- All HTTP requests protected by pinning

File: ios/Notes/Notes/Services/WebSocketService.swift
- WebSocket URLSession uses CertificatePinningDelegate
- WSS connections protected by pinning

To generate public key hash:
  openssl s_client -connect domain.com:443 2>/dev/null | \
    openssl x509 -pubkey -noout | openssl pkey -pubin -outform der | \
    openssl dgst -sha256 -binary | base64
```

#### WebSocket Token via Subprotocol
```
Previously: Token passed as query parameter (/api/ws?token=xxx)
Now: Token passed via Sec-WebSocket-Protocol header

Security benefits:
- Query params are logged by proxies, servers, and appear in browser history
- Sec-WebSocket-Protocol is part of the upgrade headers, not the URL
- Not logged by default in most server configurations

File: backend/internal/handlers/websocket.go
- Supports Sec-WebSocket-Protocol: "access_token, <token>"
- Falls back to Authorization header and query param (with warning)
- Responds with Sec-WebSocket-Protocol: "access_token" to confirm

File: web/composables/useWebSocket.ts
- Uses WebSocket(url, ["access_token", token]) for subprotocol auth

File: ios/Notes/Notes/Services/WebSocketService.swift
- Sets Sec-WebSocket-Protocol header on URLRequest
- Format: "access_token, <token>"
```

### Phase 2: Security Hardening (Commit: 19ef286)

#### Backend Changes

**1. Authentication Overhaul**
```
File: backend/internal/services/auth_service.go
- Implemented access/refresh token pair system
- Access tokens: 1 hour expiry (configurable)
- Refresh tokens: 7 days expiry (configurable)
- Added typed JWT claims with proper validation
- Added security logging for all auth events
```

**2. Configuration Hardening**
```
File: backend/internal/config/config.go
- JWT_SECRET required in production (fails startup if missing)
- JWT_SECRET must be 32+ characters in production
- ALLOWED_ORIGINS required in production
- Added configurable rate limits
- Added configurable request size limits
```

**3. Rate Limiting**
```
File: backend/internal/middleware/ratelimit.go (NEW)
- General rate limiting: 100 requests/minute (configurable)
- Auth rate limiting: 5 requests/minute with lockout
- IP-based tracking with automatic cleanup
- 15-minute lockout after 5 failed attempts
```

**4. Input Validation**
```
File: backend/internal/models/dto.go
- Password: 12-128 characters (was 6+)
- Username: 3-50 alphanumeric characters
- Note title: max 500 characters
- Note content: max 100,000 characters
- Checklist item text: max 1,000 characters
- Note type enum validation
```

**5. Security Headers**
```
File: backend/internal/middleware/security.go
- X-Content-Type-Options: nosniff
- X-Frame-Options: DENY
- X-XSS-Protection: 1; mode=block
- Referrer-Policy: strict-origin-when-cross-origin
- Permissions-Policy: geolocation=(), microphone=(), camera=()
```

**6. CORS Hardening**
```
File: backend/internal/middleware/cors.go
- Removed wildcard origin (*)
- Origins validated against ALLOWED_ORIGINS env var
- Proper credential handling
```

#### Frontend Changes

**1. Token Management**
```
File: web/stores/auth.ts
- Separate access_token and refresh_token handling
- Automatic token refresh scheduling (5 min before expiry)
- Secure cookie options (Secure, SameSite=Strict)
```

**2. API Updates**
```
File: web/utils/api.ts
- Updated refresh endpoint to send refresh_token in body
```

**3. Type Updates**
```
File: web/types/index.ts
- AuthResponse now includes access_token, refresh_token, expires_in
- Added RefreshRequest type
```

#### iOS Changes

**1. Keychain Storage**
```
File: ios/Notes/Notes/Utilities/KeychainHelper.swift (NEW)
- Secure token storage using iOS Keychain
- kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly protection
- Replaces insecure UserDefaults storage
```

**2. Auth Service Updates**
```
File: ios/Notes/Notes/Services/AuthService.swift
- Uses KeychainHelper for token storage
- Handles access/refresh token pair
- Proper token refresh scheduling
- #if DEBUG guards on sensitive logging
```

**3. Debug Logging**
```
File: ios/Notes/Notes/Utilities/DebugLog.swift (NEW)
- debugLog(), wsLog(), authLog(), syncLog() helpers
- All wrapped in #if DEBUG
```

**4. Configurable API URL**
```
File: ios/Notes/Notes/Utilities/Constants.swift
- API URL determined by build configuration
- DEBUG: Uses localhost
- RELEASE: Reads from Info.plist API_BASE_URL key
```

### Phase 4: Final Security Enhancements (Commit: pending)

#### Password Complexity Validation
```
File: backend/internal/validation/password.go (NEW)
- Minimum 12 characters
- At least one uppercase letter
- At least one lowercase letter
- At least one digit
- At least one special character (!@#$%^&*()_+-=[]{}|;':\",./<>?`~)
- Configurable requirements via PasswordRequirements struct

File: backend/internal/services/auth_service.go
- Register() validates password complexity before creating user
- ChangePassword() validates new password complexity
- Added ErrWeakPassword error type

File: backend/internal/handlers/auth.go
- Updated error messages with detailed password requirements

File: backend/internal/models/dto.go
- Password minimum length updated from 6 to 12 characters
```

#### CSRF Token Protection
```
File: backend/internal/middleware/csrf.go (NEW)
- Double-submit cookie pattern implementation
- Cryptographically secure token generation (32 bytes)
- Token stored in cookie (csrf_token) and validated via header (X-CSRF-Token)
- Configurable exempt paths (login, register, refresh, WebSocket)
- Configurable exempt methods (GET, HEAD, OPTIONS)
- Automatic token cleanup for expired entries
- Production mode uses Secure cookies with SameSite=Strict

File: backend/cmd/server/main.go
- CSRF middleware integrated into global middleware stack
```

#### Audit Logging
```
File: backend/internal/middleware/audit.go (NEW)
- Structured audit log entries with:
  - Timestamp, UserID, Action, Resource, ResourceID
  - ClientIP, UserAgent, StatusCode, Duration
- HTTP method to action mapping (POST=CREATE, GET=READ, PUT/PATCH=UPDATE, DELETE=DELETE)
- Separate auth event logging (LogAuthEvent)
- Separate sync event logging (LogSyncEvent)

File: backend/cmd/server/main.go
- Audit middleware applied to /api/notes routes
- All CRUD operations now logged
```

#### Dependency Scanning
```
File: .github/dependabot.yml (NEW)
- Go modules scanning (backend)
- npm scanning (web frontend)
- GitHub Actions scanning
- Weekly schedule (Mondays)
- Auto-grouping of minor/patch updates
- Commit message prefixes for organization
```

#### Security CI/CD Pipeline
```
File: .github/workflows/security.yml (NEW)
- govulncheck for Go vulnerability scanning
- go vet for static analysis
- npm audit for JavaScript dependencies
- CodeQL analysis for both Go and JavaScript
- TruffleHog for secrets scanning
- Runs on push, PR, and weekly schedule
```

---

## Remaining Work

### High Priority

| Task | Description | Effort | Status |
|------|-------------|--------|--------|
| **Database SSL** | Change default `sslmode=disable` to `sslmode=require` for production | Low | ✅ Done |
| **Token Revocation** | Implement token blacklist for logout/password change | Medium | ✅ Done |
| **iOS Certificate Pinning** | Add SSL pinning for production API domain | Medium | ✅ Done |

### Medium Priority

| Task | Description | Effort | Status |
|------|-------------|--------|--------|
| **WebSocket Token in Header** | Move token from query param to WebSocket subprotocol | Medium | ✅ Done |
| **CSRF Tokens** | Add explicit CSRF protection beyond SameSite cookies | Medium | ✅ Done |
| **Audit Logging** | Log note CRUD operations for compliance | Low | ✅ Done |

### Low Priority

| Task | Description | Effort | Status |
|------|-------------|--------|--------|
| **Dependency Scanning** | Enable GitHub Dependabot | Low | ✅ Done |
| **Go Vulnerability Scanning** | Add govulncheck to CI/CD | Low | ✅ Done |
| **Password Complexity** | Add uppercase/lowercase/number/symbol requirements | Low | ✅ Done |

### Infrastructure (Outside Codebase)

| Task | Description |
|------|-------------|
| Rotate any potentially exposed secrets | JWT secrets, database passwords |
| Configure production environment variables | See Configuration Guide below |
| Enable HTTPS with valid certificates | Required for Secure cookies |
| Set up monitoring/alerting | For rate limit hits, auth failures |

---

## Configuration Guide

### Required Environment Variables (Production)

```bash
# REQUIRED - Server will not start without these
ENVIRONMENT=production
JWT_SECRET=<generate-with: openssl rand -base64 32>
ALLOWED_ORIGINS=https://your-frontend-domain.com
DATABASE_URL=postgres://user:password@host:5432/notes?sslmode=require
```

### Optional Environment Variables

```bash
# Token Expiry
JWT_EXPIRY_MINUTES=60           # Access token lifetime (default: 60)
REFRESH_EXPIRY_HOURS=168        # Refresh token lifetime (default: 168 = 7 days)

# Rate Limiting
RATE_LIMIT_REQUESTS=100         # Requests per minute (default: 100)
RATE_LIMIT_BURST=20             # Burst size (default: 20)

# Request Limits
MAX_REQUEST_BODY_MB=10          # Max request body in MB (default: 10)

# Server
PORT=8080                       # Server port (default: 8080)
```

### iOS Production Configuration

Add to your Xcode project's Info.plist or build settings:

```xml
<!-- API Base URL -->
<key>API_BASE_URL</key>
<string>https://your-api-domain.com</string>

<!-- Certificate Pinning (optional but recommended) -->
<key>PINNED_PUBLIC_KEY_HASHES</key>
<array>
    <string>YOUR_BASE64_SHA256_HASH_HERE</string>
</array>
<key>PINNED_DOMAINS</key>
<array>
    <string>your-api-domain.com</string>
</array>
```

To generate your server's public key hash:
```bash
openssl s_client -connect your-domain.com:443 -servername your-domain.com 2>/dev/null | \
  openssl x509 -pubkey -noout | openssl pkey -pubin -outform der | \
  openssl dgst -sha256 -binary | base64
```

### Generating Secrets

```bash
# Generate JWT secret (32+ characters required)
openssl rand -base64 32

# Generate database password
openssl rand -base64 24
```

---

## Breaking Changes

### API Response Format

The authentication endpoints now return a different response format:

**Before:**
```json
{
  "token": "eyJhbGc...",
  "user": { "id": "...", "username": "..." }
}
```

**After:**
```json
{
  "access_token": "eyJhbGc...",
  "refresh_token": "eyJhbGc...",
  "expires_in": 3600,
  "token_type": "Bearer",
  "user": { "id": "...", "username": "..." }
}
```

### Token Refresh Endpoint

**Before:** `POST /api/auth/refresh` with Authorization header

**After:** `POST /api/auth/refresh` with body:
```json
{
  "refresh_token": "your-refresh-token"
}
```

### Password Requirements

- **Before**: Minimum 6 characters, no complexity rules
- **After**: Minimum 12 characters with complexity requirements:
  - At least one uppercase letter
  - At least one lowercase letter
  - At least one digit
  - At least one special character

Existing users with shorter or non-compliant passwords will need to update their passwords.

### CSRF Token Requirement

State-changing requests (POST, PUT, PATCH, DELETE) now require a CSRF token:
- Cookie: `csrf_token` (set automatically on first GET request)
- Header: `X-CSRF-Token` (must match cookie value)

Exempt endpoints: `/api/auth/login`, `/api/auth/register`, `/api/auth/refresh`, `/api/ws`

### Username Requirements

- **Before**: 3-50 characters, any characters allowed
- **After**: 3-50 characters, alphanumeric only

### WebSocket Authentication

- **Before**: Token passed as query parameter (`/api/ws?token=xxx`)
- **After**: Token passed via `Sec-WebSocket-Protocol` header

The server still supports query parameters for backward compatibility but logs a security warning.

### New API Endpoints

```
POST /api/auth/logout      - Revoke current access + refresh tokens
POST /api/auth/logout-all  - Revoke ALL tokens for user (requires auth)
```

---

## Deployment Checklist

### Before Deploying

- [ ] Generate new JWT_SECRET with `openssl rand -base64 32`
- [ ] Set `ENVIRONMENT=production`
- [ ] Configure `ALLOWED_ORIGINS` with your frontend domain(s)
- [ ] Update `DATABASE_URL` with `sslmode=require` (or set `DATABASE_SSL_SKIP_VALIDATION=true` for internal Docker networks)
- [ ] Update iOS app with production `API_BASE_URL`
- [ ] Generate and configure iOS certificate pinning hashes (optional but recommended)
- [ ] Test login/register with new password requirements
- [ ] Test token refresh flow
- [ ] Test logout functionality

### After Deploying

- [ ] Verify security headers with [securityheaders.com](https://securityheaders.com)
- [ ] Test rate limiting is working
- [ ] Test WebSocket connections with new subprotocol auth
- [ ] Monitor logs for auth failures and revoked token usage
- [ ] Enable GitHub Dependabot
- [ ] Run `npm audit` and `govulncheck`

---

## Commits Summary

| Commit | Description |
|--------|-------------|
| `a4d1886` | Phase 1: Security audit - Fix CORS, add security headers, remove exposed secrets |
| `19ef286` | Phase 2: Implement comprehensive security hardening |
| *pending* | Phase 3: Token revocation, database SSL, iOS cert pinning, WebSocket auth |
| *pending* | Phase 4: Password complexity, CSRF protection, audit logging, Dependabot, govulncheck |

---

## Files Changed Summary

### New Files - Phase 1 & 2
- `SECURITY.md`
- `SECURITY_AUDIT.md` (this document)
- `backend/internal/middleware/ratelimit.go`
- `backend/internal/middleware/security.go`
- `ios/Notes/Notes/Utilities/KeychainHelper.swift`
- `ios/Notes/Notes/Utilities/DebugLog.swift`
- `web/.env.production.example`

### New Files - Phase 3
- `backend/internal/repository/token_blacklist_repo.go` - Token revocation repository
- `ios/Notes/Notes/Utilities/CertificatePinning.swift` - iOS SSL certificate pinning
- `deploy/migrations/001-security-hardening.sh` - CI/CD migration script

### New Files - Phase 4
- `backend/internal/validation/password.go` - Password complexity validation
- `backend/internal/middleware/csrf.go` - CSRF token protection middleware
- `backend/internal/middleware/audit.go` - Audit logging middleware
- `.github/dependabot.yml` - Dependabot configuration for dependency scanning
- `.github/workflows/security.yml` - Security scanning CI/CD workflow (govulncheck, CodeQL, npm audit, TruffleHog)

### Modified Files - Phase 4
- `backend/internal/models/dto.go` - Password minimum length updated to 12 characters
- `backend/internal/services/auth_service.go` - Password complexity validation in Register/ChangePassword
- `backend/internal/handlers/auth.go` - Detailed password requirement error messages
- `backend/cmd/server/main.go` - CSRF middleware and audit logging integration

### Modified Files - Phase 3
- `backend/internal/database/postgres.go` - Added token_blacklist table
- `backend/internal/services/auth_service.go` - Token revocation, logout methods
- `backend/internal/handlers/auth.go` - Logout endpoints
- `backend/internal/handlers/websocket.go` - Subprotocol authentication
- `backend/internal/middleware/auth.go` - Token revocation checks
- `backend/internal/config/config.go` - Database SSL validation
- `backend/internal/models/dto.go` - LogoutRequest DTO
- `backend/cmd/server/main.go` - Blacklist repo, cleanup job, logout routes
- `backend/docker-compose.prod.yml` - Production environment variables
- `deploy/docker-compose.services.yml` - Production environment variables
- `deploy/README.md` - Updated documentation
- `.github/workflows/deploy-backend.yml` - CI/CD migration step
- `web/composables/useWebSocket.ts` - Subprotocol authentication
- `ios/Notes/Notes/Services/APIClient.swift` - Certificate pinning delegate
- `ios/Notes/Notes/Services/WebSocketService.swift` - Certificate pinning, subprotocol auth
- `ios/Notes/Notes/Utilities/Constants.swift` - Security documentation

### Modified Files - Phase 1 & 2
- Backend: config, handlers, middleware, models, services
- Frontend: stores, types, utils
- iOS: AuthService, Constants
- Config: .gitignore files, .env examples

### Removed from Tracking
- `web/.env.production`

---

## Contact

For security vulnerabilities, please see [SECURITY.md](./SECURITY.md) for responsible disclosure guidelines.
