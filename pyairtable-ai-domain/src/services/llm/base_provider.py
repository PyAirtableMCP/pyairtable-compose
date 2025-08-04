"""Base LLM provider interface"""
from abc import ABC, abstractmethod
from typing import List, Dict, Any, Optional, AsyncGenerator, Union
import time

from ...models.llm.chat import (
    ChatRequest, ChatResponse, CompletionRequest, CompletionResponse,
    EmbeddingRequest, EmbeddingResponse, TokenUsage, ModelInfo
)


class BaseLLMProvider(ABC):
    """Abstract base class for LLM providers"""
    
    def __init__(self, config: Dict[str, Any]):
        self.config = config
        self.name = config.get("name", "unknown")
        self.api_key = config.get("api_key")
        self.base_url = config.get("base_url")
        self.default_model = config.get("default_model")
        self.models = config.get("models", [])
        self._cost_tracker = {}
    
    @abstractmethod
    async def chat_completion(self, request: ChatRequest) -> ChatResponse:
        """Generate chat completion"""
        pass
    
    @abstractmethod
    async def stream_chat_completion(
        self, request: ChatRequest
    ) -> AsyncGenerator[str, None]:
        """Stream chat completion"""
        pass
    
    async def text_completion(self, request: CompletionRequest) -> CompletionResponse:
        """Generate text completion (optional)"""
        raise NotImplementedError(f"{self.name} does not support text completion")
    
    async def create_embeddings(self, request: EmbeddingRequest) -> EmbeddingResponse:
        """Create embeddings (optional)"""
        raise NotImplementedError(f"{self.name} does not support embeddings")
    
    @abstractmethod
    def count_tokens(self, text: str, model: Optional[str] = None) -> int:
        """Count tokens in text"""
        pass
    
    @abstractmethod
    def calculate_cost(
        self, usage: TokenUsage, model: str
    ) -> float:
        """Calculate cost for token usage"""
        pass
    
    @abstractmethod
    async def list_models(self) -> List[ModelInfo]:
        """List available models"""
        pass
    
    def get_supported_models(self) -> List[str]:
        """Get list of supported models"""
        return self.models
    
    def supports_model(self, model: str) -> bool:
        """Check if model is supported"""
        return model in self.models
    
    def supports_streaming(self) -> bool:
        """Check if provider supports streaming"""
        return True
    
    def supports_functions(self) -> bool:
        """Check if provider supports function calling"""
        return False
    
    def supports_vision(self) -> bool:
        """Check if provider supports vision"""
        return False
    
    async def validate_request(self, request: Union[ChatRequest, CompletionRequest]) -> None:
        """Validate request parameters"""
        if hasattr(request, 'model') and request.model:
            if not self.supports_model(request.model):
                raise ValueError(f"Model {request.model} not supported by {self.name}")
        
        if hasattr(request, 'max_tokens') and request.max_tokens:
            if request.max_tokens > 100000:  # Reasonable upper limit
                raise ValueError("max_tokens exceeds reasonable limit")
        
        if hasattr(request, 'temperature') and request.temperature is not None:
            if not 0.0 <= request.temperature <= 2.0:
                raise ValueError("temperature must be between 0.0 and 2.0")
    
    def track_usage(
        self, model: str, prompt_tokens: int, completion_tokens: int, cost: float
    ) -> None:
        """Track token usage and costs"""
        key = f"{self.name}:{model}"
        if key not in self._cost_tracker:
            self._cost_tracker[key] = {
                "requests": 0,
                "prompt_tokens": 0,
                "completion_tokens": 0,
                "total_cost": 0.0
            }
        
        self._cost_tracker[key]["requests"] += 1
        self._cost_tracker[key]["prompt_tokens"] += prompt_tokens
        self._cost_tracker[key]["completion_tokens"] += completion_tokens
        self._cost_tracker[key]["total_cost"] += cost
    
    def get_usage_stats(self) -> Dict[str, Any]:
        """Get usage statistics"""
        return dict(self._cost_tracker)
    
    async def health_check(self) -> Dict[str, Any]:
        """Check provider health"""
        try:
            models = await self.list_models()
            return {
                "status": "healthy",
                "provider": self.name,
                "models_available": len(models),
                "supports_streaming": self.supports_streaming(),
                "supports_functions": self.supports_functions(),
                "supports_vision": self.supports_vision()
            }
        except Exception as e:
            return {
                "status": "unhealthy",
                "provider": self.name,
                "error": str(e)
            }
    
    async def close(self) -> None:
        """Close provider connections"""
        pass
    
    def _generate_id(self, prefix: str = "chat") -> str:
        """Generate unique ID"""
        return f"{prefix}-{int(time.time())}-{hash(self.name) % 10000}"