#!/bin/bash
set -e

echo "🐳 Setting up Colima container runtime..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check if Homebrew is installed
if ! command -v brew &> /dev/null; then
    echo "❌ Homebrew not found. Please install Homebrew first:"
    echo "   /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
    exit 1
fi

# Install Colima if not present
if ! command -v colima &> /dev/null; then
    echo "📦 Installing Colima..."
    brew install colima
    echo "✅ Colima installed successfully!"
else
    echo "✅ Colima is already installed"
    colima --version
fi

# Check if Colima is already running
if colima status &> /dev/null; then
    echo "ℹ️  Colima is already running"
    colima status
else
    echo "🚀 Starting Colima with optimized settings..."
    
    # Determine architecture
    ARCH=$(uname -m)
    if [ "$ARCH" = "arm64" ]; then
        echo "🍎 Detected Apple Silicon (ARM64), using optimized settings..."
        colima start --cpu 4 --memory 8 --disk 60 --arch aarch64 --vm-type=vz --vz-rosetta
    else
        echo "💻 Detected Intel (x86_64), using standard settings..."
        colima start --cpu 4 --memory 8 --disk 60
    fi
fi

# Verify Docker is working
echo "🔍 Verifying Docker setup..."
if docker --version &> /dev/null; then
    echo "✅ Docker is working:"
    docker --version
    docker info | head -5
else
    echo "❌ Docker is not accessible. Please check your setup."
    exit 1
fi

echo ""
echo "🎉 Colima setup complete!"
echo "📊 Current status:"
colima status

echo ""
echo "🔧 Useful Colima commands:"
echo "   • Check status:     colima status"
echo "   • Stop Colima:      colima stop"
echo "   • Restart Colima:   colima restart"
echo "   • View logs:        colima logs"
echo "   • SSH into VM:      colima ssh"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"