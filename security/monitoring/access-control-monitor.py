#!/usr/bin/env python3
"""
PyAirtable Access Control Monitoring System
Comprehensive monitoring of user access, authentication events, and session management
"""

import asyncio
import json
import time
import uuid
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any, Set
from dataclasses import dataclass, asdict
from enum import Enum
import logging
from collections import defaultdict, deque
import hashlib
import jwt
import asyncpg
import redis.asyncio as redis
from prometheus_client import Counter, Histogram, Gauge, Info
import structlog
from ipaddress import ip_address, ip_network

logger = structlog.get_logger(__name__)

class AccessEventType(Enum):
    """Access control event types"""
    LOGIN_SUCCESS = "login_success"
    LOGIN_FAILURE = "login_failure" 
    LOGOUT = "logout"
    SESSION_CREATED = "session_created"
    SESSION_EXPIRED = "session_expired"
    SESSION_HIJACK = "session_hijacking"
    TOKEN_ISSUED = "token_issued"
    TOKEN_REFRESH = "token_refresh"
    TOKEN_REVOKED = "token_revoked"
    API_KEY_USED = "api_key_used"
    API_KEY_ABUSE = "api_key_abuse"
    PRIVILEGE_CHANGE = "privilege_change"
    ADMIN_ACTION = "admin_action"
    SUSPICIOUS_LOGIN = "suspicious_login"
    CONCURRENT_SESSIONS = "concurrent_sessions"

class RiskLevel(Enum):
    """Risk assessment levels"""
    VERY_LOW = "very_low"
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"
    CRITICAL = "critical"

@dataclass
class AccessEvent:
    """Access control event data structure"""
    event_id: str
    timestamp: datetime
    event_type: AccessEventType
    risk_level: RiskLevel
    user_id: Optional[str]
    tenant_id: Optional[str]
    session_id: Optional[str]
    source_ip: str
    user_agent: str
    location: Optional[Dict[str, str]]
    device_info: Dict[str, Any]
    success: bool
    failure_reason: Optional[str]
    authentication_method: str
    privileges: List[str]
    api_key_id: Optional[str]
    service_name: str
    endpoint: Optional[str]
    metadata: Dict[str, Any]
    
    def to_dict(self) -> Dict[str, Any]:
        data = asdict(self)
        data['timestamp'] = self.timestamp.isoformat()
        data['event_type'] = self.event_type.value
        data['risk_level'] = self.risk_level.value
        return data

@dataclass
class UserSession:
    """User session tracking"""
    session_id: str
    user_id: str
    tenant_id: str
    created_at: datetime
    last_activity: datetime
    source_ip: str
    user_agent: str
    device_fingerprint: str
    is_active: bool
    privileges: List[str]
    login_method: str
    risk_score: float

@dataclass
class APIKeyUsage:
    """API key usage tracking"""
    api_key_id: str
    key_hash: str
    user_id: str
    tenant_id: str
    service_name: str
    request_count: int
    last_used: datetime
    source_ips: Set[str]
    endpoints_accessed: Set[str]
    rate_limit_violations: int
    suspicious_activity: bool

class AccessControlMonitor:
    """Access control and session monitoring system"""
    
    def __init__(self, config: Dict[str, Any]):
        self.config = config
        self.redis_client = None
        self.db_pool = None
        
        # Session tracking
        self.active_sessions: Dict[str, UserSession] = {}
        self.api_key_usage: Dict[str, APIKeyUsage] = {}
        self.user_login_attempts = defaultdict(deque)
        self.ip_login_attempts = defaultdict(deque)
        
        # Geolocation cache
        self.geo_cache = {}
        
        # Prometheus metrics
        self.login_attempts_total = Counter(
            'access_login_attempts_total',
            'Total login attempts',
            ['status', 'method', 'tenant']
        )
        
        self.active_sessions_gauge = Gauge(
            'access_active_sessions',
            'Number of active user sessions',
            ['tenant']
        )
        
        self.session_duration_histogram = Histogram(
            'access_session_duration_seconds',
            'Session duration in seconds',
            ['tenant', 'user_type']
        )
        
        self.api_key_requests_total = Counter(
            'access_api_key_requests_total',
            'API key usage requests',
            ['api_key_id', 'service', 'status']
        )
        
        self.privilege_escalations_total = Counter(
            'access_privilege_escalations_total',
            'Privilege escalation events',
            ['user_id', 'from_role', 'to_role']
        )
        
        self.suspicious_logins_total = Counter(
            'access_suspicious_logins_total',
            'Suspicious login attempts',
            ['reason', 'tenant']
        )
        
        self.concurrent_sessions_gauge = Gauge(
            'access_concurrent_sessions',
            'Concurrent sessions per user',
            ['user_id', 'tenant']
        )
        
        self.admin_actions_total = Counter(
            'access_admin_actions_total',
            'Administrative actions performed',
            ['admin_user', 'action_type', 'tenant']
        )
        
        # Risk scoring weights
        self.risk_weights = {
            'new_location': 0.3,
            'new_device': 0.2,
            'off_hours': 0.15,
            'multiple_failures': 0.25,
            'unusual_agent': 0.1
        }
        
    async def initialize(self):
        """Initialize connections and database schema"""
        try:
            # Initialize PostgreSQL connection pool
            self.db_pool = await asyncpg.create_pool(
                host=self.config['database']['host'],
                port=self.config['database']['port'],
                user=self.config['database']['user'],  
                password=self.config['database']['password'],
                database=self.config['database']['name'],
                min_size=5,
                max_size=15,
                command_timeout=60
            )
            
            # Initialize Redis connection
            self.redis_client = redis.Redis(
                host=self.config['redis']['host'],
                port=self.config['redis']['port'],
                password=self.config.get('redis', {}).get('password'),
                decode_responses=True
            )
            
            # Create database schema
            await self.create_access_tables()
            
            # Load existing sessions from database
            await self.load_active_sessions()
            
            logger.info("Access control monitor initialized successfully")
            
        except Exception as e:
            logger.error("Failed to initialize access control monitor", error=str(e))
            raise
    
    async def create_access_tables(self):
        """Create access control monitoring tables"""
        async with self.db_pool.acquire() as conn:
            await conn.execute("""
                CREATE TABLE IF NOT EXISTS access_events (
                    event_id UUID PRIMARY KEY,
                    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                    event_type VARCHAR(50) NOT NULL,
                    risk_level VARCHAR(20) NOT NULL,
                    user_id UUID,
                    tenant_id UUID,
                    session_id VARCHAR(255),
                    source_ip INET NOT NULL,
                    user_agent TEXT,
                    location JSONB,
                    device_info JSONB,
                    success BOOLEAN NOT NULL,
                    failure_reason TEXT,
                    authentication_method VARCHAR(50),
                    privileges TEXT[],
                    api_key_id VARCHAR(255),
                    service_name VARCHAR(100),
                    endpoint TEXT,
                    metadata JSONB,
                    INDEX (timestamp),
                    INDEX (event_type),
                    INDEX (user_id),
                    INDEX (tenant_id),
                    INDEX (source_ip),
                    INDEX (session_id)
                );
                
                CREATE TABLE IF NOT EXISTS user_sessions (
                    session_id VARCHAR(255) PRIMARY KEY,
                    user_id UUID NOT NULL,
                    tenant_id UUID NOT NULL,
                    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                    last_activity TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                    source_ip INET NOT NULL,
                    user_agent TEXT,
                    device_fingerprint VARCHAR(255),
                    is_active BOOLEAN DEFAULT TRUE,
                    privileges TEXT[],
                    login_method VARCHAR(50),
                    risk_score NUMERIC(5,2) DEFAULT 0,
                    expires_at TIMESTAMPTZ,
                    INDEX (user_id),
                    INDEX (tenant_id),
                    INDEX (is_active),
                    INDEX (created_at)
                );
                
                CREATE TABLE IF NOT EXISTS api_keys (
                    api_key_id VARCHAR(255) PRIMARY KEY,
                    key_hash VARCHAR(255) UNIQUE NOT NULL,
                    user_id UUID NOT NULL,
                    tenant_id UUID NOT NULL,
                    name VARCHAR(255),
                    permissions TEXT[],
                    created_at TIMESTAMPTZ DEFAULT NOW(),
                    last_used TIMESTAMPTZ,
                    usage_count INTEGER DEFAULT 0,
                    rate_limit_per_minute INTEGER DEFAULT 100,
                    is_active BOOLEAN DEFAULT TRUE,
                    expires_at TIMESTAMPTZ,
                    allowed_ips INET[],
                    INDEX (user_id),
                    INDEX (tenant_id),
                    INDEX (is_active)
                );
                
                CREATE TABLE IF NOT EXISTS login_history (
                    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                    user_id UUID NOT NULL,
                    tenant_id UUID NOT NULL,
                    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                    source_ip INET NOT NULL,
                    user_agent TEXT,
                    success BOOLEAN NOT NULL,
                    failure_reason TEXT,
                    location JSONB,
                    device_info JSONB,
                    risk_score NUMERIC(5,2),
                    INDEX (user_id),
                    INDEX (tenant_id),
                    INDEX (timestamp),
                    INDEX (source_ip)
                );
                
                CREATE TABLE IF NOT EXISTS privilege_changes (
                    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                    user_id UUID NOT NULL,
                    tenant_id UUID NOT NULL,
                    changed_by UUID NOT NULL,
                    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                    previous_privileges TEXT[],
                    new_privileges TEXT[],
                    reason TEXT,
                    approved_by UUID,
                    INDEX (user_id),
                    INDEX (tenant_id),
                    INDEX (changed_by),
                    INDEX (timestamp)
                );
                
                CREATE TABLE IF NOT EXISTS user_behavior_profiles (
                    user_id UUID PRIMARY KEY,
                    tenant_id UUID NOT NULL,
                    typical_login_hours INTEGER[],
                    typical_locations JSONB[],
                    typical_devices JSONB[],
                    typical_ips INET[],
                    login_frequency_pattern JSONB,
                    last_updated TIMESTAMPTZ DEFAULT NOW(),
                    INDEX (tenant_id)
                );
            """)
    
    async def load_active_sessions(self):
        """Load active sessions from database"""
        try:
            async with self.db_pool.acquire() as conn:
                rows = await conn.fetch("""
                    SELECT * FROM user_sessions 
                    WHERE is_active = TRUE 
                    AND (expires_at IS NULL OR expires_at > NOW())
                """)
                
                for row in rows:
                    session = UserSession(
                        session_id=row['session_id'],
                        user_id=row['user_id'],
                        tenant_id=row['tenant_id'],
                        created_at=row['created_at'],
                        last_activity=row['last_activity'],
                        source_ip=str(row['source_ip']),
                        user_agent=row['user_agent'] or '',
                        device_fingerprint=row['device_fingerprint'] or '',
                        is_active=row['is_active'],
                        privileges=row['privileges'] or [],
                        login_method=row['login_method'] or 'password',
                        risk_score=float(row['risk_score'] or 0)
                    )
                    self.active_sessions[session.session_id] = session
                
                logger.info(f"Loaded {len(self.active_sessions)} active sessions")
                
        except Exception as e:
            logger.error("Error loading active sessions", error=str(e))
    
    async def process_authentication_event(self, auth_data: Dict[str, Any]) -> Optional[AccessEvent]:
        """Process authentication events (login/logout)"""
        try:
            user_id = auth_data.get('user_id')
            tenant_id = auth_data.get('tenant_id')
            source_ip = auth_data.get('source_ip', '0.0.0.0')
            user_agent = auth_data.get('user_agent', '')
            success = auth_data.get('success', False)
            session_id = auth_data.get('session_id')
            auth_method = auth_data.get('method', 'password')
            service = auth_data.get('service', 'unknown')
            
            # Determine event type
            if auth_data.get('action') == 'login':
                event_type = AccessEventType.LOGIN_SUCCESS if success else AccessEventType.LOGIN_FAILURE
            elif auth_data.get('action') == 'logout':
                event_type = AccessEventType.LOGOUT
            else:
                event_type = AccessEventType.LOGIN_FAILURE
            
            # Get device and location info
            device_info = self.extract_device_info(user_agent)
            location = await self.get_location_info(source_ip)
            
            # Calculate risk score
            risk_score = await self.calculate_login_risk(
                user_id, tenant_id, source_ip, user_agent, device_info, location
            )
            
            risk_level = self.risk_score_to_level(risk_score)
            
            # Check for suspicious activity
            is_suspicious = await self.detect_suspicious_login(
                user_id, tenant_id, source_ip, user_agent, success
            )
            
            if is_suspicious:
                event_type = AccessEventType.SUSPICIOUS_LOGIN
                risk_level = RiskLevel.HIGH
            
            # Create access event
            access_event = AccessEvent(
                event_id=str(uuid.uuid4()),
                timestamp=datetime.utcnow(),
                event_type=event_type,
                risk_level=risk_level,
                user_id=user_id,
                tenant_id=tenant_id,
                session_id=session_id,
                source_ip=source_ip,
                user_agent=user_agent,
                location=location,
                device_info=device_info,
                success=success,
                failure_reason=auth_data.get('failure_reason'),
                authentication_method=auth_method,
                privileges=auth_data.get('privileges', []),
                api_key_id=None,
                service_name=service,
                endpoint=auth_data.get('endpoint'),
                metadata={
                    'risk_score': risk_score,
                    'is_suspicious': is_suspicious
                }
            )
            
            # Update metrics
            self.login_attempts_total.labels(
                status='success' if success else 'failure',
                method=auth_method,
                tenant=tenant_id or 'unknown'
            ).inc()
            
            if is_suspicious:
                self.suspicious_logins_total.labels(
                    reason='risk_analysis',
                    tenant=tenant_id or 'unknown'
                ).inc()
            
            # Handle successful login
            if success and event_type == AccessEventType.LOGIN_SUCCESS:
                await self.handle_successful_login(access_event, auth_data)
            
            # Handle logout
            elif event_type == AccessEventType.LOGOUT:
                await self.handle_logout(access_event)
            
            # Store event
            await self.store_access_event(access_event)
            
            # Record login history
            await self.record_login_history(access_event)
            
            return access_event
            
        except Exception as e:
            logger.error("Error processing authentication event", error=str(e))
            return None
    
    async def handle_successful_login(self, event: AccessEvent, auth_data: Dict[str, Any]):
        """Handle successful login - create session, update metrics"""
        try:
            session_id = event.session_id or str(uuid.uuid4())
            
            # Create user session
            session = UserSession(
                session_id=session_id,
                user_id=event.user_id,
                tenant_id=event.tenant_id,
                created_at=event.timestamp,
                last_activity=event.timestamp,
                source_ip=event.source_ip,
                user_agent=event.user_agent,
                device_fingerprint=self.generate_device_fingerprint(event.device_info),
                is_active=True,
                privileges=event.privileges,
                login_method=event.authentication_method,
                risk_score=event.metadata.get('risk_score', 0.0)
            )
            
            self.active_sessions[session_id] = session
            
            # Store session in database
            await self.store_session(session)
            
            # Update concurrent sessions tracking
            user_sessions = [s for s in self.active_sessions.values() if s.user_id == event.user_id]
            self.concurrent_sessions_gauge.labels(
                user_id=event.user_id,
                tenant=event.tenant_id
            ).set(len(user_sessions))
            
            # Check for excessive concurrent sessions
            if len(user_sessions) > self.config.get('max_concurrent_sessions', 5):
                await self.handle_excessive_sessions(event.user_id, user_sessions)
            
            # Update active sessions gauge
            tenant_sessions = [s for s in self.active_sessions.values() if s.tenant_id == event.tenant_id]
            self.active_sessions_gauge.labels(tenant=event.tenant_id).set(len(tenant_sessions))
            
            logger.info(
                "User login successful",
                user_id=event.user_id,
                session_id=session_id,
                source_ip=event.source_ip,
                risk_score=session.risk_score
            )
            
        except Exception as e:
            logger.error("Error handling successful login", error=str(e))
    
    async def handle_logout(self, event: AccessEvent):
        """Handle user logout - cleanup session"""
        try:
            if event.session_id and event.session_id in self.active_sessions:
                session = self.active_sessions[event.session_id]
                
                # Calculate session duration
                duration = (event.timestamp - session.created_at).total_seconds()
                self.session_duration_histogram.labels(
                    tenant=session.tenant_id,
                    user_type='regular'  # Could be determined from privileges
                ).observe(duration)
                
                # Mark session as inactive
                session.is_active = False
                await self.update_session_status(event.session_id, False)
                
                # Remove from active sessions
                del self.active_sessions[event.session_id]
                
                # Update metrics
                tenant_sessions = [s for s in self.active_sessions.values() if s.tenant_id == event.tenant_id]
                self.active_sessions_gauge.labels(tenant=event.tenant_id).set(len(tenant_sessions))
                
                user_sessions = [s for s in self.active_sessions.values() if s.user_id == event.user_id]
                self.concurrent_sessions_gauge.labels(
                    user_id=event.user_id,
                    tenant=event.tenant_id
                ).set(len(user_sessions))
                
                logger.info(
                    "User logout processed",
                    user_id=event.user_id,
                    session_id=event.session_id,
                    duration_seconds=duration
                )
                
        except Exception as e:
            logger.error("Error handling logout", error=str(e))
    
    async def process_api_key_event(self, api_data: Dict[str, Any]) -> Optional[AccessEvent]:
        """Process API key usage events"""
        try:
            api_key_id = api_data.get('api_key_id')
            user_id = api_data.get('user_id')
            tenant_id = api_data.get('tenant_id')
            source_ip = api_data.get('source_ip', '0.0.0.0')
            service = api_data.get('service', 'api')
            endpoint = api_data.get('endpoint')
            success = api_data.get('success', True)
            
            # Track API key usage
            if api_key_id:
                await self.track_api_key_usage(api_key_id, source_ip, endpoint)
                
                # Check for API key abuse
                is_abuse = await self.detect_api_key_abuse(api_key_id, source_ip)
                
                event_type = AccessEventType.API_KEY_ABUSE if is_abuse else AccessEventType.API_KEY_USED
                risk_level = RiskLevel.HIGH if is_abuse else RiskLevel.LOW
                
                # Create access event
                access_event = AccessEvent(
                    event_id=str(uuid.uuid4()),
                    timestamp=datetime.utcnow(),
                    event_type=event_type,
                    risk_level=risk_level,
                    user_id=user_id,
                    tenant_id=tenant_id,
                    session_id=None,
                    source_ip=source_ip,
                    user_agent=api_data.get('user_agent', ''),
                    location=await self.get_location_info(source_ip),
                    device_info={},
                    success=success,
                    failure_reason=api_data.get('failure_reason'),
                    authentication_method='api_key',
                    privileges=api_data.get('privileges', []),
                    api_key_id=api_key_id,
                    service_name=service,
                    endpoint=endpoint,
                    metadata={'abuse_detected': is_abuse}
                )
                
                # Update metrics
                self.api_key_requests_total.labels(
                    api_key_id=api_key_id,
                    service=service,
                    status='success' if success else 'failure'
                ).inc()
                
                await self.store_access_event(access_event)
                return access_event
                
        except Exception as e:
            logger.error("Error processing API key event", error=str(e))
            
        return None
    
    async def track_api_key_usage(self, api_key_id: str, source_ip: str, endpoint: Optional[str]):
        """Track API key usage patterns"""
        try:
            current_time = int(time.time())
            
            # Use Redis to track usage
            usage_key = f"api_usage:{api_key_id}"
            
            # Track request count
            await self.redis_client.incr(f"{usage_key}:count")
            await self.redis_client.expire(f"{usage_key}:count", 3600)  # 1 hour window
            
            # Track unique IPs
            await self.redis_client.sadd(f"{usage_key}:ips", source_ip)
            await self.redis_client.expire(f"{usage_key}:ips", 3600)
            
            # Track endpoints
            if endpoint:
                await self.redis_client.sadd(f"{usage_key}:endpoints", endpoint)
                await self.redis_client.expire(f"{usage_key}:endpoints", 3600)
            
            # Track rate limiting
            rate_key = f"api_rate:{api_key_id}:{current_time // 60}"  # Per minute
            count = await self.redis_client.incr(rate_key)
            await self.redis_client.expire(rate_key, 60)
            
            # Check rate limit (should be configured per API key)
            if count > 100:  # Default rate limit
                await self.record_rate_limit_violation(api_key_id, source_ip)
            
        except Exception as e:
            logger.error("Error tracking API key usage", error=str(e))
    
    async def detect_api_key_abuse(self, api_key_id: str, source_ip: str) -> bool:
        """Detect API key abuse patterns"""
        try:
            usage_key = f"api_usage:{api_key_id}"
            
            # Check request count in last hour
            request_count = await self.redis_client.get(f"{usage_key}:count")
            if request_count and int(request_count) > 1000:  # Configurable threshold
                return True
            
            # Check number of unique IPs
            unique_ips = await self.redis_client.scard(f"{usage_key}:ips")
            if unique_ips > 50:  # Suspicious if used from many IPs
                return True
            
            # Check for rate limit violations
            violations_key = f"rate_violations:{api_key_id}"
            violations = await self.redis_client.get(violations_key)
            if violations and int(violations) > 10:
                return True
            
            return False
            
        except Exception as e:
            logger.error("Error detecting API key abuse", error=str(e))
            return False
    
    async def detect_suspicious_login(self, user_id: Optional[str], tenant_id: Optional[str], 
                                    source_ip: str, user_agent: str, success: bool) -> bool:
        """Detect suspicious login patterns"""
        if not user_id:
            return False
        
        try:
            # Check login frequency
            current_time = int(time.time())
            login_key = f"login_attempts:{user_id}"
            
            await self.redis_client.zadd(login_key, {current_time: current_time})
            await self.redis_client.zremrangebyscore(login_key, 0, current_time - 3600)  # Last hour
            
            recent_attempts = await self.redis_client.zcard(login_key)
            if recent_attempts > 20:  # Too many login attempts
                return True
            
            # Check for login from new location
            if await self.is_new_location(user_id, source_ip):
                return True
            
            # Check for unusual time
            if await self.is_unusual_login_time(user_id):
                return True
            
            # Check for suspicious user agent
            if self.is_suspicious_user_agent(user_agent):
                return True
            
            # Check for concurrent logins from different locations
            if await self.has_concurrent_distant_logins(user_id, source_ip):
                return True
            
            return False
            
        except Exception as e:
            logger.error("Error detecting suspicious login", error=str(e))
            return False
    
    async def calculate_login_risk(self, user_id: Optional[str], tenant_id: Optional[str],
                                 source_ip: str, user_agent: str, device_info: Dict[str, Any],
                                 location: Optional[Dict[str, str]]) -> float:
        """Calculate risk score for login attempt"""
        if not user_id:
            return 0.5  # Medium risk for anonymous
        
        risk_score = 0.0
        
        try:
            # New location risk
            if await self.is_new_location(user_id, source_ip):
                risk_score += self.risk_weights['new_location']
            
            # New device risk
            device_fingerprint = self.generate_device_fingerprint(device_info)
            if await self.is_new_device(user_id, device_fingerprint):
                risk_score += self.risk_weights['new_device']
            
            # Off-hours login risk
            if await self.is_unusual_login_time(user_id):
                risk_score += self.risk_weights['off_hours']
            
            # Multiple recent failures risk
            if await self.has_recent_failures(user_id):
                risk_score += self.risk_weights['multiple_failures']
            
            # Unusual user agent risk
            if self.is_suspicious_user_agent(user_agent):
                risk_score += self.risk_weights['unusual_agent']
            
            return min(risk_score, 1.0)  # Cap at 1.0
            
        except Exception as e:
            logger.error("Error calculating login risk", error=str(e))
            return 0.5
    
    def risk_score_to_level(self, risk_score: float) -> RiskLevel:
        """Convert risk score to risk level"""
        if risk_score >= 0.8:
            return RiskLevel.CRITICAL
        elif risk_score >= 0.6:
            return RiskLevel.HIGH
        elif risk_score >= 0.4:
            return RiskLevel.MEDIUM
        elif risk_score >= 0.2:
            return RiskLevel.LOW
        else:
            return RiskLevel.VERY_LOW
    
    def extract_device_info(self, user_agent: str) -> Dict[str, Any]:
        """Extract device information from user agent"""
        # Simplified device detection - in production use proper library
        device_info = {
            'user_agent': user_agent,
            'os': 'unknown',
            'browser': 'unknown',
            'device_type': 'unknown'
        }
        
        user_agent_lower = user_agent.lower()
        
        # OS detection
        if 'windows' in user_agent_lower:
            device_info['os'] = 'Windows'
        elif 'mac' in user_agent_lower:
            device_info['os'] = 'macOS'
        elif 'linux' in user_agent_lower:
            device_info['os'] = 'Linux'
        elif 'android' in user_agent_lower:
            device_info['os'] = 'Android'
        elif 'ios' in user_agent_lower:
            device_info['os'] = 'iOS'
        
        # Browser detection
        if 'chrome' in user_agent_lower:
            device_info['browser'] = 'Chrome'
        elif 'firefox' in user_agent_lower:
            device_info['browser'] = 'Firefox'
        elif 'safari' in user_agent_lower:
            device_info['browser'] = 'Safari'
        elif 'edge' in user_agent_lower:
            device_info['browser'] = 'Edge'
        
        # Device type
        if 'mobile' in user_agent_lower:
            device_info['device_type'] = 'mobile'
        elif 'tablet' in user_agent_lower:
            device_info['device_type'] = 'tablet'
        else:
            device_info['device_type'] = 'desktop'
        
        return device_info
    
    def generate_device_fingerprint(self, device_info: Dict[str, Any]) -> str:
        """Generate device fingerprint from device info"""
        fingerprint_data = f"{device_info.get('os')}-{device_info.get('browser')}-{device_info.get('device_type')}"
        return hashlib.sha256(fingerprint_data.encode()).hexdigest()[:16]
    
    async def get_location_info(self, ip: str) -> Optional[Dict[str, str]]:
        """Get location information for IP address"""
        # Simplified geolocation - use proper service in production
        if ip in self.geo_cache:
            return self.geo_cache[ip]
        
        # For demo purposes, return mock data based on IP ranges
        location = {
            'country': 'US',
            'city': 'Unknown',
            'region': 'Unknown'
        }
        
        self.geo_cache[ip] = location
        return location
    
    async def is_new_location(self, user_id: str, source_ip: str) -> bool:
        """Check if login is from a new location"""
        try:
            async with self.db_pool.acquire() as conn:
                # Check if this IP range has been used before
                result = await conn.fetchval("""
                    SELECT EXISTS(
                        SELECT 1 FROM login_history 
                        WHERE user_id = $1 
                        AND source_ip = $2 
                        AND success = TRUE
                        AND timestamp > NOW() - INTERVAL '30 days'
                    )
                """, user_id, source_ip)
                
                return not result
                
        except Exception as e:
            logger.error("Error checking new location", error=str(e))
            return False
    
    async def is_new_device(self, user_id: str, device_fingerprint: str) -> bool:
        """Check if login is from a new device"""
        try:
            async with self.db_pool.acquire() as conn:
                result = await conn.fetchval("""
                    SELECT EXISTS(
                        SELECT 1 FROM user_sessions 
                        WHERE user_id = $1 
                        AND device_fingerprint = $2
                        AND created_at > NOW() - INTERVAL '30 days'
                    )
                """, user_id, device_fingerprint)
                
                return not result
                
        except Exception as e:
            logger.error("Error checking new device", error=str(e))
            return False
    
    async def is_unusual_login_time(self, user_id: str) -> bool:
        """Check if login time is unusual for user"""
        try:
            current_hour = datetime.utcnow().hour
            
            async with self.db_pool.acquire() as conn:
                # Get user's typical login hours
                profile = await conn.fetchrow("""
                    SELECT typical_login_hours FROM user_behavior_profiles 
                    WHERE user_id = $1
                """, user_id)
                
                if profile and profile['typical_login_hours']:
                    return current_hour not in profile['typical_login_hours']
                
                return False  # No profile means we can't determine unusual
                
        except Exception as e:
            logger.error("Error checking unusual login time", error=str(e))
            return False
    
    def is_suspicious_user_agent(self, user_agent: str) -> bool:
        """Check if user agent is suspicious"""
        user_agent_lower = user_agent.lower()
        
        suspicious_patterns = [
            'bot', 'crawler', 'spider', 'scan', 'automated',
            'script', 'curl', 'wget', 'python', 'test'
        ]
        
        return any(pattern in user_agent_lower for pattern in suspicious_patterns)
    
    async def has_concurrent_distant_logins(self, user_id: str, source_ip: str) -> bool:
        """Check for concurrent logins from geographically distant locations"""
        # Simplified implementation - would need proper geolocation in production
        user_sessions = [s for s in self.active_sessions.values() if s.user_id == user_id]
        
        for session in user_sessions:
            if session.source_ip != source_ip:
                # In production, calculate actual distance between IPs
                return True
        
        return False
    
    async def has_recent_failures(self, user_id: str) -> bool:
        """Check for recent login failures"""
        try:
            async with self.db_pool.acquire() as conn:
                failure_count = await conn.fetchval("""
                    SELECT COUNT(*) FROM login_history 
                    WHERE user_id = $1 
                    AND success = FALSE 
                    AND timestamp > NOW() - INTERVAL '1 hour'
                """, user_id)
                
                return failure_count > 3
                
        except Exception as e:
            logger.error("Error checking recent failures", error=str(e))
            return False
    
    async def store_access_event(self, event: AccessEvent):
        """Store access event in database"""
        try:
            async with self.db_pool.acquire() as conn:
                await conn.execute("""
                    INSERT INTO access_events 
                    (event_id, timestamp, event_type, risk_level, user_id, tenant_id,
                     session_id, source_ip, user_agent, location, device_info, success,
                     failure_reason, authentication_method, privileges, api_key_id,
                     service_name, endpoint, metadata)
                    VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19)
                """,
                    event.event_id, event.timestamp, event.event_type.value,
                    event.risk_level.value, event.user_id, event.tenant_id,
                    event.session_id, event.source_ip, event.user_agent,
                    json.dumps(event.location), json.dumps(event.device_info),
                    event.success, event.failure_reason, event.authentication_method,
                    event.privileges, event.api_key_id, event.service_name,
                    event.endpoint, json.dumps(event.metadata)
                )
                
        except Exception as e:
            logger.error("Error storing access event", error=str(e))
    
    async def store_session(self, session: UserSession):
        """Store user session in database"""
        try:
            async with self.db_pool.acquire() as conn:
                await conn.execute("""
                    INSERT INTO user_sessions 
                    (session_id, user_id, tenant_id, created_at, last_activity, 
                     source_ip, user_agent, device_fingerprint, is_active,
                     privileges, login_method, risk_score)
                    VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
                    ON CONFLICT (session_id) DO UPDATE SET
                        last_activity = EXCLUDED.last_activity,
                        is_active = EXCLUDED.is_active
                """,
                    session.session_id, session.user_id, session.tenant_id,
                    session.created_at, session.last_activity, session.source_ip,
                    session.user_agent, session.device_fingerprint, session.is_active,
                    session.privileges, session.login_method, session.risk_score
                )
                
        except Exception as e:
            logger.error("Error storing session", error=str(e))
    
    async def record_login_history(self, event: AccessEvent):
        """Record login attempt in history"""
        try:
            async with self.db_pool.acquire() as conn:
                await conn.execute("""
                    INSERT INTO login_history 
                    (user_id, tenant_id, timestamp, source_ip, user_agent,
                     success, failure_reason, location, device_info, risk_score)
                    VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
                """,
                    event.user_id, event.tenant_id, event.timestamp,
                    event.source_ip, event.user_agent, event.success,
                    event.failure_reason, json.dumps(event.location),
                    json.dumps(event.device_info), 
                    event.metadata.get('risk_score', 0.0)
                )
                
        except Exception as e:
            logger.error("Error recording login history", error=str(e))
    
    async def update_session_status(self, session_id: str, is_active: bool):
        """Update session status in database"""
        try:
            async with self.db_pool.acquire() as conn:
                await conn.execute("""
                    UPDATE user_sessions 
                    SET is_active = $2, last_activity = NOW()
                    WHERE session_id = $1
                """, session_id, is_active)
                
        except Exception as e:
            logger.error("Error updating session status", error=str(e))
    
    async def handle_excessive_sessions(self, user_id: str, sessions: List[UserSession]):
        """Handle user with too many concurrent sessions"""
        try:
            # Terminate oldest sessions
            sessions.sort(key=lambda s: s.last_activity)
            max_sessions = self.config.get('max_concurrent_sessions', 5)
            
            for session in sessions[:-max_sessions]:
                session.is_active = False
                await self.update_session_status(session.session_id, False)
                
                if session.session_id in self.active_sessions:
                    del self.active_sessions[session.session_id]
            
            logger.warning(
                "Terminated excessive sessions",
                user_id=user_id,
                terminated_count=len(sessions) - max_sessions
            )
            
        except Exception as e:
            logger.error("Error handling excessive sessions", error=str(e))
    
    async def record_rate_limit_violation(self, api_key_id: str, source_ip: str):
        """Record API key rate limit violation"""
        try:
            violations_key = f"rate_violations:{api_key_id}"
            await self.redis_client.incr(violations_key)
            await self.redis_client.expire(violations_key, 3600)
            
            logger.warning(
                "API key rate limit violation",
                api_key_id=api_key_id,
                source_ip=source_ip
            )
            
        except Exception as e:
            logger.error("Error recording rate limit violation", error=str(e))
    
    async def cleanup_expired_sessions(self):
        """Clean up expired sessions (run periodically)"""
        try:
            current_time = datetime.utcnow()
            expired_sessions = []
            
            for session_id, session in list(self.active_sessions.items()):
                # Check for session timeout (e.g., 24 hours of inactivity)
                if (current_time - session.last_activity).total_seconds() > 86400:
                    expired_sessions.append(session_id)
            
            for session_id in expired_sessions:
                session = self.active_sessions[session_id]
                session.is_active = False
                await self.update_session_status(session_id, False)
                del self.active_sessions[session_id]
            
            logger.info(f"Cleaned up {len(expired_sessions)} expired sessions")
            
        except Exception as e:
            logger.error("Error cleaning up expired sessions", error=str(e))
    
    async def close(self):
        """Clean up resources"""
        if self.db_pool:
            await self.db_pool.close()
        if self.redis_client:
            await self.redis_client.close()

# Main monitoring function
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
        'max_concurrent_sessions': 5
    }
    
    monitor = AccessControlMonitor(config)
    await monitor.initialize()
    
    logger.info("Access control monitor started successfully")
    
    try:
        # Main monitoring loop
        while True:
            await monitor.cleanup_expired_sessions()
            await asyncio.sleep(300)  # Check every 5 minutes
            
    except KeyboardInterrupt:
        logger.info("Shutting down access control monitor")
    finally:
        await monitor.close()

if __name__ == "__main__":
    asyncio.run(main())