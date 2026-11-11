#!/bin/bash
set -e

echo ""
echo "  ╔═══════════════════════════════════════════╗"
echo "  ║        Cooper Lab Variant Explorer        ║"
echo "  ╚═══════════════════════════════════════════╝"
echo ""

# Always work from the folder this script is in
cd "$(dirname "$0")"
for f in Dockerfile docker-compose.yml renv.lock; do
    if [ ! -f "$f" ]; then
        echo "  ERROR: $f was not found in $(pwd)"
        echo "  start.sh must be in the app folder, next to Dockerfile and renv.lock."
        exit 1
    fi
done

# Check Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "  ERROR: Docker is not running."
    echo "  Please start Docker Desktop and try again."
    exit 1
fi

# Create the folders that are mounted into the container
mkdir -p annotations New_genotypes app_state

# One-time move of phenotype / CRAM files from the old location
for f in Phenotypes.xlsx cram_paths.xlsx; do
    if [ -s "$f" ] && [ ! -e "app_state/$f" ]; then
        cp "$f" app_state/ && echo "  Copied $f into app_state/"
    fi
done

echo "  Data folder: $(pwd)"
echo "  Starting app (first run, or after an update, may take a few minutes)..."

# Remove any running copy first. Only one copy can use port 3838, and a copy
# started from another folder would otherwise keep answering with its data.
docker rm -f variant-explorer > /dev/null 2>&1 || true

# --build rebuilds the image when the app files changed; it is quick otherwise
if ! docker compose up -d --build; then
    echo ""
    echo "  ERROR: Docker could not build or start the app. See the messages above."
    exit 1
fi

echo "  Waiting for app to start..."
tries=0
until curl -s http://localhost:3838 > /dev/null 2>&1; do
    sleep 2
    tries=$((tries + 1))
    if [ "$tries" -ge 150 ]; then
        echo ""
        echo "  ERROR: The app did not start within 5 minutes. Last lines of the log:"
        echo "  ------------------------------------------------------------------"
        docker logs --tail 25 variant-explorer
        echo "  ------------------------------------------------------------------"
        echo "  Send the lines above to whoever maintains the app."
        docker compose down
        exit 1
    fi
done

echo "  Opening browser..."
if command -v open &>/dev/null; then
    open "http://localhost:3838"          # macOS
elif command -v xdg-open &>/dev/null; then
    xdg-open "http://localhost:3838"      # Linux
fi

echo ""
echo "  App is running at http://localhost:3838"
echo "  Data folder: $(pwd)"
echo "  Press Enter (or Ctrl+C) to stop the app."
echo ""

trap "docker compose down; exit" INT TERM
read -r _
docker compose down
