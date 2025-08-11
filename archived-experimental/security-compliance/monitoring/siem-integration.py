#!/usr/bin/env python3
"""
Security Information and Event Management (SIEM) Integration

Comprehensive SIEM system for centralized security monitoring, threat detection,
incident response, and compliance reporting.
"""

import os
import json
import yaml
import logging
import datetime
import asyncio
import aiohttp
import hashlib
import uuid
from typing import Dict, List, Any, Optional, Union, Callable
from pathlib import Path
from dataclasses import dataclass, asdict
from enum import Enum
import sqlite3
import pandas as pd
import numpy as np
from elasticsearch import AsyncElasticsearch
import redis.asyncio as redis
from cryptography.fernet import Fernet
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/siem-integration.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class EventSeverity(Enum):
    CRITICAL = "critical"
    HIGH = "high"
    MEDIUM = "medium"
    LOW = "low"
    INFO = "info"

class EventCategory(Enum):
    AUTHENTICATION = "authentication"
    AUTHORIZATION = "authorization"
    DATA_ACCESS = "data_access"
    SYSTEM_ACTIVITY = "system_activity"
    NETWORK_ACTIVITY = "network_activity"
    MALWARE = "malware"
    INTRUSION = "intrusion"
    POLICY_VIOLATION = "policy_violation"
    VULNERABILITY = "vulnerability"
    COMPLIANCE = "compliance"

class AlertStatus(Enum):
    OPEN = "open"
    INVESTIGATING = "investigating"
    RESOLVED = "resolved"
    FALSE_POSITIVE = "false_positive"
    ESCALATED = "escalated"

class ThreatLevel(Enum):
    UNKNOWN = 0
    LOW = 1
    MEDIUM = 2
    HIGH = 3
    CRITICAL = 4

@dataclass
class SecurityEvent:
    """Security event record"""
    event_id: str
    timestamp: datetime.datetime
    source: str
    category: EventCategory
    severity: EventSeverity
    title: str
    description: str
    raw_data: Dict[str, Any]
    source_ip: Optional[str] = None
    destination_ip: Optional[str] = None
    user_id: Optional[str] = None
    username: Optional[str] = None
    asset_id: Optional[str] = None
    tags: List[str] = None
    threat_level: ThreatLevel = ThreatLevel.UNKNOWN

@dataclass
class SecurityAlert:
    """Security alert record"""
    alert_id: str
    event_ids: List[str]
    rule_name: str
    severity: EventSeverity
    status: AlertStatus
    created_at: datetime.datetime
    updated_at: datetime.datetime
    assigned_to: Optional[str] = None
    resolution_notes: Optional[str] = None
    false_positive_reason: Optional[str] = None

@dataclass
class ThreatIntelligence:
    """Threat intelligence indicator"""
    indicator_id: str
    indicator_type: str  # ip, domain, hash, etc.
    indicator_value: str
    threat_type: str
    confidence: float
    first_seen: datetime.datetime
    last_seen: datetime.datetime
    source: str
    tags: List[str]

class SIEMIntegration:
    """Main SIEM integration system"""
    
    def __init__(self, config_path: str = "siem-config.yaml"):
        self.config = self._load_config(config_path)
        self.db_path = self.config.get('database_path', 'siem.db')
        self.es_client = None
        self.redis_client = None
        self.detection_rules = []
        self.threat_intel_indicators = {}
        self._init_database()
        self._load_detection_rules()
        
    def _load_config(self, config_path: str) -> Dict[str, Any]:
        """Load SIEM configuration"""
        try:
            with open(config_path, 'r') as f:
                return yaml.safe_load(f)
        except FileNotFoundError:
            logger.warning(f"Config file {config_path} not found, using defaults")
            return self._default_config()
    
    def _default_config(self) -> Dict[str, Any]:
        """Default SIEM configuration"""
        return {
            'elasticsearch': {
                'enabled': True,
                'hosts': ['http://elasticsearch:9200'],
                'index_prefix': 'security-events'
            },
            'redis': {
                'enabled': True,
                'host': 'redis',
                'port': 6379,
                'db': 0
            },
            'alerting': {
                'email_enabled': True,
                'smtp_server': 'localhost',
                'smtp_port': 587,
                'from_email': 'siem@pyairtable.com',
                'alert_recipients': ['security@pyairtable.com']
            },
            'threat_intel': {
                'enabled': True,
                'sources': ['misp', 'otx', 'virustotal'],
                'update_interval_hours': 6
            },
            'retention': {
                'events_days': 365,
                'alerts_days': 2555,  # 7 years
                'logs_days': 90
            },
            'detection': {
                'enabled': True,
                'rules_path': 'detection-rules/',
                'custom_rules_enabled': True
            }
        }
    
    def _init_database(self):
        """Initialize SIEM database"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        # Security events table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS security_events (
                event_id TEXT PRIMARY KEY,
                timestamp TEXT NOT NULL,
                source TEXT NOT NULL,
                category TEXT NOT NULL,
                severity TEXT NOT NULL,
                title TEXT NOT NULL,
                description TEXT NOT NULL,
                raw_data TEXT NOT NULL,
                source_ip TEXT,
                destination_ip TEXT,
                user_id TEXT,
                username TEXT,
                asset_id TEXT,
                tags TEXT,
                threat_level INTEGER DEFAULT 0,
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP
            )
        ''')
        
        # Security alerts table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS security_alerts (
                alert_id TEXT PRIMARY KEY,
                event_ids TEXT NOT NULL,
                rule_name TEXT NOT NULL,
                severity TEXT NOT NULL,
                status TEXT NOT NULL DEFAULT 'open',
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                assigned_to TEXT,
                resolution_notes TEXT,
                false_positive_reason TEXT
            )
        ''')
        
        # Threat intelligence table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS threat_intelligence (
                indicator_id TEXT PRIMARY KEY,
                indicator_type TEXT NOT NULL,
                indicator_value TEXT NOT NULL,
                threat_type TEXT NOT NULL,
                confidence REAL NOT NULL,
                first_seen TEXT NOT NULL,
                last_seen TEXT NOT NULL,
                source TEXT NOT NULL,
                tags TEXT,
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP
            )
        ''')
        
        # Detection rules table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS detection_rules (
                rule_id TEXT PRIMARY KEY,
                rule_name TEXT NOT NULL,
                rule_description TEXT,
                rule_logic TEXT NOT NULL,
                severity TEXT NOT NULL,
                enabled BOOLEAN DEFAULT TRUE,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                author TEXT,
                tags TEXT
            )
        ''')
        
        conn.commit()
        conn.close()
    
    async def initialize_connections(self):
        """Initialize external service connections"""
        try:
            # Initialize Elasticsearch connection
            if self.config.get('elasticsearch', {}).get('enabled', False):
                es_config = self.config['elasticsearch']
                self.es_client = AsyncElasticsearch(
                    hosts=es_config.get('hosts', ['http://localhost:9200'])
                )
                
                # Test connection
                if await self.es_client.ping():
                    logger.info("Elasticsearch connection established")
                else:
                    logger.error("Failed to connect to Elasticsearch")
            
            # Initialize Redis connection
            if self.config.get('redis', {}).get('enabled', False):
                redis_config = self.config['redis']
                self.redis_client = redis.Redis(
                    host=redis_config.get('host', 'localhost'),
                    port=redis_config.get('port', 6379),
                    db=redis_config.get('db', 0),
                    decode_responses=True
                )
                
                # Test connection
                if await self.redis_client.ping():
                    logger.info("Redis connection established")
                else:
                    logger.error("Failed to connect to Redis")
            
        except Exception as e:
            logger.error(f"Failed to initialize connections: {e}")
    
    def _load_detection_rules(self):
        """Load detection rules from configuration"""
        rules = [
            {
                'rule_id': 'failed_login_brute_force',
                'rule_name': 'Failed Login Brute Force',
                'description': 'Detect multiple failed login attempts from same IP',
                'logic': 'count(failed_login) > 5 in 5 minutes',
                'severity': EventSeverity.HIGH,
                'condition': self._check_brute_force_login
            },
            {
                'rule_id': 'privilege_escalation',
                'rule_name': 'Privilege Escalation Attempt',
                'description': 'Detect unauthorized privilege escalation attempts',
                'logic': 'unauthorized access to admin functions',
                'severity': EventSeverity.CRITICAL,
                'condition': self._check_privilege_escalation
            },
            {
                'rule_id': 'data_exfiltration',
                'rule_name': 'Potential Data Exfiltration',
                'description': 'Detect large data downloads or exports',
                'logic': 'data_volume > threshold in time window',
                'severity': EventSeverity.HIGH,
                'condition': self._check_data_exfiltration
            },
            {
                'rule_id': 'suspicious_network_activity',
                'rule_name': 'Suspicious Network Activity',
                'description': 'Detect connections to known malicious IPs',
                'logic': 'connection to threat intel IPs',
                'severity': EventSeverity.MEDIUM,
                'condition': self._check_suspicious_network
            }
        ]
        
        self.detection_rules = rules
        logger.info(f"Loaded {len(rules)} detection rules")
    
    async def ingest_event(self, event: SecurityEvent) -> str:
        """Ingest security event into SIEM"""
        try:
            # Store in database
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            
            cursor.execute('''
                INSERT INTO security_events (
                    event_id, timestamp, source, category, severity,
                    title, description, raw_data, source_ip, destination_ip,
                    user_id, username, asset_id, tags, threat_level
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ''', (
                event.event_id,
                event.timestamp.isoformat(),
                event.source,
                event.category.value,
                event.severity.value,
                event.title,
                event.description,
                json.dumps(event.raw_data),
                event.source_ip,
                event.destination_ip,
                event.user_id,
                event.username,
                event.asset_id,
                json.dumps(event.tags) if event.tags else None,
                event.threat_level.value
            ))
            
            conn.commit()
            conn.close()
            
            # Store in Elasticsearch if enabled
            if self.es_client:
                await self._index_event_elasticsearch(event)
            
            # Cache in Redis if enabled
            if self.redis_client:
                await self._cache_event_redis(event)
            
            # Run detection rules
            await self._run_detection_rules(event)
            
            # Check threat intelligence
            await self._check_threat_intelligence(event)
            
            logger.debug(f"Event ingested: {event.event_id}")
            return event.event_id
            
        except Exception as e:
            logger.error(f"Failed to ingest event {event.event_id}: {e}")
            raise
    
    async def _index_event_elasticsearch(self, event: SecurityEvent):
        """Index event in Elasticsearch"""
        try:
            index_name = f"{self.config['elasticsearch']['index_prefix']}-{event.timestamp.strftime('%Y-%m')}"
            
            doc = {
                'event_id': event.event_id,
                'timestamp': event.timestamp.isoformat(),
                'source': event.source,
                'category': event.category.value,
                'severity': event.severity.value,
                'title': event.title,
                'description': event.description,
                'source_ip': event.source_ip,
                'destination_ip': event.destination_ip,
                'user_id': event.user_id,
                'username': event.username,
                'asset_id': event.asset_id,
                'tags': event.tags,
                'threat_level': event.threat_level.value,
                'raw_data': event.raw_data
            }
            
            await self.es_client.index(
                index=index_name,
                id=event.event_id,
                document=doc
            )
            
        except Exception as e:
            logger.error(f"Failed to index event in Elasticsearch: {e}")
    
    async def _cache_event_redis(self, event: SecurityEvent):
        """Cache event in Redis for real-time analysis"""
        try:
            # Cache recent events by source IP for correlation
            if event.source_ip:
                key = f"events:ip:{event.source_ip}"
                await self.redis_client.lpush(key, event.event_id)
                await self.redis_client.expire(key, 3600)  # 1 hour TTL
            
            # Cache recent events by user for correlation
            if event.user_id:
                key = f"events:user:{event.user_id}"
                await self.redis_client.lpush(key, event.event_id)
                await self.redis_client.expire(key, 3600)  # 1 hour TTL
            
        except Exception as e:
            logger.error(f"Failed to cache event in Redis: {e}")
    
    async def _run_detection_rules(self, event: SecurityEvent):
        """Run detection rules against the event"""
        try:
            for rule in self.detection_rules:
                if await rule['condition'](event):
                    await self._create_alert(
                        event_ids=[event.event_id],
                        rule_name=rule['rule_name'],
                        severity=rule['severity']
                    )
                    
        except Exception as e:
            logger.error(f"Failed to run detection rules: {e}")
    
    async def _check_brute_force_login(self, event: SecurityEvent) -> bool:
        """Check for brute force login attempts"""
        if event.category != EventCategory.AUTHENTICATION or not event.source_ip:
            return False
        
        try:
            # Get recent failed login attempts from same IP
            if self.redis_client:
                key = f"failed_logins:ip:{event.source_ip}"
                count = await self.redis_client.incr(key)
                await self.redis_client.expire(key, 300)  # 5 minutes
                
                return count > 5
            else:
                # Fallback to database query
                conn = sqlite3.connect(self.db_path)
                cursor = conn.cursor()
                
                five_minutes_ago = (datetime.datetime.utcnow() - datetime.timedelta(minutes=5)).isoformat()
                
                cursor.execute('''
                    SELECT COUNT(*) FROM security_events 
                    WHERE source_ip = ? AND category = 'authentication' 
                    AND severity IN ('medium', 'high', 'critical')
                    AND timestamp > ?
                ''', (event.source_ip, five_minutes_ago))
                
                count = cursor.fetchone()[0]
                conn.close()
                
                return count > 5
                
        except Exception as e:
            logger.error(f"Failed to check brute force login: {e}")
            return False
    
    async def _check_privilege_escalation(self, event: SecurityEvent) -> bool:
        """Check for privilege escalation attempts"""
        if event.category != EventCategory.AUTHORIZATION:
            return False
        
        try:
            # Look for patterns indicating privilege escalation
            suspicious_patterns = [
                'admin', 'root', 'sudo', 'escalate', 'privilege',
                'unauthorized', 'forbidden', 'access denied'
            ]
            
            event_text = f"{event.title} {event.description}".lower()
            
            for pattern in suspicious_patterns:
                if pattern in event_text:
                    return True
            
            return False
            
        except Exception as e:
            logger.error(f"Failed to check privilege escalation: {e}")
            return False
    
    async def _check_data_exfiltration(self, event: SecurityEvent) -> bool:
        """Check for potential data exfiltration"""
        if event.category != EventCategory.DATA_ACCESS:
            return False
        
        try:
            # Check for large data volumes or suspicious patterns
            raw_data = event.raw_data
            
            # Look for indicators of data exfiltration
            if 'bytes_transferred' in raw_data:
                bytes_transferred = raw_data['bytes_transferred']
                if bytes_transferred > 100 * 1024 * 1024:  # 100MB
                    return True
            
            if 'records_accessed' in raw_data:
                records_accessed = raw_data['records_accessed']
                if records_accessed > 10000:  # 10k records
                    return True
            
            return False
            
        except Exception as e:
            logger.error(f"Failed to check data exfiltration: {e}")
            return False
    
    async def _check_suspicious_network(self, event: SecurityEvent) -> bool:
        """Check for suspicious network activity"""
        if event.category != EventCategory.NETWORK_ACTIVITY:
            return False
        
        try:
            # Check against threat intelligence indicators
            if event.destination_ip and event.destination_ip in self.threat_intel_indicators:
                return True
            
            if event.source_ip and event.source_ip in self.threat_intel_indicators:
                return True
            
            return False
            
        except Exception as e:
            logger.error(f"Failed to check suspicious network activity: {e}")
            return False
    
    async def _check_threat_intelligence(self, event: SecurityEvent):
        """Check event against threat intelligence indicators"""
        try:
            indicators_to_check = []
            
            if event.source_ip:
                indicators_to_check.append(('ip', event.source_ip))
            if event.destination_ip:
                indicators_to_check.append(('ip', event.destination_ip))
            
            # Check for domain indicators in raw data
            if 'domain' in event.raw_data:
                indicators_to_check.append(('domain', event.raw_data['domain']))
            
            for indicator_type, indicator_value in indicators_to_check:
                if self._is_malicious_indicator(indicator_type, indicator_value):
                    # Enhance event with threat intelligence
                    event.threat_level = ThreatLevel.HIGH
                    event.tags = event.tags or []
                    event.tags.append('threat_intel_match')
                    
                    # Create high-priority alert
                    await self._create_alert(
                        event_ids=[event.event_id],
                        rule_name="Threat Intelligence Match",
                        severity=EventSeverity.HIGH
                    )
                    
        except Exception as e:
            logger.error(f"Failed to check threat intelligence: {e}")
    
    def _is_malicious_indicator(self, indicator_type: str, indicator_value: str) -> bool:
        """Check if indicator is known to be malicious"""
        # This would typically query threat intelligence feeds
        # For demo purposes, using a simple check
        malicious_ips = ['192.168.1.100', '10.0.0.100']  # Example malicious IPs
        malicious_domains = ['malicious.com', 'badsite.org']  # Example malicious domains
        
        if indicator_type == 'ip' and indicator_value in malicious_ips:
            return True
        if indicator_type == 'domain' and indicator_value in malicious_domains:
            return True
        
        return False
    
    async def _create_alert(self, event_ids: List[str], rule_name: str, 
                          severity: EventSeverity) -> str:
        """Create security alert"""
        try:
            alert_id = str(uuid.uuid4())
            now = datetime.datetime.utcnow()
            
            alert = SecurityAlert(
                alert_id=alert_id,
                event_ids=event_ids,
                rule_name=rule_name,
                severity=severity,
                status=AlertStatus.OPEN,
                created_at=now,
                updated_at=now
            )
            
            # Store in database
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            
            cursor.execute('''
                INSERT INTO security_alerts (
                    alert_id, event_ids, rule_name, severity,
                    status, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
            ''', (
                alert.alert_id,
                json.dumps(alert.event_ids),
                alert.rule_name,
                alert.severity.value,
                alert.status.value,
                alert.created_at.isoformat(),
                alert.updated_at.isoformat()
            ))
            
            conn.commit()
            conn.close()
            
            # Send notification
            await self._send_alert_notification(alert)
            
            logger.info(f"Alert created: {alert_id} - {rule_name}")
            return alert_id
            
        except Exception as e:
            logger.error(f"Failed to create alert: {e}")
            raise
    
    async def _send_alert_notification(self, alert: SecurityAlert):
        """Send alert notification"""
        try:
            if not self.config.get('alerting', {}).get('email_enabled', False):
                return
            
            email_config = self.config['alerting']
            
            # Create email message
            msg = MIMEMultipart()
            msg['From'] = email_config['from_email']
            msg['To'] = ', '.join(email_config['alert_recipients'])
            msg['Subject'] = f"Security Alert: {alert.rule_name} [{alert.severity.value.upper()}]"
            
            # Email body
            body = f"""
Security Alert Details:

Alert ID: {alert.alert_id}
Rule: {alert.rule_name}
Severity: {alert.severity.value.upper()}
Status: {alert.status.value}
Created: {alert.created_at.isoformat()}
Event IDs: {', '.join(alert.event_ids)}

Please investigate this alert immediately.

PyAirtable Security Team
            """
            
            msg.attach(MIMEText(body, 'plain'))
            
            # Send email
            server = smtplib.SMTP(email_config['smtp_server'], email_config['smtp_port'])
            server.starttls()
            text = msg.as_string()
            server.sendmail(email_config['from_email'], email_config['alert_recipients'], text)
            server.quit()
            
            logger.info(f"Alert notification sent for {alert.alert_id}")
            
        except Exception as e:
            logger.error(f"Failed to send alert notification: {e}")
    
    async def generate_security_dashboard(self, 
                                        start_date: datetime.datetime,
                                        end_date: datetime.datetime) -> Dict[str, Any]:
        """Generate security dashboard data"""
        try:
            conn = sqlite3.connect(self.db_path)
            
            # Get events in date range
            events_df = pd.read_sql_query('''
                SELECT * FROM security_events 
                WHERE timestamp BETWEEN ? AND ?
            ''', conn, params=[start_date.isoformat(), end_date.isoformat()])
            
            # Get alerts in date range
            alerts_df = pd.read_sql_query('''
                SELECT * FROM security_alerts 
                WHERE created_at BETWEEN ? AND ?
            ''', conn, params=[start_date.isoformat(), end_date.isoformat()])
            
            conn.close()
            
            dashboard = {
                "dashboard_period": {
                    "start": start_date.isoformat(),
                    "end": end_date.isoformat()
                },
                "event_summary": {
                    "total_events": len(events_df),
                    "events_by_severity": events_df['severity'].value_counts().to_dict() if len(events_df) > 0 else {},
                    "events_by_category": events_df['category'].value_counts().to_dict() if len(events_df) > 0 else {},
                    "events_by_source": events_df['source'].value_counts().head(10).to_dict() if len(events_df) > 0 else {}
                },
                "alert_summary": {
                    "total_alerts": len(alerts_df),
                    "open_alerts": len(alerts_df[alerts_df['status'] == 'open']),
                    "resolved_alerts": len(alerts_df[alerts_df['status'] == 'resolved']),
                    "alerts_by_severity": alerts_df['severity'].value_counts().to_dict() if len(alerts_df) > 0 else {},
                    "top_alert_rules": alerts_df['rule_name'].value_counts().head(10).to_dict() if len(alerts_df) > 0 else {}
                },
                "threat_intelligence": {
                    "indicators_count": len(self.threat_intel_indicators),
                    "high_confidence_indicators": len([i for i in self.threat_intel_indicators.values() if i.get('confidence', 0) > 0.8]),
                    "recent_matches": self._count_recent_threat_matches(events_df)
                },
                "security_metrics": self._calculate_security_metrics(events_df, alerts_df)
            }
            
            return dashboard
            
        except Exception as e:
            logger.error(f"Failed to generate security dashboard: {e}")
            raise

async def main():
    """Main execution function for testing"""
    siem = SIEMIntegration()
    await siem.initialize_connections()
    
    # Example: Create and ingest a security event
    event = SecurityEvent(
        event_id=str(uuid.uuid4()),
        timestamp=datetime.datetime.utcnow(),
        source="web_application",
        category=EventCategory.AUTHENTICATION,
        severity=EventSeverity.MEDIUM,
        title="Failed Login Attempt",
        description="User failed to authenticate",
        raw_data={"username": "testuser", "ip": "192.168.1.100"},
        source_ip="192.168.1.100",
        username="testuser"
    )
    
    try:
        event_id = await siem.ingest_event(event)
        print(f"Event ingested: {event_id}")
    except Exception as e:
        print(f"Event ingestion failed: {e}")
    
    # Example: Generate security dashboard
    try:
        end_date = datetime.datetime.utcnow()
        start_date = end_date - datetime.timedelta(days=7)
        
        dashboard = await siem.generate_security_dashboard(start_date, end_date)
        print("\nSecurity Dashboard Summary:")
        print(f"Total events: {dashboard['event_summary']['total_events']}")
        print(f"Total alerts: {dashboard['alert_summary']['total_alerts']}")
        print(f"Open alerts: {dashboard['alert_summary']['open_alerts']}")
    except Exception as e:
        print(f"Dashboard generation failed: {e}")

if __name__ == "__main__":
    asyncio.run(main())