"""Redis-based event bus implementation for SAGA Orchestrator."""

import asyncio
import json
import logging
from typing import Callable, Dict, Any

import redis.asyncio as redis

from .base import EventBus
from ..models.events import Event, EventType

logger = logging.getLogger(__name__)


class RedisEventBus(EventBus):
    """Redis-based event bus for reliable event distribution."""
    
    def __init__(self, redis_client: redis.Redis):
        self.redis = redis_client
        self.subscribers: Dict[str, Callable[[Event], None]] = {}
        self.running = False
        self.consumer_tasks: list[asyncio.Task] = []
        
    async def start(self) -> None:
        """Start the Redis event bus."""
        logger.info("Starting Redis event bus...")
        self.running = True
        
    async def stop(self) -> None:
        """Stop the Redis event bus."""
        logger.info("Stopping Redis event bus...")
        self.running = False
        
        # Cancel all consumer tasks
        for task in self.consumer_tasks:
            task.cancel()
        
        # Wait for tasks to complete
        if self.consumer_tasks:
            await asyncio.gather(*self.consumer_tasks, return_exceptions=True)
        
        self.consumer_tasks.clear()
        
    async def publish_event(self, event: Event, topic: str = None) -> None:
        """Publish event to Redis stream."""
        if not topic:
            topic = f"pyairtable.{event.aggregate_type}.{event.type.value}"
        
        try:
            event_data = event.to_dict()
            
            # Use Redis Streams for reliable message delivery
            await self.redis.xadd(
                topic,
                event_data,
                maxlen=10000  # Keep last 10k events per stream
            )
            
            logger.info(f"Published event {event.type.value} to topic {topic}")
            
        except Exception as e:
            logger.error(f"Failed to publish event to Redis: {e}")
            raise
    
    async def subscribe(
        self, 
        topics: list[str], 
        consumer_group: str,
        handler: Callable[[Event], None]
    ) -> None:
        """Subscribe to events from Redis streams."""
        for topic in topics:
            try:
                # Create consumer group if it doesn't exist
                try:
                    await self.redis.xgroup_create(
                        topic, 
                        consumer_group, 
                        id='0', 
                        mkstream=True
                    )
                except redis.ResponseError as e:
                    # Group already exists
                    if "BUSYGROUP" not in str(e):
                        raise
                
                # Start consumer task for this topic
                task = asyncio.create_task(
                    self._consume_events(topic, consumer_group, handler)
                )
                self.consumer_tasks.append(task)
                
                logger.info(f"Subscribed to topic {topic} with group {consumer_group}")
                
            except Exception as e:
                logger.error(f"Failed to subscribe to topic {topic}: {e}")
                raise
    
    async def _consume_events(
        self, 
        topic: str, 
        consumer_group: str, 
        handler: Callable[[Event], None]
    ) -> None:
        """Consume events from Redis stream."""
        consumer_name = f"{consumer_group}-consumer-{id(self)}"
        
        while self.running:
            try:
                # Read new messages
                messages = await self.redis.xreadgroup(
                    consumer_group,
                    consumer_name,
                    {topic: '>'},
                    count=1,
                    block=1000  # Block for 1 second
                )
                
                for stream, msgs in messages:
                    for msg_id, fields in msgs:
                        try:
                            # Convert Redis fields to Event
                            event_data = {k.decode(): v.decode() for k, v in fields.items()}
                            
                            # Parse nested JSON fields
                            for key in ['data', 'metadata']:
                                if key in event_data:
                                    event_data[key] = json.loads(event_data[key])
                            
                            # Convert timestamp
                            if 'timestamp' in event_data:
                                from datetime import datetime
                                event_data['timestamp'] = datetime.fromisoformat(event_data['timestamp'])
                            
                            # Create Event object
                            event = Event.from_dict(event_data)
                            
                            # Handle event
                            await handler(event)
                            
                            # Acknowledge message
                            await self.redis.xack(topic, consumer_group, msg_id)
                            
                        except Exception as e:
                            logger.error(f"Error processing event {msg_id}: {e}")
                            # Don't acknowledge failed messages
                            
            except asyncio.CancelledError:
                logger.info(f"Consumer for topic {topic} cancelled")
                break
            except Exception as e:
                logger.error(f"Error consuming from topic {topic}: {e}")
                await asyncio.sleep(5)  # Wait before retrying