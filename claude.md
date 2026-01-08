# Notes App

## Project Overview
Real-time notes application with Nuxt 3 frontend and Go/Gin backend with WebSocket support.

## Tech Stack
- **Frontend**: Nuxt 3 (Vue 3)
- **Backend**: Go 1.21+, Gin framework
- **Database**: PostgreSQL 15
- **Containerization**: Docker with Docker Compose

## Port Configuration

| Service | Port | Description |
|---------|------|-------------|
| Frontend (Dev) | 3030 | Nuxt dev server |
| Backend API | 8088 | Go/Gin server |
| PostgreSQL | 5438 | Database (external mapping) |

### Production Ports
| Service | Port | Description |
|---------|------|-------------|
| Backend API | 3600 | Production Docker mapping |

## Running Locally

### Development Mode
```bash
# Start database
cd backend && docker-compose up db -d

# Start backend
cd backend && go run cmd/api/main.go

# Start frontend (in another terminal)
cd web && npm run dev
```

### Docker Mode
```bash
cd backend
docker-compose up
```

## Environment Variables

### Backend (backend/.env)
- `PORT`: 8088
- `DATABASE_URL`: postgres://postgres:postgres@localhost:5438/notes?sslmode=disable
- `JWT_SECRET`: your-secret-key
- `JWT_EXPIRATION`: 168h

### Frontend (web/.env)
- `NUXT_PUBLIC_API_BASE`: http://localhost:8088

## Docker Services
- **db**: PostgreSQL 15-alpine on port 5438
- **api**: Go binary on port 8088 (dev) / 3600 (prod)

## Project Structure
```
notes-app/
├── backend/
│   ├── cmd/api/           # Main entry point
│   ├── internal/          # Application logic
│   ├── docker-compose.yml
│   └── docker-compose.prod.yml
└── web/                   # Nuxt 3 frontend
```

## Features
- WebSocket support for real-time sync
- JWT authentication
- Health check endpoints

## Notes
- Frontend port changed from 3000 to 3030 to avoid conflicts
- Database port changed to 5438 for unique allocation
- Backend uses 8088 to avoid conflicts with 8080
