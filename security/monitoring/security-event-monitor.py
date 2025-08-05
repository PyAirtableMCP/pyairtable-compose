#!/usr/bin/env python3
"""
PyAirtable Security Event Monitoring System
Enterprise-grade security monitoring for real-time threat detection
"""

import asyncio
import json
import time
import uuid
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any
from dataclasses import dataclass, asdict
from enum import Enum
import logging
import re
import hashlib
from collections import defaultdict, Counter
import asyncpg
import redis.asyncio as redis
from prometheus_client import Counter as PrometheusCounter, Histogram, Gauge, start_http_server
import structlog

# Configure structured logging
structlog.configure(
    processors=[
        structlog.stdlib.filter_by_level,
        structlog.stdlib.add_logger_name,
        structlog.stdlib.add_log_level,
        structlog.stdlib.PositionalArgumentsFormatter(),
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.StackInfoRenderer(),
        structlog.processors.format_exc_info,
        structlog.processors.UnicodeDecoder(),
        structlog.processors.JSONRenderer()
    ],
    context_class=dict,
    logger_factory=structlog.stdlib.LoggerFactory(),
    cache_logger_on_first_use=True,
)

logger = structlog.get_logger(__name__)

class ThreatLevel(Enum):
    """Security threat severity levels following NIST standards"""
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"
    CRITICAL = "critical"

class EventType(Enum):
    """Security event types for classification"""
    FAILED_AUTH = "failed_authentication"
    UNAUTHORIZED_ACCESS = "unauthorized_access"
    INJECTION_ATTEMPT = "injection_attempt"
    PRIVILEGE_ESCALATION = "privilege_escalation"
    DATA_EXFILTRATION = "data_exfiltration"
    BRUTE_FORCE = "brute_force_attack"
    ANOMALOUS_BEHAVIOR = "anomalous_behavior"
    CONFIG_CHANGE = "configuration_change"
    SESSION_HIJACK = "session_hijacking"
    API_ABUSE = "api_abuse"

@dataclass
class SecurityEvent:
    """Security event data structure"""
    event_id: str
    timestamp: datetime
    event_type: EventType
    threat_level: ThreatLevel
    source_ip: str
    user_id: Optional[str]
    tenant_id: Optional[str]
    service_name: str
    endpoint: Optional[str]
    user_agent: Optional[str]
    payload: Dict[str, Any]
    threat_indicators: List[str]
    response_code: Optional[int]
    session_id: Optional[str]
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for JSON serialization"""
        data = asdict(self)
        data['timestamp'] = self.timestamp.isoformat()
        data['event_type'] = self.event_type.value
        data['threat_level'] = self.threat_level.value
        return data

class SecurityEventMonitor:
    """Main security event monitoring system"""
    
    def __init__(self, config: Dict[str, Any]):
        self.config = config
        self.redis_client = None
        self.db_pool = None
        
        # Prometheus metrics
        self.security_events_total = PrometheusCounter(
            'security_events_total',
            'Total security events detected',
            ['event_type', 'threat_level', 'service']
        )
        
        self.failed_auth_attempts = PrometheusCounter(
            'failed_authentication_attempts_total',
            'Failed authentication attempts',
            ['source_ip', 'user_id', 'service']
        )
        
        self.injection_attempts = PrometheusCounter(
            'injection_attempts_total',
            'SQL/NoSQL injection attempts detected',
            ['attack_type', 'source_ip', 'endpoint']
        )
        
        self.privilege_escalation_attempts = PrometheusCounter(
            'privilege_escalation_attempts_total',
            'Privilege escalation attempts',
            ['user_id', 'target_role', 'service']
        )
        
        self.brute_force_attacks = PrometheusCounter(
            'brute_force_attacks_total',
            'Brute force attacks detected',
            ['source_ip', 'target_endpoint']
        )
        
        self.threat_detection_latency = Histogram(
            'threat_detection_seconds',
            'Time taken to detect security threats',
            ['event_type']
        )
        
        self.active_threats = Gauge(
            'active_security_threats',
            'Number of active security threats',
            ['threat_level']
        )
        
        # Pattern matchers for threat detection
        self.sql_injection_patterns = [
            r"(\bUNION\b.*\bSELECT\b|\bSELECT\b.*\bFROM\b.*\bWHERE\b.*['\"].*['\"])",
            r"(\bDROP\b.*\bTABLE\b|\bDELETE\b.*\bFROM\b|\bINSERT\b.*\bINTO\b)",
            r"(['\"].*;\s*--|\bOR\b.*['\"].*['\"].*=.*['\"])",
            r"(\bEXEC\b|\bEXECUTE\b|\bSP_\w+)",
            r"((\%27)|(\'))\s*((\%6F)|o|(\%4F))((\%72)|r|(\%52))",
        ]
        
        self.xss_patterns = [
            r"<script[^>]*>.*?</script>",
            r"javascript:[^\"']*",
            r"on\w+\s*=\s*[\"'][^\"']*[\"']",
            r"<iframe[^>]*>.*?</iframe>",
            r"<object[^>]*>.*?</object>",
        ]
        
        self.command_injection_patterns = [
            r"[;&|`$(){}]",
            r"\b(cat|ls|pwd|whoami|id|uname|ps|netstat|nc|ncat|telnet|wget|curl)\b",
            r"(\.\.\/|\.\.\\|\/etc\/|\/bin\/|\/usr\/|\/var\/)",
        ]
        
        # Rate limiting tracking
        self.request_counters = defaultdict(Counter)
        self.failed_auth_counters = defaultdict(Counter)
        self.ip_reputation_cache = {}
        
    async def initialize(self):
        """Initialize database connections and Redis"""
        try:
            # Initialize PostgreSQL connection pool
            self.db_pool = await asyncpg.create_pool(
                host=self.config['database']['host'],
                port=self.config['database']['port'],
                user=self.config['database']['user'],
                password=self.config['database']['password'],
                database=self.config['database']['name'],
                min_size=5,
                max_size=20,
                command_timeout=60,
                server_settings={
                    'jit': 'off',
                    'application_name': 'security-monitor'
                }
            )
            
            # Initialize Redis connection
            self.redis_client = redis.Redis(
                host=self.config['redis']['host'],
                port=self.config['redis']['port'],
                password=self.config.get('redis', {}).get('password'),
                decode_responses=True,
                socket_connect_timeout=5,
                socket_timeout=5,
                retry_on_timeout=True,
                health_check_interval=30
            )
            
            # Initialize database schema
            await self.create_security_tables()
            
            logger.info("Security event monitor initialized successfully")
            
        except Exception as e:
            logger.error("Failed to initialize security monitor", error=str(e))
            raise
    
    async def create_security_tables(self):
        """Create security monitoring database tables"""
        async with self.db_pool.acquire() as conn:
            await conn.execute("""
                CREATE TABLE IF NOT EXISTS security_events (
                    event_id UUID PRIMARY KEY,
                    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                    event_type VARCHAR(50) NOT NULL,
                    threat_level VARCHAR(20) NOT NULL,
                    source_ip INET NOT NULL,
                    user_id UUID,
                    tenant_id UUID,
                    service_name VARCHAR(100) NOT NULL,
                    endpoint TEXT,
                    user_agent TEXT,
                    payload JSONB,
                    threat_indicators TEXT[],
                    response_code INTEGER,
                    session_id VARCHAR(255),
                    created_at TIMESTAMPTZ DEFAULT NOW(),
                    processed BOOLEAN DEFAULT FALSE,
                    INDEX (timestamp),
                    INDEX (event_type),
                    INDEX (threat_level),
                    INDEX (source_ip),
                    INDEX (user_id),
                    INDEX (tenant_id)
                );
                
                CREATE TABLE IF NOT EXISTS threat_intel (
                    id SERIAL PRIMARY KEY,
                    indicator_type VARCHAR(50) NOT NULL,
                    indicator_value TEXT NOT NULL UNIQUE,
                    threat_level VARCHAR(20) NOT NULL,
                    source VARCHAR(100) NOT NULL,
                    description TEXT,
                    created_at TIMESTAMPTZ DEFAULT NOW(),
                    expires_at TIMESTAMPTZ,
                    active BOOLEAN DEFAULT TRUE,
                    INDEX (indicator_type),
                    INDEX (indicator_value),
                    INDEX (threat_level)
                );
                
                CREATE TABLE IF NOT EXISTS security_incidents (
                    incident_id UUID PRIMARY KEY,
                    title VARCHAR(255) NOT NULL,
                    description TEXT,
                    severity VARCHAR(20) NOT NULL,
                    status VARCHAR(50) DEFAULT 'open',
                    assigned_to VARCHAR(100),
                    source_events UUID[],
                    investigation_notes TEXT,
                    created_at TIMESTAMPTZ DEFAULT NOW(),
                    updated_at TIMESTAMPTZ DEFAULT NOW(),
                    resolved_at TIMESTAMPTZ
                );
                
                CREATE TABLE IF NOT EXISTS ip_reputation (
                    ip_address INET PRIMARY KEY,
                    reputation_score INTEGER NOT NULL CHECK (reputation_score >= 0 AND reputation_score <= 100),
                    threat_types TEXT[],
                    last_seen TIMESTAMPTZ DEFAULT NOW(),
                    source VARCHAR(100),
                    created_at TIMESTAMPTZ DEFAULT NOW()
                );
                
                CREATE TABLE IF NOT EXISTS user_behavior_baselines (
                    user_id UUID PRIMARY KEY,
                    tenant_id UUID NOT NULL,
                    typical_login_hours INTEGER[],
                    typical_ip_ranges INET[],
                    typical_endpoints TEXT[],
                    avg_requests_per_minute NUMERIC,
                    last_updated TIMESTAMPTZ DEFAULT NOW(),
                    INDEX (tenant_id)
                );
            """)
            
            logger.info("Security monitoring tables created successfully")
    
    async def process_log_entry(self, log_data: Dict[str, Any]) -> Optional[SecurityEvent]:
        """Process a single log entry for security threats"""
        start_time = time.time()
        
        try:
            # Extract relevant fields from log entry
            source_ip = log_data.get('source_ip', '0.0.0.0')
            user_id = log_data.get('user_id')
            tenant_id = log_data.get('tenant_id')
            service_name = log_data.get('service', 'unknown')
            endpoint = log_data.get('endpoint')
            user_agent = log_data.get('user_agent', '')
            response_code = log_data.get('response_code')
            session_id = log_data.get('session_id')
            payload = log_data.get('payload', {})
            
            # Detect security threats
            threat_indicators = []
            event_type = None
            threat_level = ThreatLevel.LOW
            
            # Check for failed authentication
            if self.is_failed_authentication(log_data):
                event_type = EventType.FAILED_AUTH
                threat_level = await self.assess_auth_failure_threat(source_ip, user_id)
                threat_indicators.append("Failed authentication attempt")
                
                self.failed_auth_attempts.labels(
                    source_ip=source_ip,
                    user_id=user_id or 'anonymous',
                    service=service_name
                ).inc()
            
            # Check for injection attempts
            injection_type = self.detect_injection_attempt(log_data)
            if injection_type:
                event_type = EventType.INJECTION_ATTEMPT
                threat_level = ThreatLevel.HIGH
                threat_indicators.append(f"{injection_type} injection attempt detected")
                
                self.injection_attempts.labels(
                    attack_type=injection_type,
                    source_ip=source_ip,
                    endpoint=endpoint or 'unknown'
                ).inc()
            
            # Check for privilege escalation
            if self.detect_privilege_escalation(log_data):
                event_type = EventType.PRIVILEGE_ESCALATION
                threat_level = ThreatLevel.CRITICAL
                threat_indicators.append("Privilege escalation attempt")
                
                self.privilege_escalation_attempts.labels(
                    user_id=user_id or 'anonymous',
                    target_role=log_data.get('target_role', 'unknown'),
                    service=service_name
                ).inc()
            
            # Check for brute force attacks
            if await self.detect_brute_force_attack(source_ip, endpoint):
                event_type = EventType.BRUTE_FORCE
                threat_level = ThreatLevel.HIGH
                threat_indicators.append("Brute force attack pattern detected")
                
                self.brute_force_attacks.labels(
                    source_ip=source_ip,
                    target_endpoint=endpoint or 'multiple'
                ).inc()
            
            # Check for unauthorized access
            if self.detect_unauthorized_access(log_data):
                event_type = EventType.UNAUTHORIZED_ACCESS
                threat_level = ThreatLevel.MEDIUM
                threat_indicators.append("Unauthorized access attempt")
            
            # Check for anomalous behavior
            if await self.detect_anomalous_behavior(user_id, tenant_id, log_data):
                event_type = EventType.ANOMALOUS_BEHAVIOR
                threat_level = ThreatLevel.MEDIUM
                threat_indicators.append("Anomalous user behavior detected")
            
            # If no specific threat detected, check for general suspicious activity
            if not event_type and self.is_suspicious_activity(log_data):
                event_type = EventType.ANOMALOUS_BEHAVIOR
                threat_level = ThreatLevel.LOW
                threat_indicators.append("Suspicious activity pattern")
            
            # Create security event if threat detected
            if event_type and threat_indicators:
                security_event = SecurityEvent(
                    event_id=str(uuid.uuid4()),
                    timestamp=datetime.utcnow(),
                    event_type=event_type,
                    threat_level=threat_level,
                    source_ip=source_ip,
                    user_id=user_id,
                    tenant_id=tenant_id,
                    service_name=service_name,
                    endpoint=endpoint,
                    user_agent=user_agent,
                    payload=payload,
                    threat_indicators=threat_indicators,
                    response_code=response_code,
                    session_id=session_id
                )
                
                # Record metrics
                self.security_events_total.labels(
                    event_type=event_type.value,
                    threat_level=threat_level.value,
                    service=service_name
                ).inc()
                
                self.threat_detection_latency.labels(
                    event_type=event_type.value
                ).observe(time.time() - start_time)
                
                # Store event
                await self.store_security_event(security_event)
                
                # Trigger real-time alerting for high/critical threats
                if threat_level in [ThreatLevel.HIGH, ThreatLevel.CRITICAL]:
                    await self.trigger_security_alert(security_event)
                
                logger.info(
                    "Security event detected",
                    event_id=security_event.event_id,
                    event_type=event_type.value,
                    threat_level=threat_level.value,
                    source_ip=source_ip,
                    service=service_name
                )
                
                return security_event
                
        except Exception as e:
            logger.error("Error processing log entry", error=str(e), log_data=log_data)
        
        return None
    
    def is_failed_authentication(self, log_data: Dict[str, Any]) -> bool:
        """Detect failed authentication attempts"""
        response_code = log_data.get('response_code')
        endpoint = log_data.get('endpoint', '').lower()
        message = log_data.get('message', '').lower()
        
        # HTTP status codes indicating auth failure
        if response_code in [401, 403]:
            return True
        
        # Auth-related endpoints
        auth_endpoints = ['/auth', '/login', '/signin', '/token', '/oauth']
        if any(auth_ep in endpoint for auth_ep in auth_endpoints):
            if response_code in [400, 422]:  # Bad request often indicates failed auth
                return True
        
        # Log message patterns
        auth_failure_patterns = [
            'authentication failed',
            'invalid credentials',
            'login failed',
            'unauthorized',
            'access denied',
            'invalid token',
            'expired token'
        ]
        
        return any(pattern in message for pattern in auth_failure_patterns)
    
    def detect_injection_attempt(self, log_data: Dict[str, Any]) -> Optional[str]:
        """Detect various injection attack attempts"""
        # Check URL parameters, body, and headers
        check_fields = [
            log_data.get('url', ''),
            str(log_data.get('payload', {})),
            str(log_data.get('headers', {})),
            log_data.get('query_string', '')
        ]
        
        combined_input = ' '.join(check_fields).lower()
        
        # SQL Injection detection
        for pattern in self.sql_injection_patterns:
            if re.search(pattern, combined_input, re.IGNORECASE):
                return "SQL"
        
        # XSS detection
        for pattern in self.xss_patterns:
            if re.search(pattern, combined_input, re.IGNORECASE):
                return "XSS"
        
        # Command injection detection
        for pattern in self.command_injection_patterns:
            if re.search(pattern, combined_input):
                return "Command"
        
        # NoSQL injection detection
        nosql_patterns = [
            r'\$where', r'\$ne', r'\$gt', r'\$lt', r'\$regex',
            r'{\s*\$[a-zA-Z]+\s*:', r'ObjectId\s*\('
        ]
        
        for pattern in nosql_patterns:
            if re.search(pattern, combined_input, re.IGNORECASE):
                return "NoSQL"
        
        return None
    
    def detect_privilege_escalation(self, log_data: Dict[str, Any]) -> bool:
        """Detect privilege escalation attempts"""
        endpoint = log_data.get('endpoint', '').lower()
        payload = log_data.get('payload', {})
        user_role = log_data.get('user_role', '').lower()
        
        # Admin endpoint access by non-admin users
        admin_endpoints = ['/admin', '/manage', '/config', '/system', '/api/admin']
        if any(admin_ep in endpoint for admin_ep in admin_endpoints):
            if user_role not in ['admin', 'superuser', 'root']:
                return True
        
        # Role modification attempts
        if isinstance(payload, dict):
            sensitive_fields = ['role', 'permissions', 'privileges', 'admin', 'superuser']
            for field in sensitive_fields:
                if field in str(payload).lower():
                    return True
        
        # Suspicious parameter manipulation
        suspicious_params = ['user_id', 'tenant_id', 'role', 'admin', 'sudo']
        query_string = log_data.get('query_string', '').lower()
        
        for param in suspicious_params:
            if f"{param}=" in query_string and log_data.get('user_id'):
                # Check if trying to access different user's data
                if f"{param}={log_data['user_id']}" not in query_string:
                    return True
        
        return False
    
    async def detect_brute_force_attack(self, source_ip: str, endpoint: Optional[str]) -> bool:
        """Detect brute force attack patterns"""
        current_time = int(time.time())
        window_size = 300  # 5 minutes
        threshold = 20  # 20 failed attempts in 5 minutes
        
        # Use Redis to track failed attempts
        key = f"failed_attempts:{source_ip}"
        
        try:
            # Add current attempt
            await self.redis_client.zadd(key, {current_time: current_time})
            
            # Remove old entries
            await self.redis_client.zremrangebyscore(key, 0, current_time - window_size)
            
            # Count attempts in current window
            attempt_count = await self.redis_client.zcard(key)
            
            # Set expiration
            await self.redis_client.expire(key, window_size)
            
            return attempt_count >= threshold
            
        except Exception as e:
            logger.error("Error checking brute force", error=str(e))
            return False
    
    def detect_unauthorized_access(self, log_data: Dict[str, Any]) -> bool:
        """Detect unauthorized access attempts"""
        response_code = log_data.get('response_code')
        endpoint = log_data.get('endpoint', '')
        user_id = log_data.get('user_id')
        
        # Access to protected resources without authentication
        protected_patterns = ['/api/', '/admin/', '/dashboard/', '/user/']
        if any(pattern in endpoint for pattern in protected_patterns):
            if not user_id and response_code == 200:
                return True  # Successful access without user context is suspicious
        
        # Directory traversal attempts
        if '../' in endpoint or '..\\' in endpoint:
            return True
        
        # Access to sensitive files
        sensitive_files = ['.env', 'config', 'secret', 'key', 'passwd', 'shadow']
        if any(sensitive in endpoint.lower() for sensitive in sensitive_files):
            return True
        
        return False
    
    async def detect_anomalous_behavior(self, user_id: Optional[str], tenant_id: Optional[str], log_data: Dict[str, Any]) -> bool:
        """Detect anomalous user behavior based on baselines"""
        if not user_id:
            return False
        
        try:
            # Get user behavior baseline
            async with self.db_pool.acquire() as conn:
                baseline = await conn.fetchrow(
                    "SELECT * FROM user_behavior_baselines WHERE user_id = $1",
                    user_id
                )
            
            if not baseline:
                return False  # No baseline established yet
            
            source_ip = log_data.get('source_ip')
            endpoint = log_data.get('endpoint')
            current_hour = datetime.utcnow().hour
            
            # Check for unusual login times
            if current_hour not in baseline['typical_login_hours']:
                return True
            
            # Check for unusual IP addresses (simplified geolocation check)
            # In production, you'd use a proper geolocation service
            if source_ip and not any(
                self.ip_in_range(source_ip, ip_range) 
                for ip_range in baseline['typical_ip_ranges']
            ):
                return True
            
            # Check for access to unusual endpoints
            if endpoint and endpoint not in baseline['typical_endpoints']:
                return True
            
            return False
            
        except Exception as e:
            logger.error("Error detecting anomalous behavior", error=str(e))
            return False
    
    def is_suspicious_activity(self, log_data: Dict[str, Any]) -> bool:
        """Detect general suspicious activity patterns"""
        user_agent = log_data.get('user_agent', '').lower()
        endpoint = log_data.get('endpoint', '')
        source_ip = log_data.get('source_ip', '')
        
        # Suspicious user agents
        suspicious_agents = [
            'bot', 'crawler', 'spider', 'scan', 'curl', 'wget', 'python',
            'automated', 'test', 'hack', 'exploit'
        ]
        
        if any(agent in user_agent for agent in suspicious_agents):
            return True
        
        # Scanning behavior
        if any(scan_pattern in endpoint.lower() for scan_pattern in [
            '.php', '.asp', '.jsp', 'admin', 'backup', 'test', 'dev'
        ]):
            return True
        
        # Private IP ranges accessing public endpoints (potential proxy/VPN)
        if self.is_private_ip(source_ip) and log_data.get('response_code') == 200:
            return True
        
        return False
    
    async def assess_auth_failure_threat(self, source_ip: str, user_id: Optional[str]) -> ThreatLevel:
        """Assess threat level for authentication failures"""
        current_time = int(time.time())
        window_size = 300  # 5 minutes
        
        try:
            # Count recent failures from this IP
            ip_key = f"auth_failures:ip:{source_ip}"
            await self.redis_client.zadd(ip_key, {current_time: current_time})
            await self.redis_client.zremrangebyscore(ip_key, 0, current_time - window_size)
            ip_failures = await self.redis_client.zcard(ip_key)
            await self.redis_client.expire(ip_key, window_size)
            
            # Count recent failures for this user
            user_failures = 0
            if user_id:
                user_key = f"auth_failures:user:{user_id}"
                await self.redis_client.zadd(user_key, {current_time: current_time})
                await self.redis_client.zremrangebyscore(user_key, 0, current_time - window_size)
                user_failures = await self.redis_client.zcard(user_key)
                await self.redis_client.expire(user_key, window_size)
            
            # Assess threat level based on failure counts
            if ip_failures >= 50 or user_failures >= 20:
                return ThreatLevel.CRITICAL
            elif ip_failures >= 20 or user_failures >= 10:
                return ThreatLevel.HIGH
            elif ip_failures >= 10 or user_failures >= 5:
                return ThreatLevel.MEDIUM
            else:
                return ThreatLevel.LOW
                
        except Exception as e:
            logger.error("Error assessing auth failure threat", error=str(e))
            return ThreatLevel.MEDIUM
    
    async def store_security_event(self, event: SecurityEvent):
        """Store security event in database"""
        try:
            async with self.db_pool.acquire() as conn:
                await conn.execute("""
                    INSERT INTO security_events 
                    (event_id, timestamp, event_type, threat_level, source_ip, user_id, 
                     tenant_id, service_name, endpoint, user_agent, payload, 
                     threat_indicators, response_code, session_id)
                    VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)
                """, 
                    event.event_id,
                    event.timestamp,
                    event.event_type.value,
                    event.threat_level.value,
                    event.source_ip,
                    event.user_id,
                    event.tenant_id,
                    event.service_name,
                    event.endpoint,
                    event.user_agent,
                    json.dumps(event.payload),
                    event.threat_indicators,
                    event.response_code,
                    event.session_id
                )
            
            # Also store in Redis for real-time access
            await self.redis_client.setex(
                f"security_event:{event.event_id}",
                3600,  # 1 hour TTL
                json.dumps(event.to_dict())
            )
            
        except Exception as e:
            logger.error("Error storing security event", error=str(e), event_id=event.event_id)
    
    async def trigger_security_alert(self, event: SecurityEvent):
        """Trigger real-time security alerts for high-priority events"""
        try:
            alert_data = {
                'alert_id': str(uuid.uuid4()),
                'timestamp': event.timestamp.isoformat(),
                'event_id': event.event_id,
                'threat_level': event.threat_level.value,
                'event_type': event.event_type.value,
                'source_ip': event.source_ip,
                'service': event.service_name,
                'threat_indicators': event.threat_indicators,
                'recommended_actions': self.get_recommended_actions(event)
            }
            
            # Publish to Redis for real-time alerting
            await self.redis_client.publish('security_alerts', json.dumps(alert_data))
            
            # Update active threat gauge
            self.active_threats.labels(threat_level=event.threat_level.value).inc()
            
            logger.warning(
                "Security alert triggered",
                alert_id=alert_data['alert_id'],
                event_id=event.event_id,
                threat_level=event.threat_level.value
            )
            
        except Exception as e:
            logger.error("Error triggering security alert", error=str(e))
    
    def get_recommended_actions(self, event: SecurityEvent) -> List[str]:
        """Get recommended actions based on event type"""
        actions = []
        
        if event.event_type == EventType.BRUTE_FORCE:
            actions.extend([
                f"Block IP address {event.source_ip}",
                "Implement rate limiting",
                "Force password reset for targeted accounts"
            ])
        
        elif event.event_type == EventType.INJECTION_ATTEMPT:
            actions.extend([
                "Review input validation",
                "Check WAF rules",
                "Audit database permissions"
            ])
        
        elif event.event_type == EventType.PRIVILEGE_ESCALATION:
            actions.extend([
                "Audit user permissions",
                "Review access controls",
                "Investigate user account"
            ])
        
        elif event.event_type == EventType.UNAUTHORIZED_ACCESS:
            actions.extend([
                "Verify authentication mechanisms",
                "Check session management",
                "Review access logs"
            ])
        
        return actions
    
    def ip_in_range(self, ip: str, ip_range: str) -> bool:
        """Check if IP is in given range (simplified)"""
        # This is a simplified implementation
        # In production, use ipaddress module for proper CIDR checking
        try:
            import ipaddress
            return ipaddress.ip_address(ip) in ipaddress.ip_network(ip_range, strict=False)
        except:
            return False
    
    def is_private_ip(self, ip: str) -> bool:
        """Check if IP is in private ranges"""
        try:
            import ipaddress
            ip_obj = ipaddress.ip_address(ip)
            return ip_obj.is_private
        except:
            return False
    
    async def cleanup_old_events(self):
        """Clean up old security events (run periodically)"""
        try:
            retention_days = self.config.get('retention_days', 90)
            cutoff_date = datetime.utcnow() - timedelta(days=retention_days)
            
            async with self.db_pool.acquire() as conn:
                deleted_count = await conn.fetchval(
                    "DELETE FROM security_events WHERE timestamp < $1",
                    cutoff_date
                )
            
            logger.info("Cleaned up old security events", deleted_count=deleted_count)
            
        except Exception as e:
            logger.error("Error cleaning up old events", error=str(e))
    
    async def close(self):
        """Clean up resources"""
        if self.db_pool:
            await self.db_pool.close()
        if self.redis_client:
            await self.redis_client.close()

# Main monitoring loop
async def main():
    config = {
        'database': {
            'host': 'postgres.pyairtable-system.svc.cluster.local',
            'port': 5432,
            'user': 'pyairtable_security',
            'password': 'secure_password',  # From Vault in production
            'name': 'pyairtable_security'
        },
        'redis': {
            'host': 'redis.pyairtable-system.svc.cluster.local',
            'port': 6379
        },
        'retention_days': 90
    }
    
    # Start Prometheus metrics server
    start_http_server(8090)
    
    monitor = SecurityEventMonitor(config)
    await monitor.initialize()
    
    logger.info("Security event monitor started successfully")
    
    try:
        # In production, this would consume from log streams (Kafka, Redis Streams, etc.)
        while True:
            await asyncio.sleep(1)
            # Process incoming log data
            
    except KeyboardInterrupt:
        logger.info("Shutting down security monitor")
    finally:
        await monitor.close()

if __name__ == "__main__":
    asyncio.run(main())