FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    gcc \
    python3-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements first for better caching
COPY mcp-server/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy shared telemetry code (required for OpenTelemetry)
COPY shared/ ./shared/

# Copy application
COPY mcp-server/src/ ./src/

# Create __init__.py files to ensure proper package structure
RUN touch /app/__init__.py && \
    touch /app/src/__init__.py && \
    touch /app/shared/__init__.py

# Set Python path to include app root and src
ENV PYTHONPATH=/app:/app/src

# Use the correct port that services expect (8001)
EXPOSE 8001

# Add health check
HEALTHCHECK --interval=15s --timeout=10s --start-period=40s --retries=5 \
    CMD curl -f http://localhost:8001/health || exit 1

# Use the correct port in the command
CMD ["python", "-m", "uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8001"]
