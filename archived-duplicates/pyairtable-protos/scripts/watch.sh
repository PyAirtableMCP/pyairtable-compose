#!/bin/bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo -e "${YELLOW}Starting file watcher for proto files...${NC}"
echo -e "${YELLOW}Watching for changes in: proto/${NC}"
echo -e "${YELLOW}Press Ctrl+C to stop${NC}"

# Check if fswatch is available
if ! command -v fswatch &> /dev/null; then
    echo -e "${RED}fswatch not found. Please install it:${NC}"
    echo -e "${YELLOW}  On macOS: brew install fswatch${NC}"
    echo -e "${YELLOW}  On Ubuntu: apt-get install fswatch${NC}"
    exit 1
fi

# Change to project root
cd "$PROJECT_ROOT"

# Function to run generation
generate_code() {
    echo -e "${YELLOW}Changes detected, regenerating code...${NC}"
    if ./scripts/generate.sh; then
        echo -e "${GREEN}Code regeneration completed!${NC}"
    else
        echo -e "${RED}Code regeneration failed!${NC}"
    fi
    echo -e "${YELLOW}Watching for more changes...${NC}"
}

# Initial generation
generate_code

# Watch for changes
fswatch -o proto/ | while read f; do
    generate_code
done