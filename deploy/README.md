# Notes App Deployment Guide

This guide explains how to deploy the Notes App to the Ubuntu server following the migration from Unraid.

## Prerequisites

1. Ubuntu server with Docker and Docker Compose installed
2. Shared PostgreSQL container running (from webapps stack)
3. Nginx reverse proxy configured
4. GHCR access configured (`docker login ghcr.io`)
5. Tailscale configured for CI/CD access

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                          NGINX                                  │
│                    (notes.hamishgilbert.com)                    │
└─────────────┬─────────────────────────────┬─────────────────────┘
              │                             │
          /api/*                           /*
              ▼                             ▼
    ┌─────────────────┐           ┌─────────────────┐
    │   notes-api     │           │  notes-frontend │
    │   (Go/Gin)      │           │  (Nuxt/nginx)   │
    │   Port: 8080    │           │   Port: 80      │
    └────────┬────────┘           └─────────────────┘
             │
             ▼
    ┌─────────────────┐
    │    PostgreSQL   │
    │ (shared, :5432) │
    │  Database: notes│
    └─────────────────┘
```

## Deployment Steps

### 1. Create Notes Database

SSH into the server and create the notes database in the shared PostgreSQL:

```bash
# Create the notes database
docker exec postgres psql -U postgres -c "CREATE DATABASE notes;"
```

The notes-api container will automatically run migrations when it starts.

### 2. Add Environment Variables

Add the following to `/opt/docker/webapps/.env`:

```env
# Notes App JWT Secret (generate with: openssl rand -base64 32)
NOTES_JWT_SECRET=your-very-secure-jwt-secret-here
```

### 3. Add Services to Docker Compose

Add the notes-app services to `/opt/docker/webapps/docker-compose.yml`:

```yaml
  # ===========================================
  # NOTES APP
  # ===========================================
  notes-api:
    image: ghcr.io/h-gilbert/notes-api:latest
    container_name: notes-api
    restart: unless-stopped
    environment:
      PORT: "8080"
      DATABASE_URL: postgresql://postgres:${POSTGRES_PASSWORD}@postgres:5432/notes?sslmode=disable
      JWT_SECRET: ${NOTES_JWT_SECRET}
      JWT_EXPIRY_HOURS: "168"
    depends_on:
      postgres:
        condition: service_healthy
    networks:
      - database-network
      - proxy-network

  notes-frontend:
    image: ghcr.io/h-gilbert/notes-frontend:latest
    container_name: notes-frontend
    restart: unless-stopped
    networks:
      - proxy-network
```

### 4. Deploy Nginx Configuration

Copy the nginx configuration to the server:

```bash
# Copy notes.conf to the nginx conf.d directory
cp deploy/notes.conf /tank/appdata/nginx/conf.d/notes.conf

# Reload nginx
docker exec nginx nginx -s reload
```

### 5. Pull and Start Containers

```bash
cd /opt/docker/webapps

# Pull the images
docker pull ghcr.io/h-gilbert/notes-api:latest
docker pull ghcr.io/h-gilbert/notes-frontend:latest

# Start the containers
docker compose up -d notes-api notes-frontend

# Verify they're running
docker ps --filter "name=notes-"
```

### 6. Verify Deployment

```bash
# Check backend health
curl http://localhost:8080/health

# Check frontend
curl http://localhost:80  # from notes-frontend container

# Check via nginx
curl -k https://notes.hamishgilbert.com/api/health
```

## GitHub Actions Secrets Required

The following secrets must be configured in the GitHub repository:

| Secret | Description |
|--------|-------------|
| `TS_OAUTH_CLIENT_ID` | Tailscale OAuth client ID |
| `TS_OAUTH_SECRET` | Tailscale OAuth secret |
| `SERVER_TAILSCALE_IP` | Server's Tailscale IP (100.x.x.x) |
| `SSH_PRIVATE_KEY` | SSH private key for deployment |

## Database Schema

The notes-api automatically runs migrations on startup. The schema includes:

- **users**: User accounts with username/password
- **notes**: User notes with title, content, type, pinned/archived status
- **checklist_items**: Checklist items within notes

## Restoring from Backup

If restoring from a database backup:

```bash
# Restore notes database from backup
gunzip -c /tank/backups/databases/notes_YYYYMMDD.sql.gz | \
  docker exec -i postgres psql -U postgres -d notes
```

## Troubleshooting

### Backend won't start
```bash
# Check logs
docker logs notes-api --tail 50

# Verify database connection
docker exec notes-api wget --spider http://localhost:8080/health
```

### Frontend 502 errors
```bash
# Verify frontend container is running
docker ps --filter "name=notes-frontend"

# Check nginx can reach frontend
docker exec nginx curl http://notes-frontend:80
```

### WebSocket issues
```bash
# Check nginx WebSocket config
docker exec nginx nginx -T | grep -A5 "ws"

# Test WebSocket connection
curl -v -H "Connection: Upgrade" -H "Upgrade: websocket" \
  https://notes.hamishgilbert.com/api/ws
```

## File Structure

```
deploy/
├── README.md                    # This file
├── notes.conf                   # Nginx configuration
└── docker-compose.services.yml  # Service definitions reference
```
