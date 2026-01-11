#!/bin/sh
set -e
# Ensure pgdata and postgresql run directories exist and are writable
mkdir -p /pgdata/data /var/run/postgresql 2>/dev/null || true
chmod -R g+rwX /pgdata /var/run/postgresql 2>/dev/null || true
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

