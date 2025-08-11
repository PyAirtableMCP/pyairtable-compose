"""Google Gemini LLM provider"""
import json
import time
from typing import List, Dict, Any, Optional, AsyncGenerator

import google.generativeai as genai
from google.generativeai.types import HarmCategory, HarmBlockThreshold

from .base_provider import BaseLLMProvider
from ...models.llm.chat import (
    ChatRequest, ChatResponse, EmbeddingRequest, EmbeddingResponse,
    Message, MessageRole, TokenUsage, ModelInfo, ChatChoice
)
from ...core.logging import get_logger


class GeminiProvider(BaseLLMProvider):
    """Google Gemini LLM provider"""
    
    def __init__(self, config: Dict[str, Any]):
        super().__init__(config)
        self.logger = get_logger(f"gemini_provider")
        
        if not self.api_key:
            raise ValueError("Gemini API key is required")
        
        genai.configure(api_key=self.api_key)
        
        # Safety settings
        self.safety_settings = {
            HarmCategory.HARM_CATEGORY_HATE_SPEECH: HarmBlockThreshold.BLOCK_ONLY_HIGH,
            HarmCategory.HARM_CATEGORY_HARASSMENT: HarmBlockThreshold.BLOCK_ONLY_HIGH,
            HarmCategory.HARM_CATEGORY_DANGEROUS_CONTENT: HarmBlockThreshold.BLOCK_ONLY_HIGH,
            HarmCategory.HARM_CATEGORY_SEXUALLY_EXPLICIT: HarmBlockThreshold.BLOCK_ONLY_HIGH,
        }
        
        # Model pricing (per 1M tokens)
        self.pricing = {
            "gemini-2.0-flash-exp": {"input": 0.25, "output": 1.00},
            "gemini-1.5-pro": {"input": 3.50, "output": 14.00},
            "gemini-1.5-flash": {"input": 0.075, "output": 0.30},
            "gemini-1.0-pro": {"input": 0.50, "output": 1.50},
        }
    
    def _get_generation_config(self, request: ChatRequest) -> Dict[str, Any]:
        """Get generation configuration from request"""
        config = {
            "temperature": request.temperature or 0.7,
            "top_p": 0.95,
            "top_k": 40,
            "max_output_tokens": request.max_tokens or 4096,
        }
        
        # Add thinking budget for flash models
        if (request.thinking_budget and 
            request.model and 
            "flash" in request.model):
            config["thinking_budget"] = request.thinking_budget
        
        return config
    
    def _get_model(self, model_name: str, generation_config: Dict[str, Any]) -> genai.GenerativeModel:
        """Get Gemini model instance"""
        return genai.GenerativeModel(
            model_name=model_name,
            generation_config=generation_config,
            safety_settings=self.safety_settings
        )
    
    def _convert_messages(self, messages: List[Message]) -> List[Dict[str, Any]]:
        """Convert messages to Gemini format"""
        gemini_messages = []
        
        for msg in messages:
            if msg.role == MessageRole.SYSTEM:
                # Gemini doesn't have system role, prepend to first user message
                if gemini_messages and gemini_messages[0]["role"] == "user":
                    gemini_messages[0]["parts"][0] = f"{msg.content}\n\n{gemini_messages[0]['parts'][0]}"
                else:
                    gemini_messages.insert(0, {
                        "role": "user",
                        "parts": [msg.content]
                    })
            elif msg.role == MessageRole.USER:
                gemini_messages.append({
                    "role": "user",
                    "parts": [msg.content]
                })
            elif msg.role == MessageRole.ASSISTANT:
                gemini_messages.append({
                    "role": "model",
                    "parts": [msg.content]
                })
        
        return gemini_messages
    
    async def chat_completion(self, request: ChatRequest) -> ChatResponse:
        """Generate chat completion"""
        await self.validate_request(request)
        
        model_name = request.model or self.default_model
        generation_config = self._get_generation_config(request)
        model = self._get_model(model_name, generation_config)
        
        # Convert messages
        gemini_messages = self._convert_messages(request.messages)
        
        try:
            # Generate response
            chat = model.start_chat(
                history=gemini_messages[:-1] if len(gemini_messages) > 1 else []
            )
            response = chat.send_message(gemini_messages[-1]["parts"][0])
            
            # Extract token usage
            usage_metadata = response.usage_metadata
            usage = TokenUsage(
                prompt_tokens=usage_metadata.prompt_token_count,
                completion_tokens=usage_metadata.candidates_token_count,
                total_tokens=usage_metadata.total_token_count,
                cost=self.calculate_cost_from_usage(usage_metadata, model_name)
            )
            
            # Track usage
            self.track_usage(
                model_name,
                usage.prompt_tokens,
                usage.completion_tokens,
                usage.cost
            )
            
            # Create response
            choice = ChatChoice(
                index=0,
                message=Message(
                    role=MessageRole.ASSISTANT,
                    content=response.text
                ),
                finish_reason="stop"
            )
            
            return ChatResponse(
                id=self._generate_id("chat"),
                created=int(time.time()),
                model=model_name,
                choices=[choice],
                usage=usage,
                session_id=request.session_id,
                provider=self.name
            )
            
        except Exception as e:
            self.logger.error(f"Gemini chat completion error: {str(e)}")
            raise
    
    async def stream_chat_completion(
        self, request: ChatRequest
    ) -> AsyncGenerator[str, None]:
        """Stream chat completion"""
        await self.validate_request(request)
        
        model_name = request.model or self.default_model
        generation_config = self._get_generation_config(request)
        model = self._get_model(model_name, generation_config)
        
        # Convert messages
        gemini_messages = self._convert_messages(request.messages)
        
        try:
            # Generate streaming response
            chat = model.start_chat(
                history=gemini_messages[:-1] if len(gemini_messages) > 1 else []
            )
            response_stream = chat.send_message(
                gemini_messages[-1]["parts"][0],
                stream=True
            )
            
            # Stream chunks
            for chunk in response_stream:
                if chunk.text:
                    data = {
                        "id": self._generate_id("chat"),
                        "object": "chat.completion.chunk",
                        "created": int(time.time()),
                        "model": model_name,
                        "choices": [{
                            "index": 0,
                            "delta": {"content": chunk.text},
                            "finish_reason": None
                        }],
                        "provider": self.name
                    }
                    yield f"data: {json.dumps(data)}\n\n"
            
            # Send final chunk
            final_data = {
                "id": self._generate_id("chat"),
                "object": "chat.completion.chunk",
                "created": int(time.time()),
                "model": model_name,
                "choices": [{
                    "index": 0,
                    "delta": {},
                    "finish_reason": "stop"
                }],
                "provider": self.name
            }
            yield f"data: {json.dumps(final_data)}\n\n"
            yield "data: [DONE]\n\n"
            
        except Exception as e:
            self.logger.error(f"Gemini streaming error: {str(e)}")
            raise
    
    async def create_embeddings(self, request: EmbeddingRequest) -> EmbeddingResponse:
        """Create embeddings"""
        model_name = request.model or "models/text-embedding-004"
        texts = request.input if isinstance(request.input, list) else [request.input]
        
        try:
            embeddings = []
            total_tokens = 0
            
            for i, text in enumerate(texts):
                result = genai.embed_content(
                    model=model_name,
                    content=str(text)
                )
                embeddings.append({
                    "object": "embedding",
                    "embedding": result["embedding"],
                    "index": i
                })
                # Estimate tokens for embeddings
                total_tokens += len(str(text).split()) * 1.3  # Rough estimate
            
            usage = TokenUsage(
                prompt_tokens=int(total_tokens),
                completion_tokens=0,
                total_tokens=int(total_tokens),
                cost=0.0  # Gemini embeddings are free for now
            )
            
            return EmbeddingResponse(
                object="list",
                data=embeddings,
                model=model_name,
                usage=usage,
                provider=self.name
            )
            
        except Exception as e:
            self.logger.error(f"Gemini embeddings error: {str(e)}")
            raise
    
    def count_tokens(self, text: str, model: Optional[str] = None) -> int:
        """Count tokens in text"""
        try:
            model_name = model or self.default_model
            model_instance = genai.GenerativeModel(model_name)
            return model_instance.count_tokens(text).total_tokens
        except Exception as e:
            self.logger.warning(f"Token counting error: {str(e)}")
            # Fallback estimation
            return len(text.split()) * 1.3
    
    def calculate_cost_from_usage(self, usage_metadata, model: str) -> float:
        """Calculate cost from Gemini usage metadata"""
        model_pricing = self.pricing.get(model, self.pricing["gemini-2.0-flash-exp"])
        
        input_cost = usage_metadata.prompt_token_count * (model_pricing["input"] / 1_000_000)
        output_cost = usage_metadata.candidates_token_count * (model_pricing["output"] / 1_000_000)
        
        return round(input_cost + output_cost, 6)
    
    def calculate_cost(self, usage: TokenUsage, model: str) -> float:
        """Calculate cost for token usage"""
        model_pricing = self.pricing.get(model, self.pricing["gemini-2.0-flash-exp"])
        
        input_cost = usage.prompt_tokens * (model_pricing["input"] / 1_000_000)
        output_cost = usage.completion_tokens * (model_pricing["output"] / 1_000_000)
        
        return round(input_cost + output_cost, 6)
    
    async def list_models(self) -> List[ModelInfo]:
        """List available models"""
        try:
            models = []
            for model_name, pricing in self.pricing.items():
                models.append(ModelInfo(
                    id=model_name,
                    name=model_name,
                    provider=self.name,
                    max_tokens=100000 if "pro" in model_name else 32000,
                    input_cost_per_token=pricing["input"] / 1_000_000,
                    output_cost_per_token=pricing["output"] / 1_000_000,
                    supports_streaming=True,
                    supports_functions=False,
                    supports_vision="pro" in model_name,
                    context_window=1000000 if "pro" in model_name else 32000,
                    description=f"Google {model_name} model"
                ))
            return models
        except Exception as e:
            self.logger.error(f"Error listing Gemini models: {str(e)}")
            return []
    
    def supports_functions(self) -> bool:
        """Gemini supports function calling"""
        return True
    
    def supports_vision(self) -> bool:
        """Gemini Pro supports vision"""
        return True