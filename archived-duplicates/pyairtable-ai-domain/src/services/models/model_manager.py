"""Model Manager for serving local and hosted models"""
import asyncio
import time
from typing import Dict, List, Optional, Any, Union
from datetime import datetime, timedelta
from pathlib import Path
import psutil

from ...core.config import get_settings
from ...core.logging import get_logger, ModelPerformanceLogger
from ...utils.redis_client import get_redis_client


class ModelManager:
    """Manages model loading, caching, and serving"""
    
    def __init__(self):
        self.settings = get_settings()
        self.logger = get_logger(__name__)
        self.performance_logger = ModelPerformanceLogger()
        
        # Model cache
        self._loaded_models: Dict[str, Any] = {}
        self._model_metadata: Dict[str, Dict[str, Any]] = {}
        self._model_usage: Dict[str, Dict[str, Any]] = {}
        
        # Resource monitoring
        self._max_memory_usage = 0.8  # 80% of available memory
        self._cleanup_threshold = 0.9  # Start cleanup at 90% cache capacity
        
        # Initialize if configured
        if self.settings.enable_model_warming:
            asyncio.create_task(self._warm_popular_models())
    
    async def load_model(
        self, 
        model_name: str, 
        model_type: str = "embedding",
        force_reload: bool = False
    ) -> Any:
        """Load a model into memory"""
        cache_key = f"{model_type}:{model_name}"
        
        # Return cached model if available
        if cache_key in self._loaded_models and not force_reload:
            self._update_model_usage(cache_key)
            return self._loaded_models[cache_key]
        
        # Check memory availability
        if not self._check_memory_availability():
            await self._cleanup_models()
        
        start_time = time.time()
        
        try:
            if model_type == "embedding":
                model = await self._load_embedding_model(model_name)
            elif model_type == "classification":
                model = await self._load_classification_model(model_name)
            elif model_type == "generation":
                model = await self._load_generation_model(model_name)
            else:
                raise ValueError(f"Unsupported model type: {model_type}")
            
            load_time = time.time() - start_time
            
            # Cache the model
            self._loaded_models[cache_key] = model
            self._model_metadata[cache_key] = {
                "loaded_at": datetime.utcnow(),
                "load_time": load_time,
                "memory_usage": self._estimate_model_memory(model),
                "access_count": 0,
                "last_accessed": datetime.utcnow()
            }
            
            self.logger.info(
                f"Model loaded successfully",
                model_name=model_name,
                model_type=model_type,
                load_time=load_time
            )
            
            return model
            
        except Exception as e:
            self.logger.error(
                f"Failed to load model",
                model_name=model_name,
                model_type=model_type,
                error=str(e)
            )
            raise
    
    async def _load_embedding_model(self, model_name: str) -> Any:
        """Load embedding model"""
        try:
            from sentence_transformers import SentenceTransformer
            
            # Map common model names to actual model paths
            model_mapping = {
                "all-MiniLM-L6-v2": "sentence-transformers/all-MiniLM-L6-v2",
                "all-mpnet-base-v2": "sentence-transformers/all-mpnet-base-v2",
                "multi-qa-MiniLM-L6-cos-v1": "sentence-transformers/multi-qa-MiniLM-L6-cos-v1",
            }
            
            actual_model_name = model_mapping.get(model_name, model_name)
            model = SentenceTransformer(actual_model_name)
            
            return model
            
        except Exception as e:
            self.logger.error(f"Failed to load embedding model {model_name}: {str(e)}")
            raise
    
    async def _load_classification_model(self, model_name: str) -> Any:
        """Load classification model"""
        try:
            from transformers import AutoTokenizer, AutoModelForSequenceClassification
            
            tokenizer = AutoTokenizer.from_pretrained(model_name)
            model = AutoModelForSequenceClassification.from_pretrained(model_name)
            
            return {"tokenizer": tokenizer, "model": model}
            
        except Exception as e:
            self.logger.error(f"Failed to load classification model {model_name}: {str(e)}")
            raise
    
    async def _load_generation_model(self, model_name: str) -> Any:
        """Load text generation model"""
        try:
            from transformers import AutoTokenizer, AutoModelForCausalLM
            
            tokenizer = AutoTokenizer.from_pretrained(model_name)
            model = AutoModelForCausalLM.from_pretrained(model_name)
            
            return {"tokenizer": tokenizer, "model": model}
            
        except Exception as e:
            self.logger.error(f"Failed to load generation model {model_name}: {str(e)}")
            raise
    
    async def generate_embeddings(
        self, 
        texts: Union[str, List[str]], 
        model_name: str = "all-MiniLM-L6-v2",
        normalize: bool = True
    ) -> List[List[float]]:
        """Generate embeddings for text(s)"""
        start_time = time.time()
        
        try:
            # Load model
            model = await self.load_model(model_name, "embedding")
            
            # Convert single string to list
            if isinstance(texts, str):
                texts = [texts]
            
            # Generate embeddings
            embeddings = model.encode(
                texts,
                normalize_embeddings=normalize,
                convert_to_numpy=True
            )
            
            # Convert to list of lists
            result = embeddings.tolist()
            
            # Log performance
            inference_time = (time.time() - start_time) * 1000
            self.performance_logger.log_inference(
                model=model_name,
                provider="local",
                latency_ms=inference_time,
                input_length=sum(len(text.split()) for text in texts),
                output_length=len(result) * len(result[0]) if result else 0,
                success=True
            )
            
            return result
            
        except Exception as e:
            inference_time = (time.time() - start_time) * 1000
            self.performance_logger.log_inference(
                model=model_name,
                provider="local",
                latency_ms=inference_time,
                input_length=0,
                output_length=0,
                success=False,
                error=str(e)
            )
            raise
    
    async def classify_text(
        self, 
        text: str, 
        model_name: str,
        return_probabilities: bool = True
    ) -> Dict[str, Any]:
        """Classify text using a classification model"""
        start_time = time.time()
        
        try:
            # Load model
            model_dict = await self.load_model(model_name, "classification")
            tokenizer = model_dict["tokenizer"]
            model = model_dict["model"]
            
            # Tokenize input
            inputs = tokenizer(text, return_tensors="pt", truncation=True, padding=True)
            
            # Perform inference
            import torch
            with torch.no_grad():
                outputs = model(**inputs)
                predictions = torch.nn.functional.softmax(outputs.logits, dim=-1)
            
            # Get results
            predicted_class = predictions.argmax().item()
            confidence = predictions.max().item()
            
            result = {
                "predicted_class": predicted_class,
                "confidence": confidence,
            }
            
            if return_probabilities:
                result["probabilities"] = predictions.squeeze().tolist()
            
            # Log performance
            inference_time = (time.time() - start_time) * 1000
            self.performance_logger.log_inference(
                model=model_name,
                provider="local",
                latency_ms=inference_time,
                input_length=len(text.split()),
                output_length=1,
                success=True
            )
            
            return result
            
        except Exception as e:
            inference_time = (time.time() - start_time) * 1000
            self.performance_logger.log_inference(
                model=model_name,
                provider="local",
                latency_ms=inference_time,
                input_length=len(text.split()) if text else 0,
                output_length=0,
                success=False,
                error=str(e)
            )
            raise
    
    async def generate_text(
        self, 
        prompt: str, 
        model_name: str,
        max_length: int = 100,
        temperature: float = 0.7,
        top_p: float = 0.9
    ) -> str:
        """Generate text using a generation model"""
        start_time = time.time()
        
        try:
            # Load model
            model_dict = await self.load_model(model_name, "generation")
            tokenizer = model_dict["tokenizer"]
            model = model_dict["model"]
            
            # Tokenize input
            inputs = tokenizer(prompt, return_tensors="pt")
            
            # Generate text
            import torch
            with torch.no_grad():
                outputs = model.generate(
                    inputs.input_ids,
                    max_length=max_length,
                    temperature=temperature,
                    top_p=top_p,
                    do_sample=True,
                    pad_token_id=tokenizer.eos_token_id
                )
            
            # Decode output
            generated_text = tokenizer.decode(outputs[0], skip_special_tokens=True)
            
            # Remove the prompt from the output
            if generated_text.startswith(prompt):
                generated_text = generated_text[len(prompt):].strip()
            
            # Log performance
            inference_time = (time.time() - start_time) * 1000
            self.performance_logger.log_inference(
                model=model_name,
                provider="local",
                latency_ms=inference_time,
                input_length=len(prompt.split()),
                output_length=len(generated_text.split()),
                success=True
            )
            
            return generated_text
            
        except Exception as e:
            inference_time = (time.time() - start_time) * 1000
            self.performance_logger.log_inference(
                model=model_name,
                provider="local",
                latency_ms=inference_time,
                input_length=len(prompt.split()) if prompt else 0,
                output_length=0,
                success=False,
                error=str(e)
            )
            raise
    
    def get_loaded_models(self) -> Dict[str, Dict[str, Any]]:
        """Get information about currently loaded models"""
        return {
            model_key: {
                **metadata,
                "cache_key": model_key,
                "model_loaded": True
            }
            for model_key, metadata in self._model_metadata.items()
        }
    
    def get_model_stats(self) -> Dict[str, Any]:
        """Get model usage statistics"""
        total_memory = sum(
            metadata.get("memory_usage", 0) 
            for metadata in self._model_metadata.values()
        )
        
        return {
            "loaded_models_count": len(self._loaded_models),
            "total_memory_usage_mb": total_memory,
            "cache_hit_rate": self._calculate_cache_hit_rate(),
            "most_used_models": self._get_most_used_models(),
            "system_memory_usage": psutil.virtual_memory().percent
        }
    
    async def unload_model(self, model_name: str, model_type: str = "embedding") -> bool:
        """Unload a specific model from memory"""
        cache_key = f"{model_type}:{model_name}"
        
        if cache_key in self._loaded_models:
            del self._loaded_models[cache_key]
            del self._model_metadata[cache_key]
            
            self.logger.info(f"Unloaded model: {cache_key}")
            return True
        
        return False
    
    async def _warm_popular_models(self) -> None:
        """Pre-load popular models based on usage patterns"""
        try:
            # Load usage data from Redis if available
            redis_client = await get_redis_client()
            if redis_client:
                popular_models = await self._get_popular_models_from_redis()
                
                for model_name, model_type in popular_models:
                    try:
                        await self.load_model(model_name, model_type)
                        self.logger.info(f"Pre-warmed model: {model_type}:{model_name}")
                    except Exception as e:
                        self.logger.warning(f"Failed to warm model {model_name}: {str(e)}")
            
        except Exception as e:
            self.logger.error(f"Model warming failed: {str(e)}")
    
    async def _get_popular_models_from_redis(self) -> List[tuple]:
        """Get popular models from Redis usage data"""
        # This would query Redis for model usage patterns
        # For now, return default popular models
        return [
            ("all-MiniLM-L6-v2", "embedding"),
            ("all-mpnet-base-v2", "embedding"),
        ]
    
    def _check_memory_availability(self) -> bool:
        """Check if sufficient memory is available for loading new models"""
        memory = psutil.virtual_memory()
        return memory.percent < (self._max_memory_usage * 100)
    
    async def _cleanup_models(self) -> None:
        """Remove least recently used models to free memory"""
        if len(self._loaded_models) <= 1:
            return
        
        # Sort models by last accessed time
        sorted_models = sorted(
            self._model_metadata.items(),
            key=lambda x: x[1]["last_accessed"]
        )
        
        # Remove oldest models until we're under the cleanup threshold
        target_count = int(self.settings.model_cache_size * self._cleanup_threshold)
        
        while len(self._loaded_models) > target_count and sorted_models:
            cache_key, _ = sorted_models.pop(0)
            if cache_key in self._loaded_models:
                del self._loaded_models[cache_key]
                del self._model_metadata[cache_key]
                self.logger.info(f"Cleaned up model: {cache_key}")
    
    def _update_model_usage(self, cache_key: str) -> None:
        """Update model usage statistics"""
        if cache_key in self._model_metadata:
            self._model_metadata[cache_key]["access_count"] += 1
            self._model_metadata[cache_key]["last_accessed"] = datetime.utcnow()
    
    def _estimate_model_memory(self, model: Any) -> float:
        """Estimate memory usage of a model in MB"""
        try:
            # For transformers models
            if hasattr(model, 'num_parameters'):
                return model.num_parameters() * 4 / (1024 * 1024)  # 4 bytes per parameter
            
            # For sentence transformers
            if hasattr(model, '_modules'):
                total_params = sum(p.numel() for p in model.parameters())
                return total_params * 4 / (1024 * 1024)
            
            # Fallback estimation
            return 100.0  # MB
            
        except Exception:
            return 100.0  # MB fallback
    
    def _calculate_cache_hit_rate(self) -> float:
        """Calculate cache hit rate"""
        total_accesses = sum(
            metadata.get("access_count", 0) 
            for metadata in self._model_metadata.values()
        )
        
        if total_accesses == 0:
            return 0.0
        
        # This is a simplified calculation
        # In a real implementation, you'd track cache hits vs misses
        return min(1.0, len(self._loaded_models) / 10.0)
    
    def _get_most_used_models(self, limit: int = 5) -> List[Dict[str, Any]]:
        """Get most frequently used models"""
        sorted_models = sorted(
            self._model_metadata.items(),
            key=lambda x: x[1].get("access_count", 0),
            reverse=True
        )
        
        return [
            {
                "model": cache_key,
                "access_count": metadata.get("access_count", 0),
                "last_accessed": metadata.get("last_accessed"),
            }
            for cache_key, metadata in sorted_models[:limit]
        ]
    
    async def health_check(self) -> Dict[str, Any]:
        """Check model manager health"""
        return {
            "status": "healthy",
            "loaded_models": len(self._loaded_models),
            "memory_usage_percent": psutil.virtual_memory().percent,
            "cache_size": len(self._loaded_models),
            "max_cache_size": self.settings.model_cache_size
        }
    
    async def close(self) -> None:
        """Clean up resources"""
        self._loaded_models.clear()
        self._model_metadata.clear()
        self.logger.info("Model manager shut down")