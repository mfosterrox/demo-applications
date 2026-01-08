#!/bin/sh
set -e
# Ensure pgdata directory is writable (directory should already exist from Dockerfile)
chmod -R g+rwX /pgdata 2>/dev/null || true
# Preserve original entrypoint behavior - let PostgreSQL handle initialization
# Check for common PostgreSQL entrypoint locations
if command -v docker-entrypoint.sh >/dev/null 2>&1; then
    exec docker-entrypoint.sh "$@"
elif [ -f /usr/local/bin/docker-entrypoint.sh ]; then
    exec /usr/local/bin/docker-entrypoint.sh "$@"
else
    # Fallback: just run the command
    exec "$@"
fi

