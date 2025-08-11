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

echo -e "${YELLOW}Starting code generation...${NC}"

# Change to project root
cd "$PROJECT_ROOT"

# Clean previous generated files
echo -e "${YELLOW}Cleaning previous generated files...${NC}"
rm -rf generated
mkdir -p generated/{go,python}

# Check if buf is available
if ! command -v buf &> /dev/null; then
    if [ -f "bin/buf" ]; then
        export PATH="$PROJECT_ROOT/bin:$PATH"
    else
        echo -e "${RED}buf not found. Please run 'make install-tools' first.${NC}"
        exit 1
    fi
fi

# Generate code using buf
echo -e "${YELLOW}Generating protobuf code...${NC}"
buf generate

# Verify generation was successful
if [ -d "generated/go" ] && [ -d "generated/python" ]; then
    echo -e "${GREEN}Code generation completed successfully!${NC}"
    
    # Count generated files
    GO_FILES=$(find generated/go -name "*.go" | wc -l)
    PYTHON_FILES=$(find generated/python -name "*.py" | wc -l)
    
    echo -e "${GREEN}Generated ${GO_FILES} Go files and ${PYTHON_FILES} Python files${NC}"
else
    echo -e "${RED}Code generation failed!${NC}"
    exit 1
fi

# Initialize Go module if it doesn't exist
if [ ! -f "generated/go/go.mod" ]; then
    echo -e "${YELLOW}Initializing Go module...${NC}"
    cd generated/go
    go mod init github.com/pyairtable/pyairtable-protos/generated/go
    go mod tidy
    cd "$PROJECT_ROOT"
    echo -e "${GREEN}Go module initialized!${NC}"
fi

# Create Python setup.py if it doesn't exist
if [ ! -f "generated/python/setup.py" ]; then
    echo -e "${YELLOW}Creating Python setup.py...${NC}"
    cat > generated/python/setup.py << 'EOF'
from setuptools import setup, find_packages

setup(
    name="pyairtable-protos",
    version="0.1.0",
    description="Generated protobuf files for PyAirtable services",
    packages=find_packages(),
    install_requires=[
        "grpcio>=1.50.0",
        "grpcio-tools>=1.50.0",
        "protobuf>=4.21.0",
    ],
    python_requires=">=3.8",
)
EOF
    echo -e "${GREEN}Python setup.py created!${NC}"
fi

echo -e "${GREEN}All done! Generated code is ready to use.${NC}"