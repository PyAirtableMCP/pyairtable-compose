#!/bin/bash
set -e

echo "🦭 Setting up Podman as Docker alternative..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check if Homebrew is installed
if ! command -v brew &> /dev/null; then
    echo "❌ Homebrew not found. Please install Homebrew first:"
    echo "   /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
    exit 1
fi

# Install Podman if not present
if ! command -v podman &> /dev/null; then
    echo "📦 Installing Podman..."
    brew install podman
    echo "✅ Podman installed successfully!"
else
    echo "✅ Podman is already installed"
    podman --version
fi

# Install podman-compose if not present
if ! command -v podman-compose &> /dev/null; then
    echo "📦 Installing podman-compose..."
    pip3 install podman-compose || brew install podman-compose
    echo "✅ podman-compose installed successfully!"
else
    echo "✅ podman-compose is already installed"
    podman-compose --version
fi

# Initialize Podman machine if needed
echo "🔧 Setting up Podman machine..."
if ! podman machine list | grep -q "running"; then
    if ! podman machine list | grep -q "podman-machine-default"; then
        echo "🏗️  Initializing Podman machine..."
        podman machine init
    fi
    
    echo "🚀 Starting Podman machine..."
    podman machine start
    
    # Wait for machine to be ready
    echo "⏳ Waiting for Podman machine to be ready..."
    sleep 10
else
    echo "✅ Podman machine is already running"
fi

# Verify Podman is working
echo "🔍 Verifying Podman setup..."
if podman --version &> /dev/null; then
    echo "✅ Podman is working:"
    podman --version
    podman info | head -10
else
    echo "❌ Podman is not accessible. Please check your setup."
    exit 1
fi

# Create helpful aliases
echo "🔗 Creating helpful aliases..."
SHELL_RC=""
if [ -f "$HOME/.zshrc" ]; then
    SHELL_RC="$HOME/.zshrc"
elif [ -f "$HOME/.bashrc" ]; then
    SHELL_RC="$HOME/.bashrc"
elif [ -f "$HOME/.bash_profile" ]; then
    SHELL_RC="$HOME/.bash_profile"
fi

if [ -n "$SHELL_RC" ]; then
    if ! grep -q "alias docker=podman" "$SHELL_RC"; then
        echo "" >> "$SHELL_RC"
        echo "# Podman aliases (PyAirtable development)" >> "$SHELL_RC"
        echo "alias docker=podman" >> "$SHELL_RC"
        echo "alias docker-compose=podman-compose" >> "$SHELL_RC"
        echo "✅ Aliases added to $SHELL_RC"
        echo "💡 Run 'source $SHELL_RC' or restart your terminal to use aliases"
    else
        echo "✅ Aliases already exist in $SHELL_RC"
    fi
fi

echo ""
echo "🎉 Podman setup complete!"
echo "📊 Machine status:"
podman machine list

echo ""
echo "🔧 Useful Podman commands:"
echo "   • List containers:        podman ps"
echo "   • List images:            podman images"
echo "   • Start machine:          podman machine start"
echo "   • Stop machine:           podman machine stop"
echo "   • Run with compose:       podman-compose up -d"
echo "   • SSH into machine:       podman machine ssh"
echo ""
echo "💡 You can now use 'podman' instead of 'docker' and 'podman-compose' instead of 'docker-compose'"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"