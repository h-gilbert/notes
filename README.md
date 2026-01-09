# Notes App

A real-time notes application with cross-platform support. Features a Nuxt 3 web frontend, native iOS app, and Go backend with WebSocket synchronization.

## Features

- **Real-time Sync** - Changes sync instantly across all devices via WebSocket
- **Multiple Note Types** - Support for text notes and checklists
- **Cross-platform** - Web app and native iOS app
- **Secure Authentication** - JWT-based auth with access/refresh tokens
- **Offline Support** - Notes persist locally and sync when online

## Tech Stack

| Component | Technology |
|-----------|------------|
| Backend | Go 1.24, Gin framework |
| Web Frontend | Nuxt 3 (Vue 3), TypeScript |
| iOS App | SwiftUI, SwiftData |
| Database | PostgreSQL 15 |
| Real-time | WebSocket |
| Containerization | Docker, Docker Compose |

## Quick Start

### Prerequisites

- Go 1.21+
- Node.js 18+
- Docker & Docker Compose
- PostgreSQL 15 (or use Docker)

### Development Setup

1. **Clone the repository**
   ```bash
   git clone https://github.com/yourusername/notes-app.git
   cd notes-app
   ```

2. **Start the database**
   ```bash
   cd backend
   docker-compose up db -d
   ```

3. **Configure environment**
   ```bash
   # Backend
   cp backend/.env.example backend/.env

   # Frontend
   cp web/.env.example web/.env
   ```

4. **Start the backend**
   ```bash
   cd backend
   go run cmd/api/main.go
   ```

5. **Start the frontend** (in a new terminal)
   ```bash
   cd web
   npm install
   npm run dev
   ```

6. **Open the app**
   - Web: http://localhost:3030
   - API: http://localhost:8088

### Docker Mode

Run the entire stack with Docker:

```bash
cd backend
docker-compose up
```

## Project Structure

```
notes-app/
├── backend/                 # Go API server
│   ├── cmd/server/          # Application entrypoint
│   ├── internal/
│   │   ├── config/          # Configuration management
│   │   ├── handlers/        # HTTP & WebSocket handlers
│   │   ├── middleware/      # Auth, CORS, rate limiting
│   │   ├── models/          # Data models
│   │   ├── repository/      # Database operations
│   │   ├── services/        # Business logic
│   │   └── websocket/       # Real-time sync
│   └── docker-compose.yml
├── web/                     # Nuxt 3 frontend
│   ├── components/          # Vue components
│   ├── composables/         # Composition API utilities
│   ├── pages/               # Route pages
│   ├── stores/              # Pinia state management
│   └── utils/               # Helper functions
├── ios/                     # Native iOS app
│   └── Notes/
│       ├── Models/          # SwiftData models
│       ├── Services/        # API & sync services
│       ├── Views/           # SwiftUI views
│       └── Utilities/       # Helpers & extensions
└── deploy/                  # Deployment configurations
```

## Configuration

### Backend Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `PORT` | Server port | `8080` |
| `DATABASE_URL` | PostgreSQL connection string | Required |
| `JWT_SECRET` | Secret for signing JWTs | Required in production |
| `JWT_EXPIRY_MINUTES` | Access token lifetime | `60` |
| `REFRESH_EXPIRY_HOURS` | Refresh token lifetime | `168` |
| `ALLOWED_ORIGINS` | CORS allowed origins | `http://localhost:3030` |
| `ENVIRONMENT` | `development` or `production` | `development` |

See `backend/.env.example` for full configuration options.

### Frontend Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `NUXT_PUBLIC_API_BASE` | Backend API URL | `http://localhost:8088` |

## API Endpoints

### Authentication
- `POST /api/auth/register` - Create account
- `POST /api/auth/login` - Login
- `POST /api/auth/refresh` - Refresh access token
- `POST /api/auth/logout` - Logout
- `POST /api/auth/change-password` - Change password

### Notes
- `GET /api/notes` - List all notes
- `POST /api/notes` - Create note
- `GET /api/notes/:id` - Get note
- `PUT /api/notes/:id` - Update note
- `DELETE /api/notes/:id` - Delete note

### WebSocket
- `GET /api/ws` - WebSocket connection for real-time sync

### Health
- `GET /health` - Health check endpoint

## Security

This application implements comprehensive security measures:

- JWT authentication with token revocation
- bcrypt password hashing
- Rate limiting with auth-specific stricter limits
- CORS origin validation
- Security headers (HSTS, CSP, X-Frame-Options, etc.)
- Input validation and sanitization
- SQL injection prevention via parameterized queries
- iOS certificate pinning

See [SECURITY.md](SECURITY.md) for the full security policy and production deployment checklist.

## iOS App

The iOS app requires Xcode 15+ and targets iOS 17+.

1. Open `ios/Notes/Notes.xcodeproj` in Xcode
2. Configure the API base URL in `Info.plist` or use the default
3. Build and run on simulator or device

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
