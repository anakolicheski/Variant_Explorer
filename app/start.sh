#!/bin/bash
set -e

echo ""
echo "  ╔═══════════════════════════════════════════╗"
echo "  ║   Cooper Lab Variant Database  v1.0.1    ║"
echo "  ╚═══════════════════════════════════════════╝"
echo ""

# Check Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "  ERROR: Docker is not running."
    echo "  Please start Docker Desktop and try again."
    exit 1
fi

# Create placeholder files for volumes if they don't exist
touch col_state_v2.json candidates.csv domain_cache.rds column_mapping_config.json 2>/dev/null || true
mkdir -p annotations New_genotypes

echo "  Starting app (first run may take a moment)..."
docker compose up -d

# Wait for the app to respond
echo "  Waiting for app to start..."
until curl -s http://localhost:3838 > /dev/null 2>&1; do
    sleep 2
done

# Open browser (works on Mac and most Linux)
echo "  Opening browser..."
if command -v open &>/dev/null; then
    open "http://localhost:3838"          # macOS
elif command -v xdg-open &>/dev/null; then
    xdg-open "http://localhost:3838"      # Linux
fi

echo ""
echo "  App is running at http://localhost:3838"
echo "  Press Ctrl+C to stop."
echo ""

# Keep running; stop container on Ctrl+C
trap "docker compose down; exit" INT TERM
wait
