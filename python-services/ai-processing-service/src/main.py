"""
AI Processing Service - Consolidated MCP Server + LLM Orchestrator
"""
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import uvicorn
import os

# Create FastAPI app
app = FastAPI(
    title="AI Processing Service",
    description="Consolidated MCP Server + LLM Orchestrator for AI operations",
    version="1.0.0"
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Import and include health routes
from routes.health import router as health_router
app.include_router(health_router, tags=["health"])

# Root endpoint
@app.get("/")
async def root():
    return {
        "service": "ai-processing-service",
        "version": "1.0.0",
        "description": "Consolidated AI Processing Service (MCP + LLM Orchestrator)",
        "status": "active",
        "consolidation": {
            "original_services": ["mcp-server", "llm-orchestrator"],
            "consolidated_at": "2025-01-11",
            "benefits": [
                "Reduced latency between MCP and LLM operations",
                "Simplified service architecture",
                "Unified AI processing pipeline",
                "Single point of configuration"
            ]
        }
    }

# Service info endpoint
@app.get("/api/v1/info")
async def info():
    return {
        "service": "ai-processing-service",
        "version": "1.0.0",
        "description": "Consolidated AI Processing Service (MCP + LLM Orchestrator)",
        "port": 8001,
        "consolidation_info": {
            "original_services": ["mcp-server", "llm-orchestrator"],
            "original_ports": [8001, 8003],
            "new_port": 8001
        },
        "features": [
            # MCP Features
            "Airtable integration",
            "Tool execution", 
            "RPC protocol",
            "REST API",
            "Async execution",
            # LLM Features
            "Chat completions",
            "Streaming responses",
            "Session management",
            "Token counting",
            "Cost tracking",
            "Table analysis",
            "Batch processing",
            "Optimization recommendations"
        ]
    }

if __name__ == "__main__":
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8001,
        reload=os.getenv("ENV", "production") == "development"
    )