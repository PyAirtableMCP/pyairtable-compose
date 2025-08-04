"""OpenAI LLM provider"""
import json
import time
from typing import List, Dict, Any, Optional, AsyncGenerator

import httpx
from openai import AsyncOpenAI

from .base_provider import BaseLLMProvider
from ...models.llm.chat import (
    ChatRequest, ChatResponse, CompletionRequest, CompletionResponse,
    EmbeddingRequest, EmbeddingResponse, TokenUsage, ModelInfo, ChatChoice,
    Message, MessageRole, CompletionChoice
)
from ...core.logging import get_logger


class OpenAIProvider(BaseLLMProvider):
    """OpenAI LLM provider"""
    
    def __init__(self, config: Dict[str, Any]):
        super().__init__(config)
        self.logger = get_logger("openai_provider")
        
        if not self.api_key:
            raise ValueError("OpenAI API key is required")
        
        # Initialize OpenAI client
        client_kwargs = {"api_key": self.api_key}
        if self.base_url:
            client_kwargs["base_url"] = self.base_url
        if config.get("organization"):
            client_kwargs["organization"] = config["organization"]
        
        self.client = AsyncOpenAI(**client_kwargs)
        
        # Model pricing (per 1M tokens)
        self.pricing = {
            "gpt-4o": {"input": 2.50, "output": 10.00},
            "gpt-4o-mini": {"input": 0.15, "output": 0.60},
            "gpt-4": {"input": 30.00, "output": 60.00},
            "gpt-4-turbo": {"input": 10.00, "output": 30.00},
            "gpt-3.5-turbo": {"input": 0.50, "output": 1.50},
            "text-embedding-3-large": {"input": 0.13, "output": 0.0},
            "text-embedding-3-small": {"input": 0.02, "output": 0.0},
            "text-embedding-ada-002": {"input": 0.10, "output": 0.0},
        }
    
    async def chat_completion(self, request: ChatRequest) -> ChatResponse:
        """Generate chat completion"""
        await self.validate_request(request)
        
        # Convert messages to OpenAI format
        messages = [
            {"role": msg.role.value, "content": msg.content}
            for msg in request.messages
        ]
        
        # Build request parameters
        params = {
            "model": request.model or self.default_model,
            "messages": messages,
            "stream": False,
        }
        
        # Add optional parameters
        if request.temperature is not None:
            params["temperature"] = request.temperature
        if request.max_tokens is not None:
            params["max_tokens"] = request.max_tokens
        if request.top_p is not None:
            params["top_p"] = request.top_p
        if request.frequency_penalty is not None:
            params["frequency_penalty"] = request.frequency_penalty
        if request.presence_penalty is not None:
            params["presence_penalty"] = request.presence_penalty
        if request.stop is not None:
            params["stop"] = request.stop
        if request.functions is not None:
            params["functions"] = request.functions
        if request.function_call is not None:
            params["function_call"] = request.function_call
        if request.tools is not None:
            params["tools"] = request.tools
        if request.tool_choice is not None:
            params["tool_choice"] = request.tool_choice
        if request.user is not None:
            params["user"] = request.user
        
        try:
            response = await self.client.chat.completions.create(**params)
            
            # Convert response
            usage = TokenUsage(
                prompt_tokens=response.usage.prompt_tokens,
                completion_tokens=response.usage.completion_tokens,
                total_tokens=response.usage.total_tokens,
                cost=self.calculate_cost_from_usage(response.usage, params["model"])
            )
            
            # Track usage
            self.track_usage(
                params["model"],
                usage.prompt_tokens,
                usage.completion_tokens,
                usage.cost
            )
            
            choices = []
            for choice in response.choices:
                choices.append(ChatChoice(
                    index=choice.index,
                    message=Message(
                        role=MessageRole(choice.message.role),
                        content=choice.message.content or "",
                        function_call=choice.message.function_call,
                        tool_calls=choice.message.tool_calls
                    ),
                    finish_reason=choice.finish_reason
                ))
            
            return ChatResponse(
                id=response.id,
                created=response.created,
                model=response.model,
                choices=choices,
                usage=usage,
                system_fingerprint=response.system_fingerprint,
                session_id=request.session_id,
                provider=self.name
            )
            
        except Exception as e:
            self.logger.error(f"OpenAI chat completion error: {str(e)}")
            raise
    
    async def stream_chat_completion(
        self, request: ChatRequest
    ) -> AsyncGenerator[str, None]:
        """Stream chat completion"""
        await self.validate_request(request)
        
        # Convert messages to OpenAI format
        messages = [
            {"role": msg.role.value, "content": msg.content}
            for msg in request.messages
        ]
        
        # Build request parameters
        params = {
            "model": request.model or self.default_model,
            "messages": messages,
            "stream": True,
        }
        
        # Add optional parameters (same as above)
        if request.temperature is not None:
            params["temperature"] = request.temperature
        if request.max_tokens is not None:
            params["max_tokens"] = request.max_tokens
        # ... (add other parameters as needed)
        
        try:
            stream = await self.client.chat.completions.create(**params)
            
            async for chunk in stream:
                if chunk.choices and chunk.choices[0].delta.content:
                    data = {
                        "id": chunk.id,
                        "object": "chat.completion.chunk",
                        "created": chunk.created,
                        "model": chunk.model,
                        "choices": [{
                            "index": 0,
                            "delta": {"content": chunk.choices[0].delta.content},
                            "finish_reason": chunk.choices[0].finish_reason
                        }],
                        "provider": self.name
                    }
                    yield f"data: {json.dumps(data)}\n\n"
            
            yield "data: [DONE]\n\n"
            
        except Exception as e:
            self.logger.error(f"OpenAI streaming error: {str(e)}")
            raise
    
    async def text_completion(self, request: CompletionRequest) -> CompletionResponse:
        """Generate text completion"""
        await self.validate_request(request)
        
        # Build request parameters
        params = {
            "model": request.model or self.default_model,
            "prompt": request.prompt,
            "stream": False,
        }
        
        # Add optional parameters
        if request.max_tokens is not None:
            params["max_tokens"] = request.max_tokens
        if request.temperature is not None:
            params["temperature"] = request.temperature
        # ... (add other parameters)
        
        try:
            response = await self.client.completions.create(**params)
            
            # Convert response
            usage = TokenUsage(
                prompt_tokens=response.usage.prompt_tokens,
                completion_tokens=response.usage.completion_tokens,
                total_tokens=response.usage.total_tokens,
                cost=self.calculate_cost_from_usage(response.usage, params["model"])
            )
            
            choices = []
            for choice in response.choices:
                choices.append(CompletionChoice(
                    text=choice.text,
                    index=choice.index,
                    finish_reason=choice.finish_reason,
                    logprobs=choice.logprobs
                ))
            
            return CompletionResponse(
                id=response.id,
                created=response.created,
                model=response.model,
                choices=choices,
                usage=usage,
                provider=self.name
            )
            
        except Exception as e:
            self.logger.error(f"OpenAI completion error: {str(e)}")
            raise
    
    async def create_embeddings(self, request: EmbeddingRequest) -> EmbeddingResponse:
        """Create embeddings"""
        model = request.model or "text-embedding-3-small"
        
        # Build request parameters
        params = {
            "input": request.input,
            "model": model,
        }
        
        if request.dimensions:
            params["dimensions"] = request.dimensions
        if request.user:
            params["user"] = request.user
        
        try:
            response = await self.client.embeddings.create(**params)
            
            # Convert response
            usage = TokenUsage(
                prompt_tokens=response.usage.prompt_tokens,
                completion_tokens=0,
                total_tokens=response.usage.total_tokens,
                cost=self.calculate_cost_from_usage(response.usage, model)
            )
            
            return EmbeddingResponse(
                object="list",
                data=[
                    {
                        "object": "embedding",
                        "embedding": embedding.embedding,
                        "index": embedding.index
                    }
                    for embedding in response.data
                ],
                model=response.model,
                usage=usage,
                provider=self.name
            )
            
        except Exception as e:
            self.logger.error(f"OpenAI embeddings error: {str(e)}")
            raise
    
    def count_tokens(self, text: str, model: Optional[str] = None) -> int:
        """Count tokens using tiktoken"""
        try:
            import tiktoken
            
            model_name = model or self.default_model
            encoding = tiktoken.encoding_for_model(model_name)
            return len(encoding.encode(text))
        except Exception as e:
            self.logger.warning(f"Token counting error: {str(e)}")
            # Fallback estimation
            return len(text.split()) * 1.3
    
    def calculate_cost_from_usage(self, usage, model: str) -> float:
        """Calculate cost from OpenAI usage"""
        model_pricing = self.pricing.get(model, {"input": 0.0, "output": 0.0})
        
        input_cost = usage.prompt_tokens * (model_pricing["input"] / 1_000_000)
        output_cost = usage.completion_tokens * (model_pricing["output"] / 1_000_000)
        
        return round(input_cost + output_cost, 6)
    
    def calculate_cost(self, usage: TokenUsage, model: str) -> float:
        """Calculate cost for token usage"""
        model_pricing = self.pricing.get(model, {"input": 0.0, "output": 0.0})
        
        input_cost = usage.prompt_tokens * (model_pricing["input"] / 1_000_000)
        output_cost = usage.completion_tokens * (model_pricing["output"] / 1_000_000)
        
        return round(input_cost + output_cost, 6)
    
    async def list_models(self) -> List[ModelInfo]:
        """List available models"""
        try:
            response = await self.client.models.list()
            models = []
            
            for model in response.data:
                if model.id in self.pricing:
                    pricing = self.pricing[model.id]
                    models.append(ModelInfo(
                        id=model.id,
                        name=model.id,
                        provider=self.name,
                        max_tokens=128000 if "gpt-4" in model.id else 4096,
                        input_cost_per_token=pricing["input"] / 1_000_000,
                        output_cost_per_token=pricing["output"] / 1_000_000,
                        supports_streaming=True,
                        supports_functions="gpt-" in model.id and "3.5" not in model.id,
                        supports_vision="gpt-4" in model.id and "vision" in model.id,
                        context_window=128000 if "gpt-4" in model.id else 4096,
                        created=model.created,
                        description=f"OpenAI {model.id} model"
                    ))
            
            return models
        except Exception as e:
            self.logger.error(f"Error listing OpenAI models: {str(e)}")
            return []
    
    def supports_functions(self) -> bool:
        """OpenAI supports function calling"""
        return True
    
    def supports_vision(self) -> bool:
        """OpenAI GPT-4 supports vision"""
        return True
    
    async def close(self) -> None:
        """Close OpenAI client"""
        await self.client.close()