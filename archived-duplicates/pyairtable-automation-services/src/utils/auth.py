import httpx
from fastapi import HTTPException, Header
from ..config import settings
import logging

logger = logging.getLogger(__name__)

async def verify_api_key(x_api_key: str = Header(None)) -> str:
    """Verify API key with auth service or local validation"""
    if not x_api_key:
        raise HTTPException(status_code=401, detail="API key required")
    
    # For now, do simple validation against configured API key
    # In production, this would validate against the auth service
    if x_api_key != settings.api_key:
        # Try validating with auth service if configured
        if settings.auth_service_url:
            try:
                async with httpx.AsyncClient() as client:
                    response = await client.post(
                        f"{settings.auth_service_url}/validate",
                        headers={"X-API-Key": x_api_key},
                        timeout=5.0
                    )
                    
                    if response.status_code != 200:
                        raise HTTPException(status_code=401, detail="Invalid API key")
                    
                    return x_api_key
                    
            except httpx.RequestError as e:
                logger.warning(f"Auth service unavailable: {str(e)}")
                # Fall back to local validation
                raise HTTPException(status_code=401, detail="Invalid API key")
        else:
            raise HTTPException(status_code=401, detail="Invalid API key")
    
    return x_api_key

def create_auth_headers(api_key: str) -> dict:
    """Create authentication headers for service-to-service calls"""
    return {"X-API-Key": api_key}