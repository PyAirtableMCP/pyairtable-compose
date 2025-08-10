#!/usr/bin/env python3
"""
Simple API Gateway for testing frontend-backend integration
"""
import os
import sys
import uvicorn
from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
import httpx
import asyncio
import json

# Create FastAPI app
app = FastAPI(
    title="Simple API Gateway", 
    description="Testing API Gateway for PyAirtable",
    version="1.0.0"
)

# Configure CORS for frontend integration
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000", "http://127.0.0.1:3000"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Service URLs
PLATFORM_SERVICES_URL = "http://localhost:8007"
AIRTABLE_GATEWAY_URL = "http://localhost:8002"

@app.get("/")
async def root():
    return {
        "service": "simple-api-gateway",
        "version": "1.0.0",
        "status": "healthy",
        "frontend_url": "http://localhost:3000"
    }

@app.get("/health")
async def health():
    services = {}
    
    # Check Platform Services
    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(f"{PLATFORM_SERVICES_URL}/health", timeout=5)
            services["platform_services"] = "healthy" if response.status_code == 200 else "unhealthy"
    except:
        services["platform_services"] = "unreachable"
    
    # Check Airtable Gateway
    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(f"{AIRTABLE_GATEWAY_URL}/health", timeout=5)
            services["airtable_gateway"] = "healthy" if response.status_code == 200 else "unhealthy"
    except:
        services["airtable_gateway"] = "unreachable"
    
    return {
        "status": "healthy",
        "timestamp": "2025-08-07T12:00:00Z",
        "services": services
    }

# Auth endpoints - proxy to platform services
@app.post("/auth/register")
async def register(request: Request):
    try:
        body = await request.body()
        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{PLATFORM_SERVICES_URL}/auth/register",
                content=body,
                headers=dict(request.headers)
            )
            return JSONResponse(
                status_code=response.status_code,
                content=response.json()
            )
    except Exception as e:
        return JSONResponse(
            status_code=500,
            content={"error": str(e)}
        )

@app.post("/auth/login")
async def login(request: Request):
    try:
        body = await request.body()
        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{PLATFORM_SERVICES_URL}/auth/login",
                content=body,
                headers=dict(request.headers)
            )
            return JSONResponse(
                status_code=response.status_code,
                content=response.json()
            )
    except Exception as e:
        return JSONResponse(
            status_code=500,
            content={"error": str(e)}
        )

@app.get("/auth/profile")
async def profile(request: Request):
    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(
                f"{PLATFORM_SERVICES_URL}/auth/profile",
                headers=dict(request.headers)
            )
            return JSONResponse(
                status_code=response.status_code,
                content=response.json()
            )
    except Exception as e:
        return JSONResponse(
            status_code=500,
            content={"error": str(e)}
        )

# Airtable endpoints - proxy to airtable gateway
@app.get("/airtable/{path:path}")
async def airtable_proxy(path: str, request: Request):
    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(
                f"{AIRTABLE_GATEWAY_URL}/{path}",
                params=dict(request.query_params),
                headers=dict(request.headers)
            )
            return JSONResponse(
                status_code=response.status_code,
                content=response.json()
            )
    except Exception as e:
        return JSONResponse(
            status_code=500,
            content={"error": str(e)}
        )

if __name__ == "__main__":
    port = int(os.getenv("PORT", "8000"))
    print(f"Starting Simple API Gateway on port {port}")
    print(f"CORS enabled for: http://localhost:3000")
    print(f"Proxying to Platform Services: {PLATFORM_SERVICES_URL}")
    print(f"Proxying to Airtable Gateway: {AIRTABLE_GATEWAY_URL}")
    uvicorn.run(
        "simple-api-gateway:app",
        host="0.0.0.0",
        port=port,
        reload=False
    )