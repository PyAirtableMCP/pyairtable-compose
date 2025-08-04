"""Base event bus interface."""

from abc import ABC, abstractmethod
from typing import Callable

from ..models.events import Event


class EventBus(ABC):
    """Abstract base class for event bus implementations."""
    
    @abstractmethod
    async def start(self) -> None:
        """Start the event bus."""
        pass
    
    @abstractmethod
    async def stop(self) -> None:
        """Stop the event bus."""
        pass
    
    @abstractmethod
    async def publish_event(self, event: Event, topic: str = None) -> None:
        """Publish an event to the bus."""
        pass
    
    @abstractmethod
    async def subscribe(
        self, 
        topics: list[str], 
        consumer_group: str,
        handler: Callable[[Event], None]
    ) -> None:
        """Subscribe to events from topics."""
        pass