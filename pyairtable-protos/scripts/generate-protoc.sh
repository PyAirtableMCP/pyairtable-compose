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

echo -e "${YELLOW}Generating protobuf code using protoc...${NC}"

# Change to project root
cd "$PROJECT_ROOT"

# Add Go bin to PATH
export PATH="$PATH:$HOME/go/bin"

# Clean previous generated files
echo -e "${YELLOW}Cleaning previous generated files...${NC}"
rm -rf generated
mkdir -p generated/{go,python}

# Proto source and output directories
PROTO_DIR="proto"
GO_OUT_DIR="generated/go"
PYTHON_OUT_DIR="generated/python"

# Generate Go code
echo -e "${YELLOW}Generating Go code...${NC}"

# Get all proto files
PROTO_FILES=$(find $PROTO_DIR -name "*.proto" | sort)

# Generate Go code for each proto file
for proto_file in $PROTO_FILES; do
    echo "  Processing: $proto_file"
    protoc \
        --proto_path=$PROTO_DIR \
        --proto_path=/opt/homebrew/include \
        --go_out=$GO_OUT_DIR \
        --go_opt=paths=source_relative \
        --go-grpc_out=$GO_OUT_DIR \
        --go-grpc_opt=paths=source_relative \
        $proto_file
done

echo -e "${GREEN}Go code generated successfully!${NC}"

# Generate Python code
echo -e "${YELLOW}Generating Python code...${NC}"

# Activate virtual environment if it exists
if [ -f "venv/bin/activate" ]; then
    source venv/bin/activate
    echo "  Using virtual environment"
fi

for proto_file in $PROTO_FILES; do
    echo "  Processing: $proto_file"
    python3 -m grpc_tools.protoc \
        --proto_path=$PROTO_DIR \
        --proto_path=/opt/homebrew/include \
        --python_out=$PYTHON_OUT_DIR \
        --grpc_python_out=$PYTHON_OUT_DIR \
        $proto_file
done

echo -e "${GREEN}Python code generated successfully!${NC}"

# Create __init__.py files for Python package structure
echo -e "${YELLOW}Creating Python package structure...${NC}"
find $PYTHON_OUT_DIR -type d -exec touch {}/__init__.py \;

# Count generated files
GO_FILES=$(find $GO_OUT_DIR -name "*.go" | wc -l)
PYTHON_FILES=$(find $PYTHON_OUT_DIR -name "*.py" | wc -l)

echo -e "${GREEN}Generated ${GO_FILES} Go files and ${PYTHON_FILES} Python files${NC}"

# Initialize Go module if it doesn't exist
if [ ! -f "$GO_OUT_DIR/go.mod" ]; then
    echo -e "${YELLOW}Initializing Go module...${NC}"
    cd $GO_OUT_DIR
    go mod init github.com/pyairtable/pyairtable-protos/generated/go
    go mod tidy
    cd "$PROJECT_ROOT"
    echo -e "${GREEN}Go module initialized!${NC}"
fi

# Create Python setup.py if it doesn't exist
if [ ! -f "$PYTHON_OUT_DIR/setup.py" ]; then
    echo -e "${YELLOW}Creating Python setup.py...${NC}"
    cat > $PYTHON_OUT_DIR/setup.py << 'EOF'
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