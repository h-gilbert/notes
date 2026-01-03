# Build stage
FROM node:20-alpine AS builder

# Accept build argument for API URL
ARG NUXT_PUBLIC_API_BASE

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci

# Copy source code
COPY . .

# Build static site
ENV NUXT_PUBLIC_API_BASE=${NUXT_PUBLIC_API_BASE}
RUN npm run generate

# Production stage - serve with nginx
FROM nginx:alpine AS production

# Install wget for health checks
RUN apk add --no-cache wget

# Copy built static files
COPY --from=builder /app/.output/public /usr/share/nginx/html

# Copy nginx configuration
COPY nginx.docker.conf /etc/nginx/conf.d/default.conf

# Expose port
EXPOSE 80

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:80 || exit 1

# Start nginx
CMD ["nginx", "-g", "daemon off;"]
