"""Event management endpoints."""

import logging
from typing import List, Dict, Any

from fastapi import APIRouter, Depends, HTTPException, Request, Query
from pydantic import BaseModel

from ..models.events import Event, EventType
from ..saga_engine.event_store import EventStore

logger = logging.getLogger(__name__)
router = APIRouter()


class PublishEventRequest(BaseModel):
    """Request to publish an event."""
    event_type: EventType
    aggregate_id: str
    aggregate_type: str
    data: Dict[str, Any]
    correlation_id: str = None


class EventListResponse(BaseModel):
    """Response for listing events."""
    events: List[Event]
    total: int


def get_event_store(request: Request) -> EventStore:
    """Get event store from app state."""
    if not hasattr(request.app.state, "event_store"):
        raise HTTPException(status_code=500, detail="Event store not initialized")
    return request.app.state.event_store


@router.post("/publish")
async def publish_event(
    request: PublishEventRequest,
    app_request: Request
) -> Dict[str, str]:
    """Publish an event to the event store and event bus."""
    try:
        event = Event(
            type=request.event_type,
            aggregate_id=request.aggregate_id,
            aggregate_type=request.aggregate_type,
            version=1,  # This should be calculated properly
            data=request.data,
            correlation_id=request.correlation_id
        )
        
        # Store event
        event_store = get_event_store(app_request)
        await event_store.append_events(
            f"{request.aggregate_type}-{request.aggregate_id}",
            [event]
        )
        
        # Publish to event bus
        if hasattr(app_request.app.state, "event_bus"):
            await app_request.app.state.event_bus.publish_event(event)
        
        return {"status": "published", "event_id": event.id}
        
    except Exception as e:
        logger.error(f"Failed to publish event: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/stream/{stream_id}", response_model=EventListResponse)
async def get_stream_events(
    stream_id: str,
    from_version: int = Query(0, ge=0, description="Start from version"),
    to_version: int = Query(None, ge=0, description="End at version"),
    event_store: EventStore = Depends(get_event_store)
) -> EventListResponse:
    """Get events from a specific stream."""
    try:
        events = await event_store.read_stream(
            stream_id=stream_id,
            from_version=from_version,
            to_version=to_version
        )
        
        return EventListResponse(
            events=events,
            total=len(events)
        )
        
    except Exception as e:
        logger.error(f"Failed to get stream events: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/all", response_model=EventListResponse)
async def get_all_events(
    from_position: int = Query(0, ge=0, description="Start from position"),
    max_count: int = Query(100, ge=1, le=1000, description="Maximum events to return"),
    event_store: EventStore = Depends(get_event_store)
) -> EventListResponse:
    """Get all events across all streams."""
    try:
        events = await event_store.read_all_events(
            from_position=from_position,
            max_count=max_count
        )
        
        return EventListResponse(
            events=events,
            total=len(events)
        )
        
    except Exception as e:
        logger.error(f"Failed to get all events: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/types")
async def get_event_types() -> Dict[str, List[str]]:
    """Get all available event types."""
    return {
        "event_types": [event_type.value for event_type in EventType]
    }


@router.post("/replay/{stream_id}")
async def replay_events(
    stream_id: str,
    from_version: int = Query(0, ge=0, description="Start replay from version"),
    app_request: Request,
    event_store: EventStore = Depends(get_event_store)
) -> Dict[str, Any]:
    """Replay events from a stream to the event bus."""
    try:
        events = await event_store.read_stream(
            stream_id=stream_id,
            from_version=from_version
        )
        
        if not hasattr(app_request.app.state, "event_bus"):
            raise HTTPException(status_code=500, detail="Event bus not available")
        
        replayed_count = 0
        for event in events:
            await app_request.app.state.event_bus.publish_event(event)
            replayed_count += 1
        
        return {
            "status": "completed",
            "stream_id": stream_id,
            "events_replayed": replayed_count,
            "from_version": from_version
        }
        
    except Exception as e:
        logger.error(f"Failed to replay events: {e}")
        raise HTTPException(status_code=500, detail=str(e))