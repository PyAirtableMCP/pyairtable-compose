#!/bin/bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Versions
PROTOC_VERSION="3.21.12"
BUF_VERSION="v1.28.1"
PROTOC_GEN_GO_VERSION="v1.31.0"
PROTOC_GEN_GO_GRPC_VERSION="v1.3.0"

echo -e "${YELLOW}Installing protobuf tools...${NC}"

# Detect OS
OS=""
ARCH=""
case "$(uname -s)" in
    Darwin*)
        OS="osx"
        ;;
    Linux*)
        OS="linux"
        ;;
    *)
        echo -e "${RED}Unsupported OS: $(uname -s)${NC}"
        exit 1
        ;;
esac

case "$(uname -m)" in
    x86_64)
        ARCH="x86_64"
        ;;
    arm64|aarch64)
        ARCH="aarch_64"
        ;;
    *)
        echo -e "${RED}Unsupported architecture: $(uname -m)${NC}"
        exit 1
        ;;
esac

# Create bin directory if it doesn't exist
mkdir -p bin

# Install buf
if ! command -v buf &> /dev/null; then
    echo -e "${YELLOW}Installing buf...${NC}"
    
    # Determine the correct buf release name
    if [[ "$OS" == "osx" ]]; then
        BUF_OS="Darwin"
    else
        BUF_OS="Linux"
    fi
    
    if [[ "$ARCH" == "aarch_64" ]]; then
        BUF_ARCH="arm64"
    else
        BUF_ARCH="x86_64"
    fi
    
    BUF_URL="https://github.com/bufbuild/buf/releases/download/${BUF_VERSION}/buf-${BUF_OS}-${BUF_ARCH}"
    echo "Downloading buf from: ${BUF_URL}"
    
    if curl -sSL "${BUF_URL}" -o bin/buf; then
        chmod +x bin/buf
        echo -e "${GREEN}buf installed successfully!${NC}"
    else
        echo -e "${RED}Failed to download buf${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}buf is already installed.${NC}"
fi

# Install protoc if not available
if ! command -v protoc &> /dev/null; then
    echo -e "${YELLOW}Installing protoc...${NC}"
    
    # Use Homebrew on macOS if available
    if [[ "$OS" == "osx" ]] && command -v brew &> /dev/null; then
        echo -e "${YELLOW}Using Homebrew to install protoc...${NC}"
        brew install protobuf
        echo -e "${GREEN}protoc installed successfully via Homebrew!${NC}"
    else
        # Manual installation for other platforms
        PROTOC_ARCH="$ARCH"
        # Handle architecture naming differences
        if [[ "$OS" == "osx" && "$ARCH" == "aarch_64" ]]; then
            PROTOC_ARCH="aarch_64"
        fi
        
        PROTOC_ZIP="protoc-${PROTOC_VERSION}-${OS}-${PROTOC_ARCH}.zip"
        PROTOC_URL="https://github.com/protocolbuffers/protobuf/releases/download/v${PROTOC_VERSION}/${PROTOC_ZIP}"
        
        echo "Downloading protoc from: ${PROTOC_URL}"
        if curl -sSL "${PROTOC_URL}" -o /tmp/${PROTOC_ZIP}; then
            if unzip -q /tmp/${PROTOC_ZIP} -d /tmp/protoc; then
                cp /tmp/protoc/bin/protoc bin/
                chmod +x bin/protoc
                rm -rf /tmp/${PROTOC_ZIP} /tmp/protoc
                echo -e "${GREEN}protoc installed successfully!${NC}"
            else
                echo -e "${RED}Failed to extract protoc archive${NC}"
                exit 1
            fi
        else
            echo -e "${RED}Failed to download protoc${NC}"
            exit 1
        fi
    fi
else
    echo -e "${GREEN}protoc is already installed.${NC}"
fi

# Install Go protobuf plugins if Go is available
if command -v go &> /dev/null; then
    echo -e "${YELLOW}Installing Go protobuf plugins...${NC}"
    
    # Install protoc-gen-go
    if ! command -v protoc-gen-go &> /dev/null; then
        go install google.golang.org/protobuf/cmd/protoc-gen-go@${PROTOC_GEN_GO_VERSION}
        echo -e "${GREEN}protoc-gen-go installed successfully!${NC}"
    else
        echo -e "${GREEN}protoc-gen-go is already installed.${NC}"
    fi
    
    # Install protoc-gen-go-grpc
    if ! command -v protoc-gen-go-grpc &> /dev/null; then
        go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@${PROTOC_GEN_GO_GRPC_VERSION}
        echo -e "${GREEN}protoc-gen-go-grpc installed successfully!${NC}"
    else
        echo -e "${GREEN}protoc-gen-go-grpc is already installed.${NC}"
    fi
else
    echo -e "${YELLOW}Go not found. Skipping Go plugin installation.${NC}"
fi

# Install Python protobuf tools if Python is available
if command -v python3 &> /dev/null; then
    echo -e "${YELLOW}Installing Python protobuf tools...${NC}"
    
    # Try installing with user flag first
    if python3 -m pip install --user --upgrade pip grpcio-tools mypy-protobuf; then
        echo -e "${GREEN}Python protobuf tools installed successfully!${NC}"
    else
        echo -e "${YELLOW}Failed to install Python tools. You may need to install them manually:${NC}"
        echo -e "${YELLOW}  python3 -m pip install --user grpcio-tools mypy-protobuf${NC}"
        echo -e "${YELLOW}  or use a virtual environment${NC}"
    fi
else
    echo -e "${YELLOW}Python3 not found. Skipping Python tools installation.${NC}"
fi

# Add bin directory to PATH hint
echo -e "${YELLOW}Note: Add $(pwd)/bin to your PATH to use the installed tools:${NC}"
echo -e "${GREEN}export PATH=\$PATH:$(pwd)/bin${NC}"

echo -e "${GREEN}All tools installed successfully!${NC}"