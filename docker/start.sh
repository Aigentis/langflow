#!/bin/sh

# Start Nginx in the background
nginx -g 'daemon off;' &

# Start Langflow in the foreground
# Ensure all necessary LANGFLOW environment variables are set in Dokploy or the Dockerfile
# (LANGFLOW_DATABASE_URL, LANGFLOW_SECRET_KEY, LANGFLOW_AUTO_LOGIN, etc.)
echo "Starting Langflow application..."
langflow run --host "$LANGFLOW_HOST" --port "$LANGFLOW_PORT"

# If langflow run daemonizes itself or you want nginx in foreground instead:
# langflow run --host "$LANGFLOW_HOST" --port "$LANGFLOW_PORT" &
# nginx -g 'daemon off;'
