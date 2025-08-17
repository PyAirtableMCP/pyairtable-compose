#!/usr/bin/env python3
"""
Simple service health monitor that exposes Prometheus metrics
"""
import time
import requests
import threading
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse
import json

# Services to monitor
SERVICES = {
    'api-gateway': 'http://pyairtable-compose-api-gateway-1:8000/api/health',
    'ai-processing-service': 'http://pyairtable-compose-ai-processing-service-1:8001/health',
    'airtable-gateway': 'http://pyairtable-compose-airtable-gateway-1:8002/health',
    'platform-services': 'http://pyairtable-compose-platform-services-1:8007/health',
    'automation-services': 'http://pyairtable-compose-automation-services-1:8006/health',
    'saga-orchestrator': 'http://pyairtable-compose-saga-orchestrator-1:8008/health/',
}

# Global metrics storage
service_status = {}
last_check = {}

def check_service_health():
    """Check health of all services"""
    while True:
        for service_name, url in SERVICES.items():
            try:
                response = requests.get(url, timeout=5)
                if response.status_code == 200:
                    service_status[service_name] = 1
                    print(f"✓ {service_name}: OK")
                else:
                    service_status[service_name] = 0
                    print(f"✗ {service_name}: HTTP {response.status_code}")
            except Exception as e:
                service_status[service_name] = 0
                print(f"✗ {service_name}: {str(e)}")
            
            last_check[service_name] = time.time()
        
        time.sleep(30)  # Check every 30 seconds

class MetricsHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/metrics':
            self.send_response(200)
            self.send_header('Content-type', 'text/plain')
            self.end_headers()
            
            # Generate Prometheus metrics
            metrics = []
            
            # Service health metrics
            for service_name, status in service_status.items():
                metrics.append(f'service_health{{service="{service_name}"}} {status}')
            
            # Auth status (special monitoring for platform-services)
            auth_status = service_status.get('platform-services', 0)
            metrics.append(f'auth_service_status {auth_status}')
            
            # Service count
            healthy_count = sum(1 for status in service_status.values() if status == 1)
            total_count = len(service_status)
            metrics.append(f'services_healthy_count {healthy_count}')
            metrics.append(f'services_total_count {total_count}')
            
            # Timestamp
            metrics.append(f'monitoring_last_update {int(time.time())}')
            
            self.wfile.write('\n'.join(metrics).encode())
        elif self.path == '/health':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            
            health_data = {
                'status': 'healthy',
                'services': service_status,
                'timestamp': time.time()
            }
            self.wfile.write(json.dumps(health_data).encode())
        else:
            self.send_error(404)

if __name__ == '__main__':
    # Start health checking in background
    health_thread = threading.Thread(target=check_service_health, daemon=True)
    health_thread.start()
    
    # Start metrics server
    server = HTTPServer(('0.0.0.0', 8080), MetricsHandler)
    print("Starting simple monitor on port 8080...")
    print("Metrics: http://localhost:8080/metrics")
    print("Health: http://localhost:8080/health")
    server.serve_forever()