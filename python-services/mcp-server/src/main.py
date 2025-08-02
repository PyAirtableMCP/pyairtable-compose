"""
mcp-server - Model Context Protocol server
"""
import os
from contextlib import asynccontextmanager
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
import uvicorn

from routes import health

# App lifespan
@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    print(f"Starting mcp-server...")
    yield
    # Shutdown
    print(f"Shutting down mcp-server...")

# Create FastAPI app
app = FastAPI(
    title="mcp-server",
    description="Model Context Protocol server",
    version="1.0.0",
    lifespan=lifespan
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Exception handler
@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    return JSONResponse(
        status_code=500,
        content={"detail": str(exc)}
    )

# Include routers
app.include_router(health.router, tags=["health"])
from routes.mcp import router as mcp_router
app.include_router(mcp_router)

# Root endpoint
@app.get("/")
async def root():
    return {
        "service": "mcp-server",
        "version": "1.0.0",
        "description": "Model Context Protocol server"
    }

# Service info endpoint
@app.get("/api/v1/info")
async def info():
    from config import get_settings
    from models.mcp import AVAILABLE_TOOLS
    settings = get_settings()
    return {
        "service": settings.service_name,
        "version": settings.service_version,
        "description": "Model Context Protocol server",
        "port": settings.port,
        "mode": settings.mcp_mode,
        "tools_count": len(AVAILABLE_TOOLS),
        "features": [
            "Airtable integration",
            "Tool execution",
            "RPC protocol",
            "REST API",
            "Async execution"
        ]
    }

if __name__ == "__main__":
    port = int(os.getenv("PORT", "8092"))
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=port,
        reload=os.getenv("ENV", "production") == "development"
    )
