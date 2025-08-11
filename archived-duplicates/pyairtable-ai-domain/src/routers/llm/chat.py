"""Chat completion endpoints"""
from fastapi import APIRouter, Request, HTTPException, Depends
from fastapi.responses import StreamingResponse
from typing import Optional

from ...models.llm.chat import ChatRequest, ChatResponse
from ...core.logging import get_logger
from ...services.llm.provider_manager import LLMProviderManager


router = APIRouter()
logger = get_logger(__name__)


def get_provider_manager(request: Request) -> LLMProviderManager:
    """Get LLM provider manager from app state"""
    if not hasattr(request.app.state, "provider_manager"):
        raise HTTPException(status_code=503, detail="LLM Provider Manager not initialized")
    return request.app.state.provider_manager


@router.post("/chat/completions", response_model=ChatResponse)
async def create_chat_completion(
    request: ChatRequest,
    provider_manager: LLMProviderManager = Depends(get_provider_manager)
):
    """Create a chat completion"""
    try:
        if request.stream:
            # For streaming, redirect to streaming endpoint
            raise HTTPException(
                status_code=400,
                detail="Use /chat/completions/stream for streaming responses"
            )
        
        response = await provider_manager.chat_completion(request)
        return response
        
    except ValueError as e:
        logger.error(f"Chat completion validation error: {str(e)}")
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        logger.error(f"Chat completion error: {str(e)}")
        raise HTTPException(status_code=500, detail="Internal server error")


@router.post("/chat/completions/stream")
async def stream_chat_completion(
    request: ChatRequest,
    provider_manager: LLMProviderManager = Depends(get_provider_manager)
):
    """Create a streaming chat completion"""
    try:
        # Force streaming
        request.stream = True
        
        async def generate():
            async for chunk in provider_manager.stream_chat_completion(request):
                yield chunk
        
        return StreamingResponse(
            generate(),
            media_type="text/plain",
            headers={
                "Cache-Control": "no-cache",
                "Connection": "keep-alive",
            }
        )
        
    except ValueError as e:
        logger.error(f"Streaming chat completion validation error: {str(e)}")
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        logger.error(f"Streaming chat completion error: {str(e)}")
        raise HTTPException(status_code=500, detail="Internal server error")


@router.get("/chat/models")
async def list_chat_models(
    provider_manager: LLMProviderManager = Depends(get_provider_manager)
):
    """List available chat models"""
    try:
        models = await provider_manager.list_models()
        
        # Filter for chat/completion models
        chat_models = [
            model for model in models
            if not model.id.startswith("text-embedding")
        ]
        
        return {
            "object": "list",
            "data": [model.model_dump() for model in chat_models]
        }
        
    except Exception as e:
        logger.error(f"Error listing chat models: {str(e)}")
        raise HTTPException(status_code=500, detail="Internal server error")


@router.get("/chat/providers")
async def list_providers(
    provider_manager: LLMProviderManager = Depends(get_provider_manager)
):
    """List available LLM providers and their status"""
    try:
        provider_health = await provider_manager.get_provider_health()
        usage_stats = await provider_manager.get_usage_stats()
        
        providers = []
        for provider_name in provider_manager.providers.keys():
            provider_info = {
                "name": provider_name,
                "health": provider_health.get(provider_name, {}),
                "usage": usage_stats.get(provider_name, {}),
                "models": provider_manager.providers[provider_name].get_supported_models()
            }
            providers.append(provider_info)
        
        return {
            "providers": providers,
            "total_providers": len(providers)
        }
        
    except Exception as e:
        logger.error(f"Error listing providers: {str(e)}")
        raise HTTPException(status_code=500, detail="Internal server error")