"""Chat models for LLM interactions"""
from enum import Enum
from typing import List, Optional, Dict, Any, Union
from datetime import datetime
from pydantic import BaseModel, Field


class MessageRole(str, Enum):
    """Message roles in chat conversation"""
    SYSTEM = "system"
    USER = "user"
    ASSISTANT = "assistant"
    FUNCTION = "function"
    TOOL = "tool"


class Message(BaseModel):
    """Chat message model"""
    role: MessageRole
    content: str
    name: Optional[str] = None
    function_call: Optional[Dict[str, Any]] = None
    tool_calls: Optional[List[Dict[str, Any]]] = None
    tool_call_id: Optional[str] = None


class ChatRequest(BaseModel):
    """Chat completion request"""
    messages: List[Message]
    model: Optional[str] = None
    temperature: Optional[float] = Field(None, ge=0.0, le=2.0)
    max_tokens: Optional[int] = Field(None, gt=0)
    top_p: Optional[float] = Field(None, ge=0.0, le=1.0)
    frequency_penalty: Optional[float] = Field(None, ge=-2.0, le=2.0)
    presence_penalty: Optional[float] = Field(None, ge=-2.0, le=2.0)
    stop: Optional[Union[str, List[str]]] = None
    stream: Optional[bool] = False
    functions: Optional[List[Dict[str, Any]]] = None
    function_call: Optional[Union[str, Dict[str, str]]] = None
    tools: Optional[List[Dict[str, Any]]] = None
    tool_choice: Optional[Union[str, Dict[str, Any]]] = None
    user: Optional[str] = None
    session_id: Optional[str] = None
    thinking_budget: Optional[int] = None  # For Gemini flash models
    
    # Provider-specific options
    provider: Optional[str] = None
    provider_options: Optional[Dict[str, Any]] = None


class TokenUsage(BaseModel):
    """Token usage information"""
    prompt_tokens: int
    completion_tokens: int
    total_tokens: int
    cost: Optional[float] = None


class ChatChoice(BaseModel):
    """Chat completion choice"""
    index: int
    message: Message
    finish_reason: Optional[str] = None
    logprobs: Optional[Dict[str, Any]] = None


class ChatResponse(BaseModel):
    """Chat completion response"""
    id: str
    object: str = "chat.completion"
    created: int
    model: str
    choices: List[ChatChoice]
    usage: TokenUsage
    system_fingerprint: Optional[str] = None
    session_id: Optional[str] = None
    provider: Optional[str] = None


class ChatCompletionChunk(BaseModel):
    """Streaming chat completion chunk"""
    id: str
    object: str = "chat.completion.chunk"
    created: int
    model: str
    choices: List[Dict[str, Any]]
    system_fingerprint: Optional[str] = None


class EmbeddingRequest(BaseModel):
    """Embedding generation request"""
    input: Union[str, List[str], List[int], List[List[int]]]
    model: Optional[str] = None
    encoding_format: Optional[str] = "float"
    dimensions: Optional[int] = None
    user: Optional[str] = None
    provider: Optional[str] = None


class EmbeddingData(BaseModel):
    """Single embedding data"""
    object: str = "embedding"
    embedding: List[float]
    index: int


class EmbeddingResponse(BaseModel):
    """Embedding generation response"""
    object: str = "list"
    data: List[EmbeddingData]
    model: str
    usage: TokenUsage
    provider: Optional[str] = None


class CompletionRequest(BaseModel):
    """Text completion request"""
    prompt: Union[str, List[str]]
    model: Optional[str] = None
    max_tokens: Optional[int] = Field(None, gt=0)
    temperature: Optional[float] = Field(None, ge=0.0, le=2.0)
    top_p: Optional[float] = Field(None, ge=0.0, le=1.0)
    n: Optional[int] = Field(1, ge=1, le=128)
    stream: Optional[bool] = False
    logprobs: Optional[int] = Field(None, ge=0, le=5)
    echo: Optional[bool] = False
    stop: Optional[Union[str, List[str]]] = None
    presence_penalty: Optional[float] = Field(None, ge=-2.0, le=2.0)
    frequency_penalty: Optional[float] = Field(None, ge=-2.0, le=2.0)
    best_of: Optional[int] = Field(None, ge=1, le=20)
    logit_bias: Optional[Dict[str, float]] = None
    user: Optional[str] = None
    suffix: Optional[str] = None
    provider: Optional[str] = None


class CompletionChoice(BaseModel):
    """Text completion choice"""
    text: str
    index: int
    logprobs: Optional[Dict[str, Any]] = None
    finish_reason: Optional[str] = None


class CompletionResponse(BaseModel):
    """Text completion response"""
    id: str
    object: str = "text_completion"
    created: int
    model: str
    choices: List[CompletionChoice]
    usage: TokenUsage
    provider: Optional[str] = None


class SessionInfo(BaseModel):
    """Chat session information"""
    session_id: str
    user_id: Optional[str] = None
    created_at: datetime
    updated_at: datetime
    message_count: int
    token_count: int
    cost: float
    model: Optional[str] = None
    provider: Optional[str] = None
    metadata: Optional[Dict[str, Any]] = None


class ProviderConfig(BaseModel):
    """LLM provider configuration"""
    name: str
    api_key: Optional[str] = None
    base_url: Optional[str] = None
    organization: Optional[str] = None
    default_model: str
    models: List[str]
    supports_streaming: bool = True
    supports_functions: bool = False
    supports_vision: bool = False
    rate_limits: Optional[Dict[str, int]] = None
    cost_per_token: Optional[Dict[str, Dict[str, float]]] = None


class ModelInfo(BaseModel):
    """Model information"""
    id: str
    name: str
    provider: str
    max_tokens: int
    input_cost_per_token: float
    output_cost_per_token: float
    supports_streaming: bool = True
    supports_functions: bool = False
    supports_vision: bool = False
    context_window: int
    created: Optional[datetime] = None
    description: Optional[str] = None