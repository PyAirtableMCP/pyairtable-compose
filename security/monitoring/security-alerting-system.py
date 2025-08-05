#!/usr/bin/env python3
"""
PyAirtable Security Alerting and Automated Response System
Real-time security incident response with automated workflows and rate limiting
"""

import asyncio
import json
import time
import uuid
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any, Set, Callable
from dataclasses import dataclass, asdict
from enum import Enum
import logging
import hashlib
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from collections import defaultdict, deque
import asyncpg
import redis.asyncio as redis
from prometheus_client import Counter, Histogram, Gauge
import structlog
import aiohttp
import ipaddress
from jinja2 import Template

logger = structlog.get_logger(__name__)

class AlertSeverity(Enum):
    """Alert severity levels"""
    INFO = "info"
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"
    CRITICAL = "critical"

class AlertStatus(Enum):
    """Alert status states"""
    OPEN = "open"
    ACKNOWLEDGED = "acknowledged"
    INVESTIGATING = "investigating"  
    RESOLVED = "resolved"
    SUPPRESSED = "suppressed"

class ResponseAction(Enum):
    """Automated response actions"""
    BLOCK_IP = "block_ip"
    RATE_LIMIT = "rate_limit"
    DISABLE_USER = "disable_user"
    REVOKE_TOKEN = "revoke_token"
    QUARANTINE_CONTAINER = "quarantine_container"
    SCALE_SERVICE = "scale_service"
    NOTIFY_ADMIN = "notify_admin"
    CREATE_INCIDENT = "create_incident"
    RUN_PLAYBOOK = "run_playbook"

@dataclass
class SecurityAlert:
    """Security alert data structure"""
    alert_id: str
    timestamp: datetime
    severity: AlertSeverity
    title: str
    description: str
    source_event_id: str
    source_system: str
    affected_resources: List[str]
    threat_indicators: List[str]
    recommended_actions: List[str]
    status: AlertStatus
    assigned_to: Optional[str]
    tags: List[str]
    metadata: Dict[str, Any]
    escalation_level: int
    suppression_key: Optional[str]
    
    def to_dict(self) -> Dict[str, Any]:
        data = asdict(self)
        data['timestamp'] = self.timestamp.isoformat()
        data['severity'] = self.severity.value
        data['status'] = self.status.value
        return data

@dataclass
class AlertRule:
    """Alert rule configuration"""
    rule_id: str
    name: str
    description: str
    condition: str
    severity: AlertSeverity
    enabled: bool
    threshold: Dict[str, Any]
    time_window: int  # seconds
    escalation_rules: List[Dict[str, Any]]
    response_actions: List[ResponseAction]
    suppression_duration: int  # seconds
    tags: List[str]

@dataclass
class IncidentResponse:
    """Incident response tracking"""
    incident_id: str
    alert_ids: List[str]
    title: str
    description: str
    severity: AlertSeverity
    status: str
    assigned_team: str
    created_at: datetime
    updated_at: datetime
    response_actions: List[Dict[str, Any]]
    timeline: List[Dict[str, Any]]
    resolution_summary: Optional[str]

class SecurityAlertingSystem:
    """Security alerting and automated response system"""
    
    def __init__(self, config: Dict[str, Any]):
        self.config = config
        self.redis_client = None
        self.db_pool = None
        self.session = None
        
        # Alert state tracking
        self.active_alerts: Dict[str, SecurityAlert] = {}
        self.alert_rules: Dict[str, AlertRule] = {}
        self.suppressed_alerts: Dict[str, datetime] = {}
        self.rate_limiters: Dict[str, deque] = defaultdict(lambda: deque(maxlen=100))
        self.blocked_ips: Set[str] = set()
        self.disabled_users: Set[str] = set()
        
        # Response handlers
        self.response_handlers: Dict[ResponseAction, Callable] = {
            ResponseAction.BLOCK_IP: self.block_ip_address,
            ResponseAction.RATE_LIMIT: self.apply_rate_limit,
            ResponseAction.DISABLE_USER: self.disable_user_account,
            ResponseAction.REVOKE_TOKEN: self.revoke_user_tokens,
            ResponseAction.QUARANTINE_CONTAINER: self.quarantine_container,
            ResponseAction.SCALE_SERVICE: self.scale_service_resources,
            ResponseAction.NOTIFY_ADMIN: self.notify_administrators,
            ResponseAction.CREATE_INCIDENT: self.create_security_incident,
            ResponseAction.RUN_PLAYBOOK: self.execute_response_playbook
        }
        
        # Prometheus metrics
        self.alerts_total = Counter(
            'security_alerts_total',
            'Total security alerts generated',
            ['severity', 'source_system', 'status']
        )
        
        self.response_actions_total = Counter(
            'security_response_actions_total',
            'Total automated response actions',
            ['action_type', 'success']
        )
        
        self.alert_processing_time = Histogram(
            'security_alert_processing_seconds',
            'Time to process security alerts',
            ['severity']
        )
        
        self.active_incidents_gauge = Gauge(
            'security_active_incidents',
            'Number of active security incidents',
            ['severity']
        )
        
        self.blocked_ips_gauge = Gauge(
            'security_blocked_ips_total',
            'Total number of blocked IP addresses'
        )
        
        # Alert templates
        self.email_template = Template("""
        <html>
        <head><title>Security Alert: {{ alert.title }}</title></head>
        <body>
        <h2 style="color: {% if alert.severity.value == 'critical' %}red{% elif alert.severity.value == 'high' %}orange{% else %}blue{% endif %};">
            🚨 Security Alert: {{ alert.title }}
        </h2>
        
        <table border="1" style="border-collapse: collapse; width: 100%;">
        <tr><td><strong>Alert ID</strong></td><td>{{ alert.alert_id }}</td></tr>
        <tr><td><strong>Severity</strong></td><td>{{ alert.severity.value.upper() }}</td></tr>
        <tr><td><strong>Timestamp</strong></td><td>{{ alert.timestamp.strftime('%Y-%m-%d %H:%M:%S UTC') }}</td></tr>
        <tr><td><strong>Source System</strong></td><td>{{ alert.source_system }}</td></tr>
        <tr><td><strong>Affected Resources</strong></td><td>{{ ', '.join(alert.affected_resources) }}</td></tr>
        </table>
        
        <h3>Description</h3>
        <p>{{ alert.description }}</p>
        
        <h3>Threat Indicators</h3>
        <ul>
        {% for indicator in alert.threat_indicators %}
        <li>{{ indicator }}</li>
        {% endfor %}
        </ul>
        
        <h3>Recommended Actions</h3>
        <ol>
        {% for action in alert.recommended_actions %}
        <li>{{ action }}</li>
        {% endfor %}
        </ol>
        
        <p><em>This is an automated security alert from PyAirtable Security Monitoring System.</em></p>
        </body>
        </html>
        """)
        
    async def initialize(self):
        """Initialize alerting system"""
        try:
            # Initialize database connection
            self.db_pool = await asyncpg.create_pool(
                host=self.config['database']['host'],
                port=self.config['database']['port'],
                user=self.config['database']['user'],
                password=self.config['database']['password'],
                database=self.config['database']['name'],
                min_size=3,
                max_size=10
            )
            
            # Initialize Redis connection
            self.redis_client = redis.Redis(
                host=self.config['redis']['host'],
                port=self.config['redis']['port'],
                decode_responses=True
            )
            
            # Initialize HTTP session
            self.session = aiohttp.ClientSession()
            
            # Create database schema
            await self.create_alerting_tables()
            
            # Load alert rules
            await self.load_alert_rules()
            
            # Load blocked IPs and disabled users
            await self.load_security_state()
            
            logger.info("Security alerting system initialized successfully")
            
        except Exception as e:
            logger.error("Failed to initialize alerting system", error=str(e))
            raise
    
    async def create_alerting_tables(self):
        """Create alerting system database tables"""
        async with self.db_pool.acquire() as conn:
            await conn.execute("""
                CREATE TABLE IF NOT EXISTS security_alerts (
                    alert_id UUID PRIMARY KEY,
                    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                    severity VARCHAR(20) NOT NULL,
                    title VARCHAR(255) NOT NULL,
                    description TEXT NOT NULL,
                    source_event_id UUID,
                    source_system VARCHAR(100) NOT NULL,
                    affected_resources TEXT[],
                    threat_indicators TEXT[],
                    recommended_actions TEXT[],
                    status VARCHAR(50) DEFAULT 'open',
                    assigned_to VARCHAR(100),
                    tags TEXT[],
                    metadata JSONB,
                    escalation_level INTEGER DEFAULT 0,
                    suppression_key VARCHAR(255),
                    created_at TIMESTAMPTZ DEFAULT NOW(),
                    updated_at TIMESTAMPTZ DEFAULT NOW(),
                    resolved_at TIMESTAMPTZ,
                    INDEX (timestamp),
                    INDEX (severity),
                    INDEX (status),
                    INDEX (source_system),
                    INDEX (suppression_key)
                );
                
                CREATE TABLE IF NOT EXISTS alert_rules (
                    rule_id VARCHAR(255) PRIMARY KEY,
                    name VARCHAR(255) NOT NULL,
                    description TEXT,
                    condition TEXT NOT NULL,
                    severity VARCHAR(20) NOT NULL,
                    enabled BOOLEAN DEFAULT TRUE,
                    threshold JSONB,
                    time_window INTEGER,
                    escalation_rules JSONB,
                    response_actions TEXT[],
                    suppression_duration INTEGER DEFAULT 3600,
                    tags TEXT[],
                    created_at TIMESTAMPTZ DEFAULT NOW(),
                    updated_at TIMESTAMPTZ DEFAULT NOW()
                );
                
                CREATE TABLE IF NOT EXISTS security_incidents (
                    incident_id UUID PRIMARY KEY,
                    alert_ids UUID[],
                    title VARCHAR(255) NOT NULL,
                    description TEXT,
                    severity VARCHAR(20) NOT NULL,
                    status VARCHAR(50) DEFAULT 'open',
                    assigned_team VARCHAR(100),
                    created_at TIMESTAMPTZ DEFAULT NOW(),
                    updated_at TIMESTAMPTZ DEFAULT NOW(),
                    resolved_at TIMESTAMPTZ,
                    response_actions JSONB,
                    timeline JSONB,
                    resolution_summary TEXT,
                    INDEX (timestamp),
                    INDEX (severity),
                    INDEX (status),
                    INDEX (assigned_team)
                );
                
                CREATE TABLE IF NOT EXISTS response_actions (
                    action_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                    alert_id UUID REFERENCES security_alerts(alert_id),
                    action_type VARCHAR(50) NOT NULL,
                    parameters JSONB,
                    executed_at TIMESTAMPTZ DEFAULT NOW(),
                    success BOOLEAN,
                    result JSONB,
                    error_message TEXT,
                    INDEX (alert_id),
                    INDEX (action_type),
                    INDEX (executed_at)
                );
                
                CREATE TABLE IF NOT EXISTS blocked_ips (
                    ip_address INET PRIMARY KEY,
                    blocked_at TIMESTAMPTZ DEFAULT NOW(),
                    blocked_by VARCHAR(100),
                    reason TEXT,
                    expires_at TIMESTAMPTZ,
                    is_active BOOLEAN DEFAULT TRUE,
                    INDEX (blocked_at),
                    INDEX (expires_at),
                    INDEX (is_active)
                );
                
                CREATE TABLE IF NOT EXISTS disabled_users (
                    user_id UUID PRIMARY KEY,
                    disabled_at TIMESTAMPTZ DEFAULT NOW(),
                    disabled_by VARCHAR(100),
                    reason TEXT,
                    expires_at TIMESTAMPTZ,
                    is_active BOOLEAN DEFAULT TRUE,
                    INDEX (disabled_at),
                    INDEX (expires_at),
                    INDEX (is_active)
                );
                
                CREATE TABLE IF NOT EXISTS rate_limits (
                    rule_id VARCHAR(255) PRIMARY KEY,
                    target_type VARCHAR(50) NOT NULL,
                    target_value VARCHAR(255) NOT NULL,
                    limit_per_minute INTEGER NOT NULL,
                    created_at TIMESTAMPTZ DEFAULT NOW(),
                    expires_at TIMESTAMPTZ,
                    is_active BOOLEAN DEFAULT TRUE,
                    INDEX (target_type, target_value),
                    INDEX (expires_at),
                    INDEX (is_active)
                );
            """)
    
    async def load_alert_rules(self):
        """Load alert rules from database"""
        try:
            async with self.db_pool.acquire() as conn:
                rules = await conn.fetch("SELECT * FROM alert_rules WHERE enabled = TRUE")
                
                for rule_data in rules:
                    rule = AlertRule(
                        rule_id=rule_data['rule_id'],
                        name=rule_data['name'],
                        description=rule_data['description'],
                        condition=rule_data['condition'],
                        severity=AlertSeverity(rule_data['severity']),
                        enabled=rule_data['enabled'],
                        threshold=rule_data['threshold'] or {},
                        time_window=rule_data['time_window'] or 300,
                        escalation_rules=rule_data['escalation_rules'] or [],
                        response_actions=[ResponseAction(action) for action in rule_data['response_actions'] or []],
                        suppression_duration=rule_data['suppression_duration'] or 3600,
                        tags=rule_data['tags'] or []
                    )
                    self.alert_rules[rule.rule_id] = rule
                
                logger.info(f"Loaded {len(self.alert_rules)} alert rules")
                
        except Exception as e:
            logger.error("Error loading alert rules", error=str(e))
    
    async def load_security_state(self):
        """Load blocked IPs and disabled users"""
        try:
            async with self.db_pool.acquire() as conn:
                # Load blocked IPs
                blocked_ips = await conn.fetch("""
                    SELECT ip_address FROM blocked_ips 
                    WHERE is_active = TRUE 
                    AND (expires_at IS NULL OR expires_at > NOW())
                """)
                
                self.blocked_ips = {str(row['ip_address']) for row in blocked_ips}
                self.blocked_ips_gauge.set(len(self.blocked_ips))
                
                # Load disabled users
                disabled_users = await conn.fetch("""
                    SELECT user_id FROM disabled_users 
                    WHERE is_active = TRUE 
                    AND (expires_at IS NULL OR expires_at > NOW())
                """)
                
                self.disabled_users = {str(row['user_id']) for row in disabled_users}
                
                logger.info(f"Loaded {len(self.blocked_ips)} blocked IPs, {len(self.disabled_users)} disabled users")
                
        except Exception as e:
            logger.error("Error loading security state", error=str(e))
    
    async def process_security_event(self, event_data: Dict[str, Any]) -> Optional[SecurityAlert]:
        """Process incoming security event and generate alerts"""
        start_time = time.time()
        
        try:
            event_type = event_data.get('event_type', 'unknown')
            severity = event_data.get('severity', 'medium')
            source_system = event_data.get('source_system', 'unknown')
            
            # Check if event matches any alert rules
            matching_rules = await self.find_matching_rules(event_data)
            
            if not matching_rules:
                return None
            
            # Process each matching rule
            alerts_created = []
            for rule in matching_rules:
                alert = await self.create_alert_from_rule(rule, event_data)
                if alert:
                    alerts_created.append(alert)
            
            # Record processing time
            self.alert_processing_time.labels(
                severity=severity
            ).observe(time.time() - start_time)
            
            return alerts_created[0] if alerts_created else None
            
        except Exception as e:
            logger.error("Error processing security event", error=str(e))
            return None
    
    async def find_matching_rules(self, event_data: Dict[str, Any]) -> List[AlertRule]:
        """Find alert rules that match the event"""
        matching_rules = []
        
        for rule in self.alert_rules.values():
            if not rule.enabled:
                continue
                
            # Check if event matches rule condition
            if await self.evaluate_rule_condition(rule, event_data):
                matching_rules.append(rule)
        
        return matching_rules
    
    async def evaluate_rule_condition(self, rule: AlertRule, event_data: Dict[str, Any]) -> bool:
        """Evaluate if event matches rule condition"""
        try:
            # Simplified condition evaluation - in production, use proper expression evaluator
            condition = rule.condition.lower()
            event_type = event_data.get('event_type', '').lower()
            severity = event_data.get('severity', '').lower()
            source_system = event_data.get('source_system', '').lower()
            
            # Basic condition matching
            if 'event_type' in condition and event_type in condition:
                return True
            
            if 'severity' in condition and severity in condition:
                return True
                
            if 'source_system' in condition and source_system in condition:
                return True
            
            # Check threshold conditions
            if rule.threshold:
                return await self.check_threshold_conditions(rule, event_data)
            
            return False
            
        except Exception as e:
            logger.error("Error evaluating rule condition", error=str(e))
            return False
    
    async def check_threshold_conditions(self, rule: AlertRule, event_data: Dict[str, Any]) -> bool:
        """Check threshold-based conditions"""
        try:
            threshold = rule.threshold
            time_window = rule.time_window
            
            # Example: Check for multiple failed logins
            if threshold.get('type') == 'count':
                count_key = f"rule_count:{rule.rule_id}:{event_data.get('source_ip', 'unknown')}"
                current_time = int(time.time())
                
                # Add current event
                await self.redis_client.zadd(count_key, {current_time: current_time})
                
                # Remove old events outside time window
                await self.redis_client.zremrangebyscore(count_key, 0, current_time - time_window)
                
                # Check count against threshold
                event_count = await self.redis_client.zcard(count_key)
                await self.redis_client.expire(count_key, time_window)
                
                return event_count >= threshold.get('value', 1)
            
            # Example: Check for rate-based conditions
            elif threshold.get('type') == 'rate':
                rate_key = f"rule_rate:{rule.rule_id}"
                rate_limit = threshold.get('value', 10)  # events per minute
                
                current_minute = int(time.time() // 60)
                current_count = await self.redis_client.incr(f"{rate_key}:{current_minute}")
                await self.redis_client.expire(f"{rate_key}:{current_minute}", 60)
                
                return current_count >= rate_limit
            
            return False
            
        except Exception as e:
            logger.error("Error checking threshold conditions", error=str(e))
            return False
    
    async def create_alert_from_rule(self, rule: AlertRule, event_data: Dict[str, Any]) -> Optional[SecurityAlert]:
        """Create alert from matching rule and event"""
        try:
            # Generate suppression key for duplicate detection
            suppression_key = self.generate_suppression_key(rule, event_data)
            
            # Check if alert is suppressed
            if self.is_alert_suppressed(suppression_key):
                logger.debug("Alert suppressed", rule_id=rule.rule_id, suppression_key=suppression_key)
                return None
            
            # Create alert
            alert = SecurityAlert(
                alert_id=str(uuid.uuid4()),
                timestamp=datetime.utcnow(),
                severity=rule.severity,
                title=f"{rule.name}: {event_data.get('description', 'Security event detected')}",
                description=self.generate_alert_description(rule, event_data),
                source_event_id=event_data.get('event_id'),
                source_system=event_data.get('source_system', 'unknown'),
                affected_resources=event_data.get('affected_resources', []),
                threat_indicators=event_data.get('threat_indicators', []),
                recommended_actions=self.generate_recommended_actions(rule, event_data),
                status=AlertStatus.OPEN,
                assigned_to=None,
                tags=rule.tags + event_data.get('tags', []),
                metadata=event_data.get('metadata', {}),
                escalation_level=0,
                suppression_key=suppression_key
            )
            
            # Store alert
            await self.store_alert(alert)
            
            # Track active alert
            self.active_alerts[alert.alert_id] = alert
            
            # Update metrics
            self.alerts_total.labels(
                severity=alert.severity.value,
                source_system=alert.source_system,
                status=alert.status.value
            ).inc()
            
            # Apply suppression
            self.suppress_alert(suppression_key, rule.suppression_duration)
            
            # Execute automated response actions
            await self.execute_response_actions(alert, rule.response_actions)
            
            # Send notifications
            await self.send_alert_notifications(alert)
            
            logger.info(
                "Security alert created",
                alert_id=alert.alert_id,
                severity=alert.severity.value,
                title=alert.title
            )
            
            return alert
            
        except Exception as e:
            logger.error("Error creating alert from rule", error=str(e))
            return None
    
    def generate_suppression_key(self, rule: AlertRule, event_data: Dict[str, Any]) -> str:
        """Generate unique suppression key for duplicate detection"""
        key_parts = [
            rule.rule_id,
            event_data.get('source_system', ''),
            event_data.get('source_ip', ''),
            event_data.get('user_id', ''),
            event_data.get('event_type', '')
        ]
        
        key_string = '|'.join(str(part) for part in key_parts if part)
        return hashlib.sha256(key_string.encode()).hexdigest()[:16]
    
    def is_alert_suppressed(self, suppression_key: str) -> bool:
        """Check if alert is currently suppressed"""
        if suppression_key in self.suppressed_alerts:
            suppression_expiry = self.suppressed_alerts[suppression_key]
            if datetime.utcnow() < suppression_expiry:
                return True
            else:
                # Clean up expired suppression
                del self.suppressed_alerts[suppression_key]
        
        return False
    
    def suppress_alert(self, suppression_key: str, duration: int):
        """Suppress alerts with the same key for specified duration"""
        expiry_time = datetime.utcnow() + timedelta(seconds=duration)
        self.suppressed_alerts[suppression_key] = expiry_time
    
    def generate_alert_description(self, rule: AlertRule, event_data: Dict[str, Any]) -> str:
        """Generate detailed alert description"""
        description_parts = [
            f"Rule: {rule.name}",
            f"Description: {rule.description}",
            f"Event: {event_data.get('description', 'Security event detected')}"
        ]
        
        if event_data.get('source_ip'):
            description_parts.append(f"Source IP: {event_data['source_ip']}")
        
        if event_data.get('user_id'):
            description_parts.append(f"User: {event_data['user_id']}")
        
        return '\n'.join(description_parts)
    
    def generate_recommended_actions(self, rule: AlertRule, event_data: Dict[str, Any]) -> List[str]:
        """Generate recommended response actions"""
        actions = [
            "Investigate the security event immediately",
            "Review logs for additional context",
            "Verify the legitimacy of the activity"
        ]
        
        # Add rule-specific actions
        if rule.response_actions:
            action_descriptions = {
                ResponseAction.BLOCK_IP: "Consider blocking the source IP address",
                ResponseAction.DISABLE_USER: "Consider disabling the affected user account",
                ResponseAction.RATE_LIMIT: "Apply rate limiting to prevent further abuse",
                ResponseAction.REVOKE_TOKEN: "Revoke authentication tokens for the user"
            }
            
            for response_action in rule.response_actions:
                if response_action in action_descriptions:
                    actions.append(action_descriptions[response_action])
        
        return actions
    
    async def execute_response_actions(self, alert: SecurityAlert, response_actions: List[ResponseAction]):
        """Execute automated response actions"""
        for action in response_actions:
            try:
                if action in self.response_handlers:
                    success = await self.response_handlers[action](alert)
                    
                    # Record response action
                    await self.record_response_action(alert.alert_id, action, success)
                    
                    # Update metrics
                    self.response_actions_total.labels(
                        action_type=action.value,
                        success=str(success).lower()
                    ).inc()
                    
                    logger.info(
                        "Response action executed",
                        alert_id=alert.alert_id,
                        action=action.value,
                        success=success
                    )
                else:
                    logger.warning("Unknown response action", action=action.value)
                    
            except Exception as e:
                logger.error("Error executing response action", action=action.value, error=str(e))
                await self.record_response_action(alert.alert_id, action, False, str(e))
    
    async def block_ip_address(self, alert: SecurityAlert) -> bool:
        """Block IP address automatically"""
        try:
            # Extract IP from alert metadata or affected resources
            ip_address = None
            
            if 'source_ip' in alert.metadata:
                ip_address = alert.metadata['source_ip']
            elif alert.affected_resources:
                # Try to find IP in affected resources
                for resource in alert.affected_resources:
                    if self.is_valid_ip(resource):
                        ip_address = resource
                        break
            
            if not ip_address:
                logger.warning("No IP address found to block", alert_id=alert.alert_id)
                return False
            
            # Add to blocked IPs
            self.blocked_ips.add(ip_address)
            
            # Store in database
            async with self.db_pool.acquire() as conn:
                await conn.execute("""
                    INSERT INTO blocked_ips (ip_address, blocked_by, reason, expires_at)
                    VALUES ($1, $2, $3, $4)
                    ON CONFLICT (ip_address) DO UPDATE SET
                        blocked_at = NOW(),
                        blocked_by = EXCLUDED.blocked_by,
                        reason = EXCLUDED.reason,
                        expires_at = EXCLUDED.expires_at,
                        is_active = TRUE
                """, 
                    ip_address, 
                    'security_system',
                    f"Automated block due to alert: {alert.title}",
                    datetime.utcnow() + timedelta(hours=24)  # Block for 24 hours
                )
            
            # Update metrics
            self.blocked_ips_gauge.set(len(self.blocked_ips))
            
            # Notify network security components
            await self.redis_client.publish('security_ip_blocks', json.dumps({
                'action': 'block',
                'ip_address': ip_address,
                'reason': alert.title,
                'expires_at': (datetime.utcnow() + timedelta(hours=24)).isoformat()
            }))
            
            return True
            
        except Exception as e:
            logger.error("Error blocking IP address", error=str(e))
            return False
    
    async def apply_rate_limit(self, alert: SecurityAlert) -> bool:
        """Apply rate limiting"""
        try:
            # Extract target for rate limiting
            target_ip = alert.metadata.get('source_ip')
            target_user = alert.metadata.get('user_id')
            
            if target_ip:
                # Apply IP-based rate limiting
                await self.set_rate_limit('ip', target_ip, 10)  # 10 requests per minute
                return True
            elif target_user:
                # Apply user-based rate limiting
                await self.set_rate_limit('user', target_user, 20)  # 20 requests per minute
                return True
            
            return False
            
        except Exception as e:
            logger.error("Error applying rate limit", error=str(e))
            return False
    
    async def set_rate_limit(self, target_type: str, target_value: str, limit: int):
        """Set rate limit for target"""
        try:
            rule_id = f"{target_type}:{target_value}"
            
            async with self.db_pool.acquire() as conn:
                await conn.execute("""
                    INSERT INTO rate_limits (rule_id, target_type, target_value, limit_per_minute, expires_at)
                    VALUES ($1, $2, $3, $4, $5)
                    ON CONFLICT (rule_id) DO UPDATE SET
                        limit_per_minute = EXCLUDED.limit_per_minute,
                        expires_at = EXCLUDED.expires_at,
                        is_active = TRUE
                """,
                    rule_id, target_type, target_value, limit,
                    datetime.utcnow() + timedelta(hours=1)  # Rate limit for 1 hour
                )
            
            # Notify API gateway about rate limit
            await self.redis_client.publish('security_rate_limits', json.dumps({
                'action': 'set_limit',
                'target_type': target_type,
                'target_value': target_value,
                'limit_per_minute': limit,
                'expires_at': (datetime.utcnow() + timedelta(hours=1)).isoformat()
            }))
            
        except Exception as e:
            logger.error("Error setting rate limit", error=str(e))
    
    async def disable_user_account(self, alert: SecurityAlert) -> bool:
        """Disable user account automatically"""
        try:
            user_id = alert.metadata.get('user_id')
            if not user_id:
                return False
            
            # Add to disabled users
            self.disabled_users.add(user_id)
            
            # Store in database
            async with self.db_pool.acquire() as conn:
                await conn.execute("""
                    INSERT INTO disabled_users (user_id, disabled_by, reason, expires_at)
                    VALUES ($1, $2, $3, $4)
                    ON CONFLICT (user_id) DO UPDATE SET
                        disabled_at = NOW(),
                        disabled_by = EXCLUDED.disabled_by,
                        reason = EXCLUDED.reason,
                        expires_at = EXCLUDED.expires_at,
                        is_active = TRUE
                """,
                    user_id,
                    'security_system',
                    f"Automated disable due to alert: {alert.title}",
                    datetime.utcnow() + timedelta(hours=2)  # Disable for 2 hours
                )
            
            # Notify user management service
            await self.redis_client.publish('security_user_actions', json.dumps({
                'action': 'disable',
                'user_id': user_id,
                'reason': alert.title,
                'expires_at': (datetime.utcnow() + timedelta(hours=2)).isoformat()
            }))
            
            return True
            
        except Exception as e:
            logger.error("Error disabling user account", error=str(e))
            return False
    
    async def revoke_user_tokens(self, alert: SecurityAlert) -> bool:
        """Revoke user authentication tokens"""
        try:
            user_id = alert.metadata.get('user_id')
            if not user_id:
                return False
            
            # Notify authentication service to revoke tokens
            await self.redis_client.publish('security_token_actions', json.dumps({
                'action': 'revoke_all',
                'user_id': user_id,
                'reason': alert.title,
                'timestamp': datetime.utcnow().isoformat()
            }))
            
            return True
            
        except Exception as e:
            logger.error("Error revoking user tokens", error=str(e))
            return False
    
    async def quarantine_container(self, alert: SecurityAlert) -> bool:
        """Quarantine suspicious container"""
        try:
            # Extract container ID from alert
            container_id = None
            for resource in alert.affected_resources:
                if resource.startswith('container:'):
                    container_id = resource.split(':', 1)[1]
                    break
            
            if not container_id:
                return False
            
            # Notify container orchestrator to quarantine
            await self.redis_client.publish('security_container_actions', json.dumps({
                'action': 'quarantine',
                'container_id': container_id,
                'reason': alert.title,
                'timestamp': datetime.utcnow().isoformat()
            }))
            
            return True
            
        except Exception as e:
            logger.error("Error quarantining container", error=str(e))
            return False
    
    async def scale_service_resources(self, alert: SecurityAlert) -> bool:
        """Scale service resources to handle attack"""
        try:
            # Extract service name from alert
            service_name = None
            for resource in alert.affected_resources:
                if resource.startswith('service:'):
                    service_name = resource.split(':', 1)[1]
                    break
            
            if not service_name:
                return False
            
            # Notify orchestrator to scale up
            await self.redis_client.publish('security_scaling_actions', json.dumps({
                'action': 'scale_up',
                'service_name': service_name,
                'reason': alert.title,
                'scale_factor': 2,  # Double the resources
                'timestamp': datetime.utcnow().isoformat()
            }))
            
            return True
            
        except Exception as e:
            logger.error("Error scaling service resources", error=str(e))
            return False
    
    async def notify_administrators(self, alert: SecurityAlert) -> bool:
        """Send notification to administrators"""
        try:
            # Send email notification
            if self.config.get('notifications', {}).get('email', {}).get('enabled'):
                await self.send_email_alert(alert)
            
            # Send Slack notification
            if self.config.get('notifications', {}).get('slack', {}).get('enabled'):
                await self.send_slack_alert(alert)
            
            # Send PagerDuty alert for critical issues
            if alert.severity == AlertSeverity.CRITICAL and self.config.get('notifications', {}).get('pagerduty', {}).get('enabled'):
                await self.send_pagerduty_alert(alert)
            
            return True
            
        except Exception as e:
            logger.error("Error notifying administrators", error=str(e))
            return False
    
    async def create_security_incident(self, alert: SecurityAlert) -> bool:
        """Create security incident for high-priority alerts"""
        try:
            if alert.severity not in [AlertSeverity.HIGH, AlertSeverity.CRITICAL]:
                return True  # Don't create incident for lower severity
            
            incident = IncidentResponse(
                incident_id=str(uuid.uuid4()),
                alert_ids=[alert.alert_id],
                title=f"Security Incident: {alert.title}",
                description=alert.description,
                severity=alert.severity,
                status='open',
                assigned_team='security',
                created_at=datetime.utcnow(),
                updated_at=datetime.utcnow(),
                response_actions=[],
                timeline=[{
                    'timestamp': datetime.utcnow().isoformat(),
                    'action': 'incident_created',
                    'details': 'Security incident created automatically'
                }],
                resolution_summary=None
            )
            
            # Store incident
            await self.store_incident(incident)
            
            # Update metrics
            self.active_incidents_gauge.labels(severity=alert.severity.value).inc()
            
            return True
            
        except Exception as e:
            logger.error("Error creating security incident", error=str(e))
            return False
    
    async def execute_response_playbook(self, alert: SecurityAlert) -> bool:
        """Execute automated response playbook"""
        try:
            # Determine playbook based on alert type
            playbook_name = self.get_playbook_for_alert(alert)
            if not playbook_name:
                return False
            
            # Execute playbook
            await self.redis_client.publish('security_playbook_execution', json.dumps({
                'playbook_name': playbook_name,
                'alert_id': alert.alert_id,
                'parameters': alert.metadata,
                'timestamp': datetime.utcnow().isoformat()
            }))
            
            return True
            
        except Exception as e:
            logger.error("Error executing response playbook", error=str(e))
            return False
    
    def get_playbook_for_alert(self, alert: SecurityAlert) -> Optional[str]:
        """Get appropriate playbook for alert type"""
        playbook_mapping = {
            'brute_force_attack': 'brute_force_response',
            'injection_attempt': 'injection_response',
            'privilege_escalation': 'privilege_escalation_response',
            'data_exfiltration': 'data_exfiltration_response'
        }
        
        for keyword, playbook in playbook_mapping.items():
            if keyword in alert.title.lower() or keyword in alert.description.lower():
                return playbook
        
        return None
    
    async def send_email_alert(self, alert: SecurityAlert):
        """Send email alert to administrators"""
        try:
            email_config = self.config.get('notifications', {}).get('email', {})
            if not email_config.get('enabled'):
                return
            
            # Create email message
            msg = MIMEMultipart('alternative')
            msg['Subject'] = f"[SECURITY ALERT] {alert.title}"
            msg['From'] = email_config.get('from_address')
            msg['To'] = ', '.join(email_config.get('to_addresses', []))
            
            # Generate HTML content
            html_content = self.email_template.render(alert=alert)
            html_part = MIMEText(html_content, 'html')
            msg.attach(html_part)
            
            # Send email
            smtp_server = smtplib.SMTP(email_config.get('smtp_host'), email_config.get('smtp_port', 587))
            smtp_server.starttls()
            if email_config.get('username'):
                smtp_server.login(email_config['username'], email_config['password'])
            
            smtp_server.send_message(msg)
            smtp_server.quit()
            
            logger.info("Email alert sent", alert_id=alert.alert_id)
            
        except Exception as e:
            logger.error("Error sending email alert", error=str(e))
    
    async def send_slack_alert(self, alert: SecurityAlert):
        """Send Slack alert notification"""
        try:
            slack_config = self.config.get('notifications', {}).get('slack', {})
            if not slack_config.get('enabled'):
                return
            
            # Create Slack message
            color_map = {
                AlertSeverity.CRITICAL: 'danger',
                AlertSeverity.HIGH: 'warning',
                AlertSeverity.MEDIUM: 'good',
                AlertSeverity.LOW: '#36a64f',
                AlertSeverity.INFO: '#36a64f'
            }
            
            message = {
                'channel': slack_config.get('channel', '#security'),
                'username': 'PyAirtable Security',
                'icon_emoji': ':warning:',
                'attachments': [{
                    'color': color_map.get(alert.severity, 'good'),
                    'title': f"Security Alert: {alert.title}",
                    'text': alert.description,
                    'fields': [
                        {'title': 'Severity', 'value': alert.severity.value.upper(), 'short': True},
                        {'title': 'Source System', 'value': alert.source_system, 'short': True},
                        {'title': 'Alert ID', 'value': alert.alert_id, 'short': True},
                        {'title': 'Timestamp', 'value': alert.timestamp.strftime('%Y-%m-%d %H:%M:%S UTC'), 'short': True}
                    ],
                    'footer': 'PyAirtable Security Monitoring',
                    'ts': int(alert.timestamp.timestamp())
                }]
            }
            
            # Send to Slack
            async with self.session.post(slack_config['webhook_url'], json=message) as response:
                if response.status == 200:
                    logger.info("Slack alert sent", alert_id=alert.alert_id)
                else:
                    logger.error("Failed to send Slack alert", status=response.status)
                    
        except Exception as e:
            logger.error("Error sending Slack alert", error=str(e))
    
    async def send_pagerduty_alert(self, alert: SecurityAlert):
        """Send PagerDuty alert for critical issues"""
        try:
            pagerduty_config = self.config.get('notifications', {}).get('pagerduty', {})
            if not pagerduty_config.get('enabled'):
                return
            
            # Create PagerDuty event
            event_data = {
                'routing_key': pagerduty_config['integration_key'],
                'event_action': 'trigger',
                'dedup_key': alert.alert_id,
                'payload': {
                    'summary': alert.title,
                    'source': alert.source_system,
                    'severity': 'critical' if alert.severity == AlertSeverity.CRITICAL else 'error',
                    'component': 'PyAirtable Security',
                    'group': 'security',
                    'class': 'security_alert',
                    'custom_details': {
                        'alert_id': alert.alert_id,
                        'description': alert.description,
                        'affected_resources': alert.affected_resources,
                        'threat_indicators': alert.threat_indicators
                    }
                }
            }
            
            # Send to PagerDuty
            async with self.session.post('https://events.pagerduty.com/v2/enqueue', json=event_data) as response:
                if response.status == 202:
                    logger.info("PagerDuty alert sent", alert_id=alert.alert_id)
                else:
                    logger.error("Failed to send PagerDuty alert", status=response.status)
                    
        except Exception as e:
            logger.error("Error sending PagerDuty alert", error=str(e))
    
    async def send_alert_notifications(self, alert: SecurityAlert):
        """Send all configured alert notifications"""
        try:
            # Always notify for high and critical alerts
            if alert.severity in [AlertSeverity.HIGH, AlertSeverity.CRITICAL]:
                await self.notify_administrators(alert)
            
            # Send webhook notifications
            webhook_config = self.config.get('notifications', {}).get('webhook')
            if webhook_config and webhook_config.get('enabled'):
                await self.send_webhook_notification(alert, webhook_config)
                
        except Exception as e:
            logger.error("Error sending alert notifications", error=str(e))
    
    async def send_webhook_notification(self, alert: SecurityAlert, webhook_config: Dict[str, Any]):
        """Send webhook notification"""
        try:
            webhook_data = {
                'alert_id': alert.alert_id,
                'timestamp': alert.timestamp.isoformat(),
                'severity': alert.severity.value,
                'title': alert.title,
                'description': alert.description,
                'source_system': alert.source_system,
                'affected_resources': alert.affected_resources,
                'threat_indicators': alert.threat_indicators,
                'recommended_actions': alert.recommended_actions,
                'metadata': alert.metadata
            }
            
            headers = {'Content-Type': 'application/json'}
            if webhook_config.get('auth_header'):
                headers['Authorization'] = webhook_config['auth_header']
            
            async with self.session.post(
                webhook_config['url'],
                json=webhook_data,
                headers=headers,
                timeout=10
            ) as response:
                if response.status == 200:
                    logger.info("Webhook notification sent", alert_id=alert.alert_id)
                else:
                    logger.error("Webhook notification failed", status=response.status)
                    
        except Exception as e:
            logger.error("Error sending webhook notification", error=str(e))
    
    def is_valid_ip(self, ip_string: str) -> bool:
        """Check if string is a valid IP address"""
        try:
            ipaddress.ip_address(ip_string)
            return True
        except ValueError:
            return False
    
    async def store_alert(self, alert: SecurityAlert):
        """Store alert in database"""
        try:
            async with self.db_pool.acquire() as conn:
                await conn.execute("""
                    INSERT INTO security_alerts 
                    (alert_id, timestamp, severity, title, description, source_event_id,
                     source_system, affected_resources, threat_indicators, recommended_actions,
                     status, assigned_to, tags, metadata, escalation_level, suppression_key)
                    VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16)
                """,
                    alert.alert_id, alert.timestamp, alert.severity.value, alert.title,
                    alert.description, alert.source_event_id, alert.source_system,
                    alert.affected_resources, alert.threat_indicators, alert.recommended_actions,
                    alert.status.value, alert.assigned_to, alert.tags, json.dumps(alert.metadata),
                    alert.escalation_level, alert.suppression_key
                )
                
        except Exception as e:
            logger.error("Error storing alert", error=str(e))
    
    async def store_incident(self, incident: IncidentResponse):
        """Store security incident in database"""
        try:
            async with self.db_pool.acquire() as conn:
                await conn.execute("""
                    INSERT INTO security_incidents 
                    (incident_id, alert_ids, title, description, severity, status,
                     assigned_team, created_at, updated_at, response_actions, timeline)
                    VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
                """,
                    incident.incident_id, incident.alert_ids, incident.title,
                    incident.description, incident.severity.value, incident.status,
                    incident.assigned_team, incident.created_at, incident.updated_at,
                    json.dumps(incident.response_actions), json.dumps(incident.timeline)
                )
                
        except Exception as e:
            logger.error("Error storing incident", error=str(e))
    
    async def record_response_action(self, alert_id: str, action: ResponseAction, 
                                   success: bool, error_message: Optional[str] = None):
        """Record executed response action"""
        try:
            async with self.db_pool.acquire() as conn:
                await conn.execute("""
                    INSERT INTO response_actions 
                    (alert_id, action_type, executed_at, success, error_message)
                    VALUES ($1, $2, $3, $4, $5)
                """, alert_id, action.value, datetime.utcnow(), success, error_message)
                
        except Exception as e:
            logger.error("Error recording response action", error=str(e))
    
    async def listen_for_events(self):
        """Listen for security events from Redis"""
        try:
            pubsub = self.redis_client.pubsub()
            await pubsub.subscribe('security_alerts', 'security_events')
            
            logger.info("Listening for security events")
            
            async for message in pubsub.listen():
                if message['type'] == 'message':
                    try:
                        event_data = json.loads(message['data'])
                        await self.process_security_event(event_data)
                    except Exception as e:
                        logger.error("Error processing event message", error=str(e))
                        
        except Exception as e:
            logger.error("Error listening for events", error=str(e))
    
    async def cleanup_old_data(self):
        """Clean up old alerts, incidents, and security state"""
        try:
            retention_days = self.config.get('retention_days', 90)
            cutoff_date = datetime.utcnow() - timedelta(days=retention_days)
            
            async with self.db_pool.acquire() as conn:
                # Clean up old alerts
                deleted_alerts = await conn.fetchval("""
                    DELETE FROM security_alerts 
                    WHERE timestamp < $1 AND status IN ('resolved', 'suppressed')
                    RETURNING COUNT(*)
                """, cutoff_date)
                
                # Clean up old incidents
                deleted_incidents = await conn.fetchval("""
                    DELETE FROM security_incidents 
                    WHERE created_at < $1 AND status = 'resolved'
                    RETURNING COUNT(*)
                """, cutoff_date)
                
                # Clean up expired blocked IPs
                await conn.execute("""
                    UPDATE blocked_ips SET is_active = FALSE 
                    WHERE expires_at < NOW() AND is_active = TRUE
                """)
                
                # Clean up expired disabled users
                await conn.execute("""
                    UPDATE disabled_users SET is_active = FALSE 
                    WHERE expires_at < NOW() AND is_active = TRUE
                """)
            
            # Reload security state
            await self.load_security_state()
            
            logger.info(f"Cleaned up {deleted_alerts} alerts, {deleted_incidents} incidents")
            
        except Exception as e:
            logger.error("Error cleaning up old data", error=str(e))
    
    async def close(self):
        """Clean up resources"""
        if self.db_pool:
            await self.db_pool.close()
        if self.redis_client:
            await self.redis_client.close()
        if self.session:
            await self.session.close()

# Main alerting loop
async def main():
    config = {
        'database': {
            'host': 'postgres.pyairtable-system.svc.cluster.local',
            'port': 5432,
            'user': 'pyairtable_security',
            'password': 'secure_password',
            'name': 'pyairtable_security'
        },
        'redis': {
            'host': 'redis.pyairtable-system.svc.cluster.local',
            'port': 6379
        },
        'notifications': {
            'email': {
                'enabled': True,
                'smtp_host': 'smtp.gmail.com',
                'smtp_port': 587,
                'from_address': 'security@pyairtable.com',
                'to_addresses': ['admin@pyairtable.com', 'security-team@pyairtable.com'],
                'username': 'security@pyairtable.com',
                'password': 'app_password'
            },
            'slack': {
                'enabled': True,
                'webhook_url': 'https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK',
                'channel': '#security-alerts'
            },
            'pagerduty': {
                'enabled': True,
                'integration_key': 'your_pagerduty_integration_key'
            }
        },
        'retention_days': 90
    }
    
    alerting_system = SecurityAlertingSystem(config)
    await alerting_system.initialize()
    
    logger.info("Security alerting system started successfully")
    
    try:
        # Start event listening and cleanup tasks
        await asyncio.gather(
            alerting_system.listen_for_events(),
            alerting_system.run_periodic_cleanup()
        )
    except KeyboardInterrupt:
        logger.info("Shutting down security alerting system")
    finally:
        await alerting_system.close()

if __name__ == "__main__":
    asyncio.run(main())