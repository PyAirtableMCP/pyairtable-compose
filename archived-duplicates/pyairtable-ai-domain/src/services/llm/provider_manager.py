"""LLM Provider Manager for handling multiple providers"""
import asyncio
from typing import Dict, List, Optional, Any, AsyncGenerator, Union
from datetime import datetime, timedelta

from .base_provider import BaseLLMProvider
from .openai_provider import OpenAIProvider
from .gemini_provider import GeminiProvider
from ...models.llm.chat import (
    ChatRequest, ChatResponse, CompletionRequest, CompletionResponse,
    EmbeddingRequest, EmbeddingResponse, ModelInfo
)
from ...core.config import get_settings
from ...core.logging import get_logger, TokenUsageLogger
from ...utils.redis_client import get_redis_client


class LLMProviderManager:
    """Manages multiple LLM providers and routing"""
    
    def __init__(self):
        self.settings = get_settings()
        self.logger = get_logger(__name__)
        self.usage_logger = TokenUsageLogger()
        self.providers: Dict[str, BaseLLMProvider] = {}
        self._model_to_provider: Dict[str, str] = {}
        self._fallback_chains: Dict[str, List[str]] = {}
        
        # Initialize providers
        asyncio.create_task(self._initialize_providers())
    
    async def _initialize_providers(self) -> None:
        """Initialize available providers based on configuration"""
        # OpenAI Provider
        if self.settings.openai_api_key:
            try:
                openai_config = {
                    "name": "openai",
                    "api_key": self.settings.openai_api_key,
                    "base_url": self.settings.openai_base_url,
                    "organization": self.settings.openai_organization,
                    "default_model": "gpt-4o-mini",
                    "models": [
                        "gpt-4o", "gpt-4o-mini", "gpt-4", "gpt-4-turbo",
                        "gpt-3.5-turbo", "text-embedding-3-large",
                        "text-embedding-3-small", "text-embedding-ada-002"
                    ]
                }
                self.providers["openai"] = OpenAIProvider(openai_config)
                self._update_model_mapping("openai", openai_config["models"])
                self.logger.info("Initialized OpenAI provider")
            except Exception as e:
                self.logger.error(f"Failed to initialize OpenAI provider: {str(e)}")
        
        # Gemini Provider
        if self.settings.gemini_api_key:
            try:
                gemini_config = {
                    "name": "google",
                    "api_key": self.settings.gemini_api_key,
                    "default_model": self.settings.gemini_model,
                    "models": [
                        "gemini-2.0-flash-exp", "gemini-1.5-pro",
                        "gemini-1.5-flash", "gemini-1.0-pro"
                    ]
                }
                self.providers["google"] = GeminiProvider(gemini_config)
                self._update_model_mapping("google", gemini_config["models"])
                self.logger.info("Initialized Gemini provider")
            except Exception as e:
                self.logger.error(f"Failed to initialize Gemini provider: {str(e)}")
        
        # Set up fallback chains
        self._setup_fallback_chains()
        
        self.logger.info(f"Initialized {len(self.providers)} LLM providers")
    
    def _update_model_mapping(self, provider_name: str, models: List[str]) -> None:
        """Update model to provider mapping"""
        for model in models:
            self._model_to_provider[model] = provider_name
    
    def _setup_fallback_chains(self) -> None:
        """Setup fallback chains for different model types"""
        # Chat models fallback chain
        chat_providers = []
        if "openai" in self.providers:
            chat_providers.append("openai")
        if "google" in self.providers:
            chat_providers.append("google")
        
        self._fallback_chains["chat"] = chat_providers
        
        # Embedding models fallback chain
        embedding_providers = []
        if "openai" in self.providers:
            embedding_providers.append("openai")
        if "google" in self.providers:
            embedding_providers.append("google")
        
        self._fallback_chains["embeddings"] = embedding_providers
    
    def get_provider_for_model(self, model: str) -> Optional[str]:
        """Get provider name for a specific model"""
        return self._model_to_provider.get(model)
    
    def get_provider(self, provider_name: str) -> Optional[BaseLLMProvider]:
        """Get provider instance by name"""
        return self.providers.get(provider_name)
    
    def get_default_provider(self, task_type: str = "chat") -> Optional[str]:
        """Get default provider for a task type"""
        fallback_chain = self._fallback_chains.get(task_type, [])
        return fallback_chain[0] if fallback_chain else None
    
    async def chat_completion(
        self, 
        request: ChatRequest, 
        use_fallback: bool = True
    ) -> ChatResponse:
        """Generate chat completion with automatic provider selection"""
        # Determine provider
        provider_name = None
        if request.provider:
            provider_name = request.provider
        elif request.model:
            provider_name = self.get_provider_for_model(request.model)
        else:
            provider_name = self.get_default_provider("chat")
        
        if not provider_name or provider_name not in self.providers:
            if use_fallback:
                fallback_chain = self._fallback_chains.get("chat", [])
                for fallback_provider in fallback_chain:
                    if fallback_provider in self.providers:
                        provider_name = fallback_provider
                        break
            
            if not provider_name:
                raise ValueError("No available provider for chat completion")
        
        provider = self.providers[provider_name]
        
        try:
            # Set default model if not specified
            if not request.model:
                request.model = provider.default_model
            
            # Check rate limits
            await self._check_rate_limits(provider_name, request.user)
            
            # Generate response
            response = await provider.chat_completion(request)
            
            # Log usage
            self.usage_logger.log_usage(
                provider=provider_name,
                model=response.model,
                prompt_tokens=response.usage.prompt_tokens,
                completion_tokens=response.usage.completion_tokens,
                cost=response.usage.cost,
                user_id=request.user,
                session_id=request.session_id
            )
            
            # Cache response if enabled
            if self.settings.enable_response_caching:
                await self._cache_response(request, response)
            
            return response
            
        except Exception as e:
            self.logger.error(
                f"Chat completion failed with {provider_name}: {str(e)}"
            )
            
            # Try fallback if enabled and this wasn't already a fallback
            if use_fallback and request.provider != provider_name:
                fallback_chain = self._fallback_chains.get("chat", [])
                for fallback_provider in fallback_chain:
                    if (fallback_provider != provider_name and 
                        fallback_provider in self.providers):
                        try:
                            fallback_request = request.model_copy()
                            fallback_request.provider = fallback_provider
                            fallback_request.model = self.providers[fallback_provider].default_model
                            return await self.chat_completion(fallback_request, use_fallback=False)
                        except Exception as fallback_error:
                            self.logger.error(
                                f"Fallback to {fallback_provider} failed: {str(fallback_error)}"
                            )
                            continue
            
            raise
    
    async def stream_chat_completion(
        self, 
        request: ChatRequest
    ) -> AsyncGenerator[str, None]:
        """Stream chat completion"""
        # Similar provider selection logic as chat_completion
        provider_name = None
        if request.provider:
            provider_name = request.provider
        elif request.model:
            provider_name = self.get_provider_for_model(request.model)
        else:
            provider_name = self.get_default_provider("chat")
        
        if not provider_name or provider_name not in self.providers:
            raise ValueError("No available provider for streaming chat completion")
        
        provider = self.providers[provider_name]
        
        # Set default model if not specified
        if not request.model:
            request.model = provider.default_model
        
        # Check rate limits
        await self._check_rate_limits(provider_name, request.user)
        
        async for chunk in provider.stream_chat_completion(request):
            yield chunk
    
    async def create_embeddings(
        self, 
        request: EmbeddingRequest
    ) -> EmbeddingResponse:
        """Create embeddings"""
        # Determine provider
        provider_name = None
        if request.provider:
            provider_name = request.provider
        elif request.model:
            provider_name = self.get_provider_for_model(request.model)
        else:
            provider_name = self.get_default_provider("embeddings")
        
        if not provider_name or provider_name not in self.providers:
            raise ValueError("No available provider for embeddings")
        
        provider = self.providers[provider_name]
        
        # Set default model if not specified
        if not request.model:
            request.model = "text-embedding-3-small" if provider_name == "openai" else "models/text-embedding-004"
        
        try:
            response = await provider.create_embeddings(request)
            
            # Log usage
            self.usage_logger.log_usage(
                provider=provider_name,
                model=response.model,
                prompt_tokens=response.usage.prompt_tokens,
                completion_tokens=0,
                cost=response.usage.cost,
                user_id=request.user
            )
            
            return response
            
        except Exception as e:
            self.logger.error(f"Embeddings creation failed: {str(e)}")
            raise
    
    async def list_models(self) -> List[ModelInfo]:
        """List all available models from all providers"""
        all_models = []
        
        for provider_name, provider in self.providers.items():
            try:
                models = await provider.list_models()
                all_models.extend(models)
            except Exception as e:
                self.logger.error(f"Failed to list models from {provider_name}: {str(e)}")
        
        return all_models
    
    async def get_provider_health(self) -> Dict[str, Any]:
        """Check health of all providers"""
        health_status = {}
        
        for provider_name, provider in self.providers.items():
            try:
                health_status[provider_name] = await provider.health_check()
            except Exception as e:
                health_status[provider_name] = {
                    "status": "unhealthy",
                    "error": str(e)
                }
        
        return health_status
    
    async def get_usage_stats(self) -> Dict[str, Any]:
        """Get usage statistics from all providers"""
        stats = {}
        
        for provider_name, provider in self.providers.items():
            stats[provider_name] = provider.get_usage_stats()
        
        return stats
    
    async def _check_rate_limits(self, provider_name: str, user_id: Optional[str]) -> None:
        """Check rate limits for provider and user"""
        if not user_id:
            return
        
        redis_client = await get_redis_client()
        if not redis_client:
            return
        
        # Check requests per minute
        key = f"rate_limit:{provider_name}:{user_id}:requests"
        current_requests = await redis_client.incr(key)
        if current_requests == 1:
            await redis_client.expire(key, 60)  # 1 minute
        
        if current_requests > self.settings.rate_limit_requests_per_minute:
            raise ValueError("Rate limit exceeded: too many requests")
        
        # Check tokens per minute (simplified)
        token_key = f"rate_limit:{provider_name}:{user_id}:tokens"
        # This would need to be implemented with proper token counting
    
    async def _cache_response(self, request: ChatRequest, response: ChatResponse) -> None:
        """Cache response for future use"""
        if not self.settings.enable_response_caching:
            return
        
        redis_client = await get_redis_client()
        if not redis_client:
            return
        
        # Create cache key from request
        cache_key = self._create_cache_key(request)
        
        try:
            await redis_client.setex(
                cache_key,
                self.settings.cache_ttl,
                response.model_dump_json()
            )
        except Exception as e:
            self.logger.warning(f"Failed to cache response: {str(e)}")
    
    def _create_cache_key(self, request: ChatRequest) -> str:
        """Create cache key from request"""
        import hashlib
        
        # Include relevant request parameters in cache key
        key_data = {
            "messages": [{"role": m.role, "content": m.content} for m in request.messages],
            "model": request.model,
            "temperature": request.temperature,
            "max_tokens": request.max_tokens,
        }
        
        if self.settings.cache_key_include_user and request.user:
            key_data["user"] = request.user
        
        key_str = str(sorted(key_data.items()))
        hash_obj = hashlib.md5(key_str.encode())
        return f"llm_cache:{hash_obj.hexdigest()}"
    
    async def close(self) -> None:
        """Close all providers"""
        for provider in self.providers.values():
            try:
                await provider.close()
            except Exception as e:
                self.logger.error(f"Error closing provider: {str(e)}")