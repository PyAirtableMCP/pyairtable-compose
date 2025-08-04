"""Main application entry point."""

import uvicorn

from src.core.app import app
from src.core.config import get_settings


def main() -> None:
    """Run the application."""
    settings = get_settings()
    
    uvicorn.run(
        "src.main:app" if settings.reload else app,
        host=settings.host,
        port=settings.port,
        workers=settings.workers if not settings.reload else 1,
        reload=settings.reload,
        access_log=settings.is_development,
        log_level=settings.observability.log_level.lower(),
    )


if __name__ == "__main__":
    main()