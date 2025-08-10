FROM python:3.12-slim

WORKDIR /app

# Install build dependencies and curl for health checks
RUN apt-get update && apt-get install -y \
    gcc \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements first for better caching
COPY airtable-gateway/requirements.txt .
COPY airtable-gateway/requirements-test.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy shared telemetry code (required for OpenTelemetry)
# Note: Build context should be set to python-services directory
COPY shared/ ./shared/

# Copy application code
COPY airtable-gateway/src/ ./src/

# Create __init__.py files to ensure proper package structure
RUN touch /app/__init__.py && \
    touch /app/src/__init__.py && \
    touch /app/shared/__init__.py

# Set Python path to include src directory first, then app root
ENV PYTHONPATH=/app/src:/app

EXPOSE 8002

# Health check using curl instead of httpx to avoid import issues
HEALTHCHECK --interval=15s --timeout=10s --start-period=45s --retries=5 \
    CMD curl -f http://localhost:8002/health || exit 1

# Change to src directory and run the application
WORKDIR /app/src
CMD ["python", "-m", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8002"]