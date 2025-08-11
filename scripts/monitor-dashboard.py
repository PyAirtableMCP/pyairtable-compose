#!/usr/bin/env python3
"""
Emergency Stabilization Day 5: Monitoring Dashboard
Real-time web dashboard for PyAirtable service health monitoring.
"""

import asyncio
import aiohttp
import json
import time
from datetime import datetime
from aiohttp import web, WSMsgType
from pathlib import Path
import logging
import argparse
import os
import sys

# Import our health checker
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

# Import the health checker classes directly to avoid import issues
import asyncio
import aiohttp
import json
import time
from datetime import datetime
from typing import Dict, List, Optional
from dataclasses import dataclass, asdict

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Import HealthChecker from our health-check script
try:
    from health_check import HealthChecker
except ImportError:
    # If import fails, we'll define a minimal version
    logger.error("Could not import HealthChecker, using fallback")
    
    @dataclass
    class ServiceHealth:
        name: str
        url: str
        status: str
        response_time_ms: Optional[float]
        last_check: str
        error_message: Optional[str] = None
        status_code: Optional[int] = None

    @dataclass  
    class HealthSummary:
        timestamp: str
        total_services: int
        healthy_services: int
        degraded_services: int
        failed_services: int
        services: List[ServiceHealth]

    class HealthChecker:
        def __init__(self):
            self.services = {
                'api-gateway': {'url': 'http://localhost:8000/api/health', 'timeout': 5},
                'llm-orchestrator': {'url': 'http://localhost:8003/health', 'timeout': 10},
                'mcp-server': {'url': 'http://localhost:8001/health', 'timeout': 5},
                'airtable-gateway': {'url': 'http://localhost:8002/health', 'timeout': 5},
                'platform-services': {'url': 'http://localhost:8007/health', 'timeout': 5},
                'automation-services': {'url': 'http://localhost:8006/health', 'timeout': 5},
                'saga-orchestrator': {'url': 'http://localhost:8008/health/', 'timeout': 5},
                'frontend': {'url': 'http://localhost:3000/api/health', 'timeout': 10},
                'frontend-ready': {'url': 'http://localhost:3000/health/ready', 'timeout': 10}
            }
            self.session = None
            
        async def __aenter__(self):
            connector = aiohttp.TCPConnector(limit=10, limit_per_host=5)
            self.session = aiohttp.ClientSession(connector=connector, timeout=aiohttp.ClientTimeout(total=30))
            return self
            
        async def __aexit__(self, exc_type, exc_val, exc_tb):
            if self.session:
                await self.session.close()
                
        async def check_all_services(self):
            tasks = []
            for name, config in self.services.items():
                tasks.append(self.check_service_health(name, config))
            
            service_healths = await asyncio.gather(*tasks, return_exceptions=True)
            valid_healths = []
            
            for i, health in enumerate(service_healths):
                if isinstance(health, Exception):
                    service_name = list(self.services.keys())[i]
                    valid_healths.append(ServiceHealth(
                        name=service_name,
                        url=self.services[service_name]['url'],
                        status="DOWN",
                        response_time_ms=None,
                        last_check=datetime.now().isoformat(),
                        error_message=f"Check failed: {str(health)}"
                    ))
                else:
                    valid_healths.append(health)
            
            healthy_count = sum(1 for h in valid_healths if h.status == "UP")
            degraded_count = sum(1 for h in valid_healths if h.status == "DEGRADED") 
            failed_count = sum(1 for h in valid_healths if h.status == "DOWN")
            
            return HealthSummary(
                timestamp=datetime.now().isoformat(),
                total_services=len(valid_healths),
                healthy_services=healthy_count,
                degraded_services=degraded_count,
                failed_services=failed_count,
                services=valid_healths
            )
            
        async def check_service_health(self, name: str, config: Dict) -> ServiceHealth:
            url = config['url']
            timeout = config.get('timeout', 5)
            start_time = time.time()
            
            try:
                async with self.session.get(url, timeout=aiohttp.ClientTimeout(total=timeout)) as response:
                    response_time_ms = (time.time() - start_time) * 1000
                    
                    if response.status == 200:
                        if response_time_ms < 1000:
                            status = "UP"
                        elif response_time_ms < 5000:
                            status = "DEGRADED"
                        else:
                            status = "DOWN"
                    else:
                        status = "DOWN"
                    
                    try:
                        response_text = await response.text()
                        error_message = None if status == "UP" else f"HTTP {response.status}: {response_text[:200]}"
                    except:
                        error_message = None if status == "UP" else f"HTTP {response.status}"
                    
                    return ServiceHealth(
                        name=name,
                        url=url,
                        status=status,
                        response_time_ms=round(response_time_ms, 2),
                        last_check=datetime.now().isoformat(),
                        error_message=error_message,
                        status_code=response.status
                    )
                    
            except asyncio.TimeoutError:
                response_time_ms = (time.time() - start_time) * 1000
                return ServiceHealth(
                    name=name,
                    url=url,
                    status="DOWN",
                    response_time_ms=round(response_time_ms, 2),
                    last_check=datetime.now().isoformat(),
                    error_message=f"Timeout after {timeout}s",
                    status_code=None
                )
            except Exception as e:
                response_time_ms = (time.time() - start_time) * 1000
                return ServiceHealth(
                    name=name,
                    url=url,
                    status="DOWN",
                    response_time_ms=round(response_time_ms, 2),
                    last_check=datetime.now().isoformat(),
                    error_message=str(e),
                    status_code=None
                )

class MonitoringDashboard:
    def __init__(self, port: int = 9999):
        self.port = port
        self.app = web.Application()
        self.websockets = set()
        self.health_checker = None
        self.current_health = None
        self.monitoring_task = None
        
        # Setup routes
        self.setup_routes()
    
    def setup_routes(self):
        """Setup web application routes"""
        self.app.router.add_get('/', self.serve_dashboard)
        self.app.router.add_get('/health', self.serve_health_api)
        self.app.router.add_get('/ws', self.websocket_handler)
        self.app.router.add_static('/static', path=str(Path(__file__).parent), name='static')

    async def serve_dashboard(self, request):
        """Serve the main dashboard HTML page"""
        html_content = self.get_dashboard_html()
        return web.Response(text=html_content, content_type='text/html')

    async def serve_health_api(self, request):
        """Serve health data as JSON API"""
        if self.current_health:
            return web.json_response(self.current_health)
        else:
            return web.json_response({"error": "No health data available"}, status=503)

    async def websocket_handler(self, request):
        """WebSocket handler for real-time updates"""
        ws = web.WebSocketResponse()
        await ws.prepare(request)
        
        self.websockets.add(ws)
        logger.info(f"WebSocket connected. Total connections: {len(self.websockets)}")
        
        try:
            # Send current health data immediately
            if self.current_health:
                await ws.send_str(json.dumps(self.current_health))
            
            async for msg in ws:
                if msg.type == WSMsgType.ERROR:
                    logger.error(f'WebSocket error: {ws.exception()}')
                    break
                elif msg.type == WSMsgType.CLOSE:
                    break
        except Exception as e:
            logger.error(f"WebSocket error: {e}")
        finally:
            self.websockets.discard(ws)
            logger.info(f"WebSocket disconnected. Total connections: {len(self.websockets)}")
        
        return ws

    async def broadcast_health_update(self, health_data):
        """Broadcast health update to all connected WebSocket clients"""
        if not self.websockets:
            return
        
        message = json.dumps(health_data)
        disconnected = set()
        
        for ws in self.websockets:
            try:
                await ws.send_str(message)
            except Exception as e:
                logger.warning(f"Failed to send to WebSocket: {e}")
                disconnected.add(ws)
        
        # Clean up disconnected sockets
        self.websockets -= disconnected
        if disconnected:
            logger.info(f"Cleaned up {len(disconnected)} disconnected WebSockets")

    async def health_monitoring_loop(self, interval: int = 30):
        """Background task for continuous health monitoring"""
        logger.info(f"Starting health monitoring loop (interval: {interval}s)")
        
        self.health_checker = HealthChecker()
        await self.health_checker.__aenter__()
        
        try:
            while True:
                try:
                    # Get health status
                    health_summary = await self.health_checker.check_all_services()
                    health_data = {
                        'timestamp': health_summary.timestamp,
                        'total_services': health_summary.total_services,
                        'healthy_services': health_summary.healthy_services,
                        'degraded_services': health_summary.degraded_services,
                        'failed_services': health_summary.failed_services,
                        'services': [
                            {
                                'name': s.name,
                                'url': s.url,
                                'status': s.status,
                                'response_time_ms': s.response_time_ms,
                                'last_check': s.last_check,
                                'error_message': s.error_message,
                                'status_code': s.status_code
                            }
                            for s in health_summary.services
                        ]
                    }
                    
                    self.current_health = health_data
                    
                    # Broadcast to WebSocket clients
                    await self.broadcast_health_update(health_data)
                    
                    logger.info(f"Health update: {health_data['healthy_services']}/{health_data['total_services']} services healthy")
                    
                    await asyncio.sleep(interval)
                    
                except asyncio.CancelledError:
                    break
                except Exception as e:
                    logger.error(f"Error in health monitoring loop: {e}")
                    await asyncio.sleep(5)
        finally:
            if self.health_checker:
                await self.health_checker.__aexit__(None, None, None)

    def get_dashboard_html(self):
        """Generate the dashboard HTML"""
        return '''
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>PyAirtable Service Health Dashboard</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            color: #333;
        }
        
        .container {
            max-width: 1200px;
            margin: 0 auto;
            padding: 20px;
        }
        
        .header {
            text-align: center;
            color: white;
            margin-bottom: 30px;
        }
        
        .header h1 {
            font-size: 2.5em;
            margin-bottom: 10px;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
        }
        
        .summary-cards {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        
        .summary-card {
            background: white;
            border-radius: 12px;
            padding: 20px;
            text-align: center;
            box-shadow: 0 8px 25px rgba(0,0,0,0.1);
            transition: transform 0.2s ease;
        }
        
        .summary-card:hover {
            transform: translateY(-5px);
        }
        
        .summary-card .number {
            font-size: 2.5em;
            font-weight: bold;
            margin-bottom: 5px;
        }
        
        .summary-card .label {
            color: #666;
            font-size: 0.9em;
            text-transform: uppercase;
            letter-spacing: 1px;
        }
        
        .summary-card.healthy .number { color: #27AE60; }
        .summary-card.degraded .number { color: #F39C12; }
        .summary-card.failed .number { color: #E74C3C; }
        .summary-card.total .number { color: #3498DB; }
        
        .services-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(320px, 1fr));
            gap: 20px;
        }
        
        .service-card {
            background: white;
            border-radius: 12px;
            padding: 20px;
            box-shadow: 0 8px 25px rgba(0,0,0,0.1);
            transition: all 0.3s ease;
            border-left: 5px solid #ddd;
        }
        
        .service-card.UP {
            border-left-color: #27AE60;
            background: linear-gradient(135deg, #ffffff 0%, #f8fff8 100%);
        }
        
        .service-card.DEGRADED {
            border-left-color: #F39C12;
            background: linear-gradient(135deg, #ffffff 0%, #fffbf0 100%);
        }
        
        .service-card.DOWN {
            border-left-color: #E74C3C;
            background: linear-gradient(135deg, #ffffff 0%, #fff5f5 100%);
        }
        
        .service-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 15px;
        }
        
        .service-name {
            font-size: 1.2em;
            font-weight: bold;
            color: #2c3e50;
        }
        
        .status-badge {
            padding: 6px 12px;
            border-radius: 20px;
            font-size: 0.8em;
            font-weight: bold;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }
        
        .status-badge.UP {
            background: #27AE60;
            color: white;
        }
        
        .status-badge.DEGRADED {
            background: #F39C12;
            color: white;
        }
        
        .status-badge.DOWN {
            background: #E74C3C;
            color: white;
        }
        
        .service-details {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 10px;
            font-size: 0.9em;
            color: #666;
        }
        
        .detail-item {
            display: flex;
            justify-content: space-between;
        }
        
        .detail-label {
            font-weight: 600;
        }
        
        .response-time {
            font-weight: bold;
        }
        
        .response-time.fast { color: #27AE60; }
        .response-time.medium { color: #F39C12; }
        .response-time.slow { color: #E74C3C; }
        
        .error-message {
            margin-top: 10px;
            padding: 10px;
            background: #ffe6e6;
            border: 1px solid #ffcccc;
            border-radius: 6px;
            font-size: 0.85em;
            color: #cc0000;
            word-break: break-word;
        }
        
        .connection-status {
            position: fixed;
            top: 20px;
            right: 20px;
            padding: 10px 15px;
            border-radius: 6px;
            font-size: 0.9em;
            font-weight: bold;
            transition: all 0.3s ease;
            z-index: 1000;
        }
        
        .connection-status.connected {
            background: #27AE60;
            color: white;
        }
        
        .connection-status.disconnected {
            background: #E74C3C;
            color: white;
        }
        
        .last-update {
            text-align: center;
            color: white;
            margin-top: 20px;
            font-size: 0.9em;
            opacity: 0.8;
        }
        
        .loading {
            text-align: center;
            color: white;
            font-size: 1.5em;
            margin-top: 100px;
        }
        
        @media (max-width: 768px) {
            .container {
                padding: 10px;
            }
            
            .header h1 {
                font-size: 2em;
            }
            
            .services-grid {
                grid-template-columns: 1fr;
            }
            
            .service-details {
                grid-template-columns: 1fr;
            }
        }
        
        /* Animation for status changes */
        @keyframes pulse {
            0% { transform: scale(1); }
            50% { transform: scale(1.05); }
            100% { transform: scale(1); }
        }
        
        .service-card.status-changed {
            animation: pulse 0.5s ease-in-out;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🚀 PyAirtable Health Dashboard</h1>
            <p>Real-time monitoring for all services</p>
        </div>
        
        <div class="connection-status" id="connectionStatus">Connecting...</div>
        
        <div id="loading" class="loading">
            Loading service status...
        </div>
        
        <div id="dashboard" style="display: none;">
            <div class="summary-cards" id="summaryCards">
                <!-- Summary cards will be populated here -->
            </div>
            
            <div class="services-grid" id="servicesGrid">
                <!-- Service cards will be populated here -->
            </div>
            
            <div class="last-update" id="lastUpdate">
                <!-- Last update time will be shown here -->
            </div>
        </div>
    </div>

    <script>
        class HealthDashboard {
            constructor() {
                this.ws = null;
                this.previousData = null;
                this.connectionStatus = document.getElementById('connectionStatus');
                this.loading = document.getElementById('loading');
                this.dashboard = document.getElementById('dashboard');
                
                this.connect();
                
                // Reconnect on page visibility change
                document.addEventListener('visibilitychange', () => {
                    if (document.visibilityState === 'visible' && (!this.ws || this.ws.readyState === WebSocket.CLOSED)) {
                        this.connect();
                    }
                });
            }
            
            connect() {
                const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
                const wsUrl = `${protocol}//${window.location.host}/ws`;
                
                this.ws = new WebSocket(wsUrl);
                
                this.ws.onopen = () => {
                    console.log('WebSocket connected');
                    this.connectionStatus.textContent = '🟢 Connected';
                    this.connectionStatus.className = 'connection-status connected';
                };
                
                this.ws.onmessage = (event) => {
                    const data = JSON.parse(event.data);
                    this.updateDashboard(data);
                };
                
                this.ws.onclose = () => {
                    console.log('WebSocket disconnected');
                    this.connectionStatus.textContent = '🔴 Disconnected';
                    this.connectionStatus.className = 'connection-status disconnected';
                    
                    // Attempt to reconnect after 5 seconds
                    setTimeout(() => this.connect(), 5000);
                };
                
                this.ws.onerror = (error) => {
                    console.error('WebSocket error:', error);
                    this.connectionStatus.textContent = '⚠️ Error';
                    this.connectionStatus.className = 'connection-status disconnected';
                };
            }
            
            updateDashboard(data) {
                this.loading.style.display = 'none';
                this.dashboard.style.display = 'block';
                
                this.updateSummaryCards(data);
                this.updateServicesGrid(data);
                this.updateLastUpdate(data.timestamp);
                
                this.previousData = data;
            }
            
            updateSummaryCards(data) {
                const summaryCards = document.getElementById('summaryCards');
                summaryCards.innerHTML = `
                    <div class="summary-card total">
                        <div class="number">${data.total_services}</div>
                        <div class="label">Total Services</div>
                    </div>
                    <div class="summary-card healthy">
                        <div class="number">${data.healthy_services}</div>
                        <div class="label">Healthy</div>
                    </div>
                    <div class="summary-card degraded">
                        <div class="number">${data.degraded_services}</div>
                        <div class="label">Degraded</div>
                    </div>
                    <div class="summary-card failed">
                        <div class="number">${data.failed_services}</div>
                        <div class="label">Failed</div>
                    </div>
                `;
            }
            
            updateServicesGrid(data) {
                const servicesGrid = document.getElementById('servicesGrid');
                servicesGrid.innerHTML = data.services.map(service => {
                    const responseTimeClass = this.getResponseTimeClass(service.response_time_ms);
                    const responseTimeText = service.response_time_ms ? 
                        `${service.response_time_ms.toFixed(1)}ms` : 'N/A';
                    
                    const statusCode = service.status_code ? 
                        `HTTP ${service.status_code}` : 'N/A';
                    
                    const errorMessage = service.error_message ? 
                        `<div class="error-message">${service.error_message}</div>` : '';
                    
                    return `
                        <div class="service-card ${service.status}" data-service="${service.name}">
                            <div class="service-header">
                                <div class="service-name">${service.name}</div>
                                <div class="status-badge ${service.status}">${service.status}</div>
                            </div>
                            <div class="service-details">
                                <div class="detail-item">
                                    <span class="detail-label">Response Time:</span>
                                    <span class="response-time ${responseTimeClass}">${responseTimeText}</span>
                                </div>
                                <div class="detail-item">
                                    <span class="detail-label">Status Code:</span>
                                    <span>${statusCode}</span>
                                </div>
                                <div class="detail-item" style="grid-column: 1 / -1;">
                                    <span class="detail-label">URL:</span>
                                    <span style="word-break: break-all;">${service.url}</span>
                                </div>
                            </div>
                            ${errorMessage}
                        </div>
                    `;
                }).join('');
                
                // Add animation for status changes
                if (this.previousData) {
                    data.services.forEach(service => {
                        const prevService = this.previousData.services.find(s => s.name === service.name);
                        if (prevService && prevService.status !== service.status) {
                            const card = document.querySelector(`[data-service="${service.name}"]`);
                            if (card) {
                                card.classList.add('status-changed');
                                setTimeout(() => card.classList.remove('status-changed'), 500);
                            }
                        }
                    });
                }
            }
            
            getResponseTimeClass(responseTime) {
                if (!responseTime) return '';
                if (responseTime < 1000) return 'fast';
                if (responseTime < 5000) return 'medium';
                return 'slow';
            }
            
            updateLastUpdate(timestamp) {
                const lastUpdate = document.getElementById('lastUpdate');
                const date = new Date(timestamp);
                lastUpdate.textContent = `Last updated: ${date.toLocaleString()}`;
            }
        }
        
        // Initialize dashboard when page loads
        document.addEventListener('DOMContentLoaded', () => {
            new HealthDashboard();
        });
    </script>
</body>
</html>
        '''

    async def start_server(self, health_interval: int = 30):
        """Start the monitoring dashboard server"""
        # Start health monitoring task
        self.monitoring_task = asyncio.create_task(
            self.health_monitoring_loop(health_interval)
        )
        
        logger.info(f"Starting monitoring dashboard on port {self.port}")
        logger.info(f"Dashboard URL: http://localhost:{self.port}")
        
        runner = web.AppRunner(self.app)
        await runner.setup()
        site = web.TCPSite(runner, 'localhost', self.port)
        await site.start()
        
        return runner

async def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(
        description="PyAirtable Service Health Dashboard",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Start dashboard on default port 9999
  python monitor-dashboard.py
  
  # Start dashboard on custom port with custom health check interval
  python monitor-dashboard.py --port 8080 --interval 60
        """
    )
    
    parser.add_argument(
        '--port', 
        type=int, 
        default=9999,
        help='Dashboard server port (default: 9999)'
    )
    
    parser.add_argument(
        '--interval', 
        type=int, 
        default=30,
        help='Health check interval in seconds (default: 30)'
    )
    
    args = parser.parse_args()
    
    dashboard = MonitoringDashboard(args.port)
    
    try:
        runner = await dashboard.start_server(args.interval)
        
        print(f"🚀 PyAirtable Health Dashboard started!")
        print(f"📊 Dashboard: http://localhost:{args.port}")
        print(f"🔍 Health API: http://localhost:{args.port}/health")
        print(f"⏱️  Health check interval: {args.interval} seconds")
        print(f"Press Ctrl+C to stop...")
        
        # Keep the server running
        while True:
            await asyncio.sleep(1)
            
    except KeyboardInterrupt:
        logger.info("Dashboard stopped by user")
        if dashboard.monitoring_task:
            dashboard.monitoring_task.cancel()
        await runner.cleanup()
    except Exception as e:
        logger.error(f"Fatal error: {e}")
        if dashboard.monitoring_task:
            dashboard.monitoring_task.cancel()
        if 'runner' in locals():
            await runner.cleanup()
        sys.exit(1)

if __name__ == "__main__":
    asyncio.run(main())