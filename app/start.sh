#!/bin/bash
set -e

echo ""
echo "  ╔═══════════════════════════════════════════╗"
echo "  ║        Cooper Lab Variant Database        ║"
echo "  ╚═══════════════════════════════════════════╝"
echo ""

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

echo "  Starting app (first run, or after an update, may take a few minutes)..."
# --build rebuilds the image when the app files changed; it is quick otherwise
docker compose up -d --build

# Wait for the app to respond
echo "  Waiting for app to start..."
tries=0
until curl -s http://localhost:3838 > /dev/null 2>&1; do
    sleep 2
    tries=$((tries + 1))
    if [ "$tries" -ge 150 ]; then
        # ~5 minutes without a response: show why, stop the container, exit
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

# Open browser (works on Mac and most Linux)
echo "  Opening browser..."
if command -v open &>/dev/null; then
    open "http://localhost:3838"          # macOS
elif command -v xdg-open &>/dev/null; then
    xdg-open "http://localhost:3838"      # Linux
fi

echo ""
echo "  App is running at http://localhost:3838"
echo "  Press Enter (or Ctrl+C) to stop the app."
echo ""

# Stop the container on Enter or Ctrl+C
trap "docker compose down; exit" INT TERM
read -r _
docker compose down
