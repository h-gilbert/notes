#!/bin/bash
# Migration 001: Security Hardening
# Adds new required environment variables for security hardening update
#
# This script is idempotent - safe to run multiple times

set -e

COMPOSE_DIR="/opt/docker/webapps"
COMPOSE_FILE="$COMPOSE_DIR/docker-compose.yml"
ENV_FILE="$COMPOSE_DIR/.env"
BACKUP_DIR="$COMPOSE_DIR/backups"

echo "=== Migration 001: Security Hardening ==="

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Backup current files
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
echo "Creating backups..."
cp "$COMPOSE_FILE" "$BACKUP_DIR/docker-compose.yml.backup_$TIMESTAMP"
cp "$ENV_FILE" "$BACKUP_DIR/.env.backup_$TIMESTAMP"

# --- Update .env file ---
echo "Updating .env..."

# Add NOTES_ALLOWED_ORIGINS if not present
if ! grep -q "^NOTES_ALLOWED_ORIGINS=" "$ENV_FILE"; then
    echo "" >> "$ENV_FILE"
    echo "# Notes App - Allowed Origins (added by migration 001)" >> "$ENV_FILE"
    echo "NOTES_ALLOWED_ORIGINS=https://notes.hamishgilbert.com" >> "$ENV_FILE"
    echo "  Added NOTES_ALLOWED_ORIGINS"
else
    echo "  NOTES_ALLOWED_ORIGINS already exists, skipping"
fi

# --- Update docker-compose.yml ---
echo "Updating docker-compose.yml..."

# Check if ENVIRONMENT is already set for notes-api
if grep -A 20 "notes-api:" "$COMPOSE_FILE" | grep -q "ENVIRONMENT:"; then
    echo "  ENVIRONMENT already configured, skipping compose updates"
else
    echo "  Adding new environment variables to notes-api service..."

    # Use sed to add new environment variables after the PORT line in notes-api
    # This is a targeted replacement that adds the new vars

    # Create a temporary file for the new compose content
    TEMP_FILE=$(mktemp)

    # Use awk for more reliable YAML editing
    awk '
    /^  notes-api:/ { in_notes_api = 1 }
    /^  [a-z]/ && !/^  notes-api:/ { in_notes_api = 0 }

    # When we find PORT in notes-api, add our new variables after it
    in_notes_api && /PORT:.*"8080"/ {
        print
        print "      ENVIRONMENT: \"production\""
        print "      DATABASE_SSL_SKIP_VALIDATION: \"true\"  # Safe for internal Docker networks"
        next
    }

    # Replace old JWT_EXPIRY_HOURS with new format
    in_notes_api && /JWT_EXPIRY_HOURS:/ {
        print "      JWT_EXPIRY_MINUTES: \"60\""
        print "      REFRESH_EXPIRY_HOURS: \"168\""
        next
    }

    # Add ALLOWED_ORIGINS after JWT_SECRET
    in_notes_api && /JWT_SECRET:/ {
        print
        print "      ALLOWED_ORIGINS: ${NOTES_ALLOWED_ORIGINS}"
        next
    }

    { print }
    ' "$COMPOSE_FILE" > "$TEMP_FILE"

    # Verify the temp file is valid (not empty and has content)
    if [ -s "$TEMP_FILE" ]; then
        mv "$TEMP_FILE" "$COMPOSE_FILE"
        echo "  docker-compose.yml updated successfully"
    else
        rm -f "$TEMP_FILE"
        echo "  ERROR: Failed to update docker-compose.yml, backup restored"
        exit 1
    fi
fi

echo ""
echo "=== Migration 001 Complete ==="
echo "Backups saved to: $BACKUP_DIR"
echo ""
echo "Please verify the changes:"
echo "  cat $ENV_FILE | grep NOTES_"
echo "  grep -A 15 'notes-api:' $COMPOSE_FILE"
