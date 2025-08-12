#!/bin/bash
echo "🔧 Creating a fixed version of the LLM orchestrator..."

# Stop the current service
echo "Stopping llm-orchestrator service..."
docker-compose stop llm-orchestrator

# Create a temporary directory for our fix
mkdir -p /tmp/llm-orchestrator-fix
cd /tmp/llm-orchestrator-fix

# Copy files from the existing container to create our own image
echo "Extracting files from current container..."
docker run --rm ghcr.io/reg-kris/llm-orchestrator-py:latest tar -czf - /app | tar -xzf -

# Apply our fix to main.py
echo "Applying fix to main.py..."
sed -i.bak 's/return await chat_handler.handle_chat_request(request, trace_id=trace_id)/return await chat_handler.handle_chat_request(request)/g' app/src/main.py

# Verify the fix was applied
if grep -q "trace_id=trace_id" app/src/main.py; then
    echo "❌ Fix not applied correctly"
    exit 1
else
    echo "✅ Fix applied successfully"
fi

# Create a simple Dockerfile
cat > Dockerfile << 'EOF'
FROM python:3.12-slim

# Copy the fixed application
COPY app/ /app/

# Set working directory
WORKDIR /app

# Install dependencies
RUN pip install -r requirements.txt

# Expose port
EXPOSE 8003

# Run the application
CMD ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8003"]
EOF

# Build the fixed image
echo "Building fixed image..."
docker build -t pyairtable-llm-orchestrator-fixed:latest .

# Update docker-compose to use our fixed image
cd /Users/kg/IdeaProjects/pyairtable-compose

# Create a docker-compose override
cat > docker-compose.override.yml << 'EOF'
version: '3.8'

services:
  llm-orchestrator:
    image: pyairtable-llm-orchestrator-fixed:latest
    build:
      context: /tmp/llm-orchestrator-fix
      dockerfile: Dockerfile
EOF

echo "✅ Created docker-compose override"

# Start the service with the fixed image
echo "Starting fixed llm-orchestrator service..."
docker-compose up -d llm-orchestrator

echo "🎉 Fixed LLM orchestrator is now running!"
echo ""
echo "Test the fix with:"
echo "curl -X POST 'http://localhost:8003/chat' -H 'Content-Type: application/json' -d '{\"message\": \"Hello\", \"session_id\": \"test-123\"}'"