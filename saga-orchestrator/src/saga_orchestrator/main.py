"""Main entry point for SAGA Orchestrator service."""

import uvicorn

from .core.app import create_app
from .core.config import get_settings


def main() -> None:
    """Run the SAGA Orchestrator service."""
    settings = get_settings()
    app = create_app()
    
    uvicorn.run(
        app,
        host=settings.host,
        port=settings.port,
        log_level=settings.log_level.lower(),
        access_log=True,
        server_header=False,
    )


if __name__ == "__main__":
    main()