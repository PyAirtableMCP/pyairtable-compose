#!/usr/bin/env python3
"""
Emergency Stabilization Day 5: Alert Manager
Basic alerting system for PyAirtable service failures and performance issues.
"""

import asyncio
import json
import time
import logging
import sys
import os
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Set
from dataclasses import dataclass, asdict
import argparse
from pathlib import Path

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler('/tmp/alert-manager.log')
    ]
)
logger = logging.getLogger(__name__)

@dataclass
class Alert:
    id: str
    service_name: str
    alert_type: str  # SERVICE_DOWN, DEGRADED_PERFORMANCE, RECOVERY
    severity: str    # CRITICAL, WARNING, INFO
    message: str
    timestamp: str
    details: Dict
    resolved: bool = False
    resolved_at: Optional[str] = None

@dataclass
class AlertRule:
    name: str
    service_pattern: str  # Service name pattern to match
    condition: str        # DOWN, DEGRADED, RESPONSE_TIME
    threshold: Optional[float]  # For response time alerts
    duration: int         # How long condition must persist (seconds)
    severity: str         # CRITICAL, WARNING, INFO
    cooldown: int         # Minimum time between alerts (seconds)

class AlertManager:
    def __init__(self, config_file: Optional[str] = None):
        self.config_file = config_file or '/tmp/alert-config.json'
        self.state_file = '/tmp/alert-state.json'
        self.alerts_file = '/tmp/alerts.json'
        
        # Active alerts (keyed by service_name + alert_type)
        self.active_alerts: Dict[str, Alert] = {}
        
        # Alert history
        self.alert_history: List[Alert] = []
        
        # Service states to track condition duration
        self.service_states: Dict[str, Dict] = {}
        
        # Default alert rules
        self.alert_rules = self.load_default_rules()
        
        # Load existing state
        self.load_state()

    def load_default_rules(self) -> List[AlertRule]:
        """Load default alerting rules"""
        return [
            # Critical service down alerts
            AlertRule(
                name="Critical Service Down",
                service_pattern="*",
                condition="DOWN",
                threshold=None,
                duration=30,  # 30 seconds
                severity="CRITICAL",
                cooldown=300  # 5 minutes
            ),
            
            # Degraded performance alerts
            AlertRule(
                name="Service Degraded Performance",
                service_pattern="*",
                condition="DEGRADED",
                threshold=None,
                duration=60,  # 1 minute
                severity="WARNING",
                cooldown=600  # 10 minutes
            ),
            
            # High response time alerts
            AlertRule(
                name="High Response Time",
                service_pattern="*",
                condition="RESPONSE_TIME",
                threshold=5000.0,  # 5 seconds
                duration=120,  # 2 minutes
                severity="WARNING",
                cooldown=900  # 15 minutes
            ),
            
            # Frontend specific alerts (less critical)
            AlertRule(
                name="Frontend Service Down",
                service_pattern="frontend*",
                condition="DOWN",
                threshold=None,
                duration=120,  # 2 minutes (longer tolerance)
                severity="WARNING",
                cooldown=600  # 10 minutes
            ),
        ]

    def load_state(self):
        """Load alert manager state from disk"""
        try:
            if os.path.exists(self.state_file):
                with open(self.state_file, 'r') as f:
                    state = json.load(f)
                    
                    # Load active alerts
                    self.active_alerts = {
                        key: Alert(**alert_data) 
                        for key, alert_data in state.get('active_alerts', {}).items()
                    }
                    
                    # Load service states
                    self.service_states = state.get('service_states', {})
                    
                logger.info(f"Loaded state: {len(self.active_alerts)} active alerts")
            
            # Load alert history
            if os.path.exists(self.alerts_file):
                with open(self.alerts_file, 'r') as f:
                    history_data = json.load(f)
                    self.alert_history = [Alert(**alert) for alert in history_data]
                logger.info(f"Loaded {len(self.alert_history)} historical alerts")
                
        except Exception as e:
            logger.error(f"Error loading state: {e}")

    def save_state(self):
        """Save alert manager state to disk"""
        try:
            state = {
                'active_alerts': {
                    key: asdict(alert) 
                    for key, alert in self.active_alerts.items()
                },
                'service_states': self.service_states,
                'last_save': datetime.now().isoformat()
            }
            
            with open(self.state_file, 'w') as f:
                json.dump(state, f, indent=2, default=str)
            
            # Save alert history (keep last 1000 alerts)
            with open(self.alerts_file, 'w') as f:
                history_to_save = self.alert_history[-1000:]
                json.dump([asdict(alert) for alert in history_to_save], f, indent=2, default=str)
                
        except Exception as e:
            logger.error(f"Error saving state: {e}")

    def generate_alert_id(self, service_name: str, alert_type: str) -> str:
        """Generate unique alert ID"""
        timestamp = int(time.time())
        return f"{service_name}_{alert_type}_{timestamp}"

    def get_alert_key(self, service_name: str, alert_type: str) -> str:
        """Get key for tracking active alerts"""
        return f"{service_name}_{alert_type}"

    def matches_pattern(self, service_name: str, pattern: str) -> bool:
        """Check if service name matches pattern"""
        if pattern == "*":
            return True
        if pattern.endswith("*"):
            return service_name.startswith(pattern[:-1])
        if pattern.startswith("*"):
            return service_name.endswith(pattern[1:])
        return service_name == pattern

    def should_alert(self, service_name: str, rule: AlertRule, current_time: datetime) -> bool:
        """Check if we should send an alert based on cooldown"""
        alert_key = self.get_alert_key(service_name, rule.condition)
        
        # Check if there's an active alert
        if alert_key in self.active_alerts:
            last_alert_time = datetime.fromisoformat(self.active_alerts[alert_key].timestamp)
            time_since_last = (current_time - last_alert_time).total_seconds()
            return time_since_last >= rule.cooldown
        
        return True

    def evaluate_rules(self, health_data: Dict):
        """Evaluate all alert rules against current health data"""
        current_time = datetime.now()
        
        for service in health_data.get('services', []):
            service_name = service['name']
            service_status = service['status']
            response_time = service.get('response_time_ms')
            
            # Update service state tracking
            if service_name not in self.service_states:
                self.service_states[service_name] = {
                    'status': service_status,
                    'status_since': current_time.isoformat(),
                    'response_time': response_time
                }
            else:
                prev_state = self.service_states[service_name]
                
                # If status changed, reset the timer
                if prev_state['status'] != service_status:
                    self.service_states[service_name] = {
                        'status': service_status,
                        'status_since': current_time.isoformat(),
                        'response_time': response_time
                    }
                else:
                    # Update response time but keep status_since
                    self.service_states[service_name]['response_time'] = response_time
            
            # Evaluate rules for this service
            for rule in self.alert_rules:
                if not self.matches_pattern(service_name, rule.service_pattern):
                    continue
                
                should_trigger = False
                alert_details = {}
                
                # Check rule conditions
                if rule.condition == "DOWN" and service_status == "DOWN":
                    should_trigger = True
                    alert_details = {
                        'status': service_status,
                        'error_message': service.get('error_message', 'Service is down'),
                        'response_time_ms': response_time
                    }
                
                elif rule.condition == "DEGRADED" and service_status == "DEGRADED":
                    should_trigger = True
                    alert_details = {
                        'status': service_status,
                        'response_time_ms': response_time,
                        'threshold': '1-5 seconds'
                    }
                
                elif rule.condition == "RESPONSE_TIME" and response_time and response_time > rule.threshold:
                    should_trigger = True
                    alert_details = {
                        'response_time_ms': response_time,
                        'threshold_ms': rule.threshold,
                        'status': service_status
                    }
                
                # Check duration requirement
                if should_trigger:
                    status_since = datetime.fromisoformat(self.service_states[service_name]['status_since'])
                    duration_seconds = (current_time - status_since).total_seconds()
                    
                    if duration_seconds >= rule.duration:
                        # Check cooldown
                        if self.should_alert(service_name, rule, current_time):
                            self.trigger_alert(service_name, rule, alert_details, current_time)
                
                # Check for recovery
                elif rule.condition in ["DOWN", "DEGRADED"]:
                    self.check_recovery(service_name, rule.condition, service_status, current_time)

    def trigger_alert(self, service_name: str, rule: AlertRule, details: Dict, current_time: datetime):
        """Trigger a new alert"""
        alert_id = self.generate_alert_id(service_name, rule.condition)
        alert_key = self.get_alert_key(service_name, rule.condition)
        
        alert = Alert(
            id=alert_id,
            service_name=service_name,
            alert_type=rule.condition,
            severity=rule.severity,
            message=self.format_alert_message(service_name, rule, details),
            timestamp=current_time.isoformat(),
            details=details
        )
        
        # Add to active alerts and history
        self.active_alerts[alert_key] = alert
        self.alert_history.append(alert)
        
        # Log and notify
        self.log_alert(alert)
        self.send_alert_notification(alert)

    def check_recovery(self, service_name: str, condition: str, current_status: str, current_time: datetime):
        """Check if a service has recovered and resolve alerts"""
        alert_key = self.get_alert_key(service_name, condition)
        
        if alert_key in self.active_alerts and not self.active_alerts[alert_key].resolved:
            # Service recovered
            if ((condition == "DOWN" and current_status in ["UP", "DEGRADED"]) or
                (condition == "DEGRADED" and current_status == "UP")):
                
                # Create recovery alert
                recovery_alert = Alert(
                    id=self.generate_alert_id(service_name, "RECOVERY"),
                    service_name=service_name,
                    alert_type="RECOVERY",
                    severity="INFO",
                    message=f"🟢 Service {service_name} has recovered (status: {current_status})",
                    timestamp=current_time.isoformat(),
                    details={
                        'previous_condition': condition,
                        'current_status': current_status,
                        'recovered_from': self.active_alerts[alert_key].id
                    }
                )
                
                # Mark original alert as resolved
                self.active_alerts[alert_key].resolved = True
                self.active_alerts[alert_key].resolved_at = current_time.isoformat()
                
                # Add recovery to history
                self.alert_history.append(recovery_alert)
                
                # Log and notify
                self.log_alert(recovery_alert)
                self.send_alert_notification(recovery_alert)
                
                # Clean up resolved alert from active alerts
                del self.active_alerts[alert_key]

    def format_alert_message(self, service_name: str, rule: AlertRule, details: Dict) -> str:
        """Format alert message"""
        if rule.condition == "DOWN":
            return f"🔴 ALERT: Service {service_name} is DOWN - {details.get('error_message', 'No response')}"
        
        elif rule.condition == "DEGRADED":
            response_time = details.get('response_time_ms', 0)
            return f"🟡 ALERT: Service {service_name} performance degraded - Response time: {response_time:.1f}ms"
        
        elif rule.condition == "RESPONSE_TIME":
            response_time = details.get('response_time_ms', 0)
            threshold = details.get('threshold_ms', 0)
            return f"⚠️ ALERT: Service {service_name} slow response - {response_time:.1f}ms (threshold: {threshold}ms)"
        
        return f"ALERT: {service_name} - {rule.condition}"

    def log_alert(self, alert: Alert):
        """Log alert to console and file"""
        severity_emoji = {
            'CRITICAL': '🚨',
            'WARNING': '⚠️', 
            'INFO': 'ℹ️'
        }
        
        emoji = severity_emoji.get(alert.severity, '🔔')
        logger.warning(f"{emoji} [{alert.severity}] {alert.message}")
        
        # Also write to dedicated alert log
        alert_log_file = '/tmp/alerts.log'
        try:
            with open(alert_log_file, 'a') as f:
                f.write(f"{alert.timestamp} [{alert.severity}] {alert.service_name}: {alert.message}\n")
        except Exception as e:
            logger.error(f"Failed to write to alert log: {e}")

    def send_alert_notification(self, alert: Alert):
        """Send alert notification (placeholder for future integrations)"""
        # For now, just log. In the future, this could send to:
        # - Slack
        # - Email
        # - PagerDuty
        # - Discord
        # - SMS
        
        logger.info(f"Alert notification would be sent: {alert.id}")
        
        # You could add webhook calls here, e.g.:
        # await self.send_slack_notification(alert)
        # await self.send_email_notification(alert)

    async def monitor_health_file(self, health_file: str = '/tmp/health-status.json', interval: int = 10):
        """Monitor health status file for changes and evaluate alerts"""
        logger.info(f"Starting alert monitoring (checking {health_file} every {interval}s)")
        
        last_modified = 0
        
        while True:
            try:
                if os.path.exists(health_file):
                    # Check if file was modified
                    current_modified = os.path.getmtime(health_file)
                    
                    if current_modified > last_modified:
                        last_modified = current_modified
                        
                        # Read and process health data
                        with open(health_file, 'r') as f:
                            health_data = json.load(f)
                        
                        # Evaluate alert rules
                        self.evaluate_rules(health_data)
                        
                        # Save state
                        self.save_state()
                else:
                    logger.warning(f"Health file {health_file} not found")
                
                await asyncio.sleep(interval)
                
            except KeyboardInterrupt:
                logger.info("Alert monitoring stopped by user")
                break
            except Exception as e:
                logger.error(f"Error in alert monitoring: {e}")
                await asyncio.sleep(5)

    def get_alert_summary(self) -> Dict:
        """Get current alert summary"""
        active_by_severity = {}
        for alert in self.active_alerts.values():
            severity = alert.severity
            if severity not in active_by_severity:
                active_by_severity[severity] = 0
            active_by_severity[severity] += 1
        
        recent_alerts = [
            alert for alert in self.alert_history
            if datetime.fromisoformat(alert.timestamp) > datetime.now() - timedelta(hours=24)
        ]
        
        return {
            'active_alerts': len(self.active_alerts),
            'active_by_severity': active_by_severity,
            'recent_alerts_24h': len(recent_alerts),
            'total_alert_history': len(self.alert_history)
        }

    def print_status(self):
        """Print current alert status"""
        summary = self.get_alert_summary()
        
        print(f"\n{'='*60}")
        print(f"PyAirtable Alert Manager Status")
        print(f"{'='*60}")
        print(f"Active Alerts: {summary['active_alerts']}")
        
        if summary['active_by_severity']:
            for severity, count in summary['active_by_severity'].items():
                print(f"  {severity}: {count}")
        
        print(f"Recent Alerts (24h): {summary['recent_alerts_24h']}")
        print(f"Total Alert History: {summary['total_alert_history']}")
        
        if self.active_alerts:
            print(f"\n🚨 ACTIVE ALERTS:")
            for alert in self.active_alerts.values():
                age = datetime.now() - datetime.fromisoformat(alert.timestamp)
                age_str = f"{int(age.total_seconds() / 60)}m ago"
                print(f"  [{alert.severity}] {alert.service_name}: {alert.message} ({age_str})")
        
        print(f"{'='*60}\n")

def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(
        description="PyAirtable Alert Manager",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Start alert monitoring
  python alert-manager.py --monitor
  
  # Check current alert status
  python alert-manager.py --status
  
  # Monitor with custom health file and interval
  python alert-manager.py --monitor --health-file /custom/health.json --interval 30
        """
    )
    
    parser.add_argument(
        '--monitor',
        action='store_true',
        help='Start continuous alert monitoring'
    )
    
    parser.add_argument(
        '--status',
        action='store_true', 
        help='Show current alert status and exit'
    )
    
    parser.add_argument(
        '--health-file',
        default='/tmp/health-status.json',
        help='Health status file to monitor (default: /tmp/health-status.json)'
    )
    
    parser.add_argument(
        '--interval',
        type=int,
        default=10,
        help='Monitoring interval in seconds (default: 10)'
    )
    
    args = parser.parse_args()
    
    # Default to status if no mode specified
    if not args.monitor and not args.status:
        args.status = True
    
    alert_manager = AlertManager()
    
    try:
        if args.status:
            alert_manager.print_status()
        
        if args.monitor:
            asyncio.run(alert_manager.monitor_health_file(args.health_file, args.interval))
            
    except KeyboardInterrupt:
        logger.info("Alert manager stopped by user")
        alert_manager.save_state()
        sys.exit(0)
    except Exception as e:
        logger.error(f"Fatal error: {e}")
        alert_manager.save_state()
        sys.exit(1)

if __name__ == "__main__":
    main()