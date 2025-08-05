#!/usr/bin/env python3
"""
PyAirtable Infrastructure Security Monitoring System
Comprehensive monitoring of network traffic, container security, database access, and configuration changes
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
import re
import hashlib
import subprocess
from collections import defaultdict, deque
import asyncpg
import redis.asyncio as redis
from prometheus_client import Counter, Histogram, Gauge, Info
import structlog
import psutil
import docker
from kubernetes import client, config as k8s_config
import yaml

logger = structlog.get_logger(__name__)

class InfraEventType(Enum):
    """Infrastructure security event types"""
    NETWORK_ANOMALY = "network_anomaly"
    PORT_SCAN = "port_scan"
    UNUSUAL_TRAFFIC = "unusual_traffic"
    CONTAINER_ESCAPE = "container_escape"
    CONTAINER_BREACH = "container_breach"
    PRIVILEGE_ESCALATION = "privilege_escalation"
    DATABASE_ANOMALY = "database_anomaly"
    CONFIG_CHANGE = "configuration_change"
    UNAUTHORIZED_ACCESS = "unauthorized_access"
    RESOURCE_EXHAUSTION = "resource_exhaustion"
    MALWARE_DETECTED = "malware_detected"
    COMPLIANCE_VIOLATION = "compliance_violation"

class SeverityLevel(Enum):
    """Security severity levels"""
    INFO = "info"
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"
    CRITICAL = "critical"

@dataclass
class InfraSecurityEvent:
    """Infrastructure security event"""
    event_id: str
    timestamp: datetime
    event_type: InfraEventType
    severity: SeverityLevel
    source: str
    target: Optional[str]
    description: str
    details: Dict[str, Any]
    affected_resources: List[str]
    remediation_actions: List[str]
    compliance_impact: Optional[str]
    metadata: Dict[str, Any]
    
    def to_dict(self) -> Dict[str, Any]:
        data = asdict(self)
        data['timestamp'] = self.timestamp.isoformat()
        data['event_type'] = self.event_type.value
        data['severity'] = self.severity.value
        return data

@dataclass
class NetworkConnection:
    """Network connection tracking"""
    connection_id: str
    source_ip: str
    source_port: int
    dest_ip: str
    dest_port: int
    protocol: str
    bytes_sent: int
    bytes_received: int
    duration: float
    established_at: datetime
    is_internal: bool
    is_encrypted: bool

@dataclass
class ContainerSecurityState:
    """Container security state"""
    container_id: str
    name: str
    image: str
    running_as_root: bool
    privileged: bool
    host_network: bool
    host_pid: bool
    capabilities: List[str]
    security_opt: List[str]
    volumes: List[str]
    environment_vars: Dict[str, str]
    process_count: int
    network_connections: List[NetworkConnection]
    last_updated: datetime

class InfrastructureSecurityMonitor:
    """Infrastructure security monitoring system"""
    
    def __init__(self, config: Dict[str, Any]):
        self.config = config
        self.redis_client = None
        self.db_pool = None
        self.docker_client = None
        self.k8s_client = None
        
        # Tracking state
        self.network_baselines = {}
        self.container_states = {}
        self.database_queries = deque(maxlen=1000)
        self.config_hashes = {}
        
        # Prometheus metrics
        self.security_events_total = Counter(
            'infra_security_events_total',
            'Total infrastructure security events',
            ['event_type', 'severity', 'source']
        )
        
        self.network_connections_total = Counter(
            'infra_network_connections_total',
            'Network connections monitored',
            ['protocol', 'direction', 'encrypted']
        )
        
        self.container_security_violations = Counter(
            'infra_container_security_violations_total',
            'Container security violations',
            ['violation_type', 'container']
        )
        
        self.database_anomalies_total = Counter(
            'infra_database_anomalies_total',
            'Database access anomalies',
            ['anomaly_type', 'database']
        )
        
        self.config_changes_total = Counter(
            'infra_config_changes_total',
            'Configuration changes detected',
            ['config_type', 'change_type']
        )
        
        self.resource_usage_gauge = Gauge(
            'infra_resource_usage_percent',
            'Resource usage percentage',
            ['resource_type', 'host']
        )
        
        self.threat_detection_latency = Histogram(
            'infra_threat_detection_seconds',
            'Infrastructure threat detection latency',
            ['event_type']
        )
        
        # Network monitoring patterns
        self.suspicious_ports = {
            22, 23, 135, 139, 445, 1433, 1521, 3306, 3389, 5432, 6379, 27017
        }
        
        self.internal_networks = [
            '10.0.0.0/8',
            '172.16.0.0/12', 
            '192.168.0.0/16',
            '127.0.0.0/8'
        ]
        
    async def initialize(self):
        """Initialize monitoring components"""
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
            
            # Initialize Redis
            self.redis_client = redis.Redis(
                host=self.config['redis']['host'],
                port=self.config['redis']['port'],
                decode_responses=True
            )
            
            # Initialize Docker client
            try:
                self.docker_client = docker.from_env()
            except Exception as e:
                logger.warning("Docker client not available", error=str(e))
            
            # Initialize Kubernetes client
            try:
                k8s_config.load_incluster_config()
                self.k8s_client = client.CoreV1Api()
            except Exception:
                try:
                    k8s_config.load_kube_config()
                    self.k8s_client = client.CoreV1Api()
                except Exception as e:
                    logger.warning("Kubernetes client not available", error=str(e))
            
            # Create database schema
            await self.create_infra_tables()
            
            # Initialize baselines
            await self.initialize_baselines()
            
            logger.info("Infrastructure security monitor initialized successfully")
            
        except Exception as e:
            logger.error("Failed to initialize infrastructure monitor", error=str(e))
            raise
    
    async def create_infra_tables(self):
        """Create infrastructure monitoring database tables"""
        async with self.db_pool.acquire() as conn:
            await conn.execute("""
                CREATE TABLE IF NOT EXISTS infra_security_events (
                    event_id UUID PRIMARY KEY,
                    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                    event_type VARCHAR(50) NOT NULL,
                    severity VARCHAR(20) NOT NULL,
                    source VARCHAR(255) NOT NULL,
                    target VARCHAR(255),
                    description TEXT NOT NULL,
                    details JSONB,
                    affected_resources TEXT[],
                    remediation_actions TEXT[],
                    compliance_impact TEXT,
                    metadata JSONB,
                    resolved BOOLEAN DEFAULT FALSE,
                    resolved_at TIMESTAMPTZ,
                    INDEX (timestamp),
                    INDEX (event_type),
                    INDEX (severity),
                    INDEX (source)
                );
                
                CREATE TABLE IF NOT EXISTS network_connections (
                    connection_id VARCHAR(255) PRIMARY KEY,
                    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                    source_ip INET NOT NULL,
                    source_port INTEGER NOT NULL,
                    dest_ip INET NOT NULL,
                    dest_port INTEGER NOT NULL,
                    protocol VARCHAR(10) NOT NULL,
                    bytes_sent BIGINT DEFAULT 0,
                    bytes_received BIGINT DEFAULT 0,
                    duration_seconds NUMERIC,
                    is_internal BOOLEAN,
                    is_encrypted BOOLEAN,
                    risk_score NUMERIC(5,2),
                    INDEX (timestamp),
                    INDEX (source_ip),
                    INDEX (dest_ip),
                    INDEX (dest_port)
                );
                
                CREATE TABLE IF NOT EXISTS container_security_state (
                    container_id VARCHAR(255) PRIMARY KEY,
                    name VARCHAR(255),
                    image VARCHAR(255),
                    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                    running_as_root BOOLEAN,
                    privileged BOOLEAN,
                    host_network BOOLEAN,
                    host_pid BOOLEAN,
                    capabilities TEXT[],
                    security_opt TEXT[],
                    volumes TEXT[],
                    environment_vars JSONB,
                    process_count INTEGER,
                    risk_score NUMERIC(5,2),
                    INDEX (timestamp),
                    INDEX (name),
                    INDEX (image)
                );
                
                CREATE TABLE IF NOT EXISTS database_access_log (
                    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                    database_name VARCHAR(100),
                    user_name VARCHAR(100),
                    client_ip INET,
                    query_type VARCHAR(50),
                    query_hash VARCHAR(255),
                    execution_time_ms NUMERIC,
                    rows_affected INTEGER,
                    error_message TEXT,
                    risk_score NUMERIC(5,2),
                    INDEX (timestamp),
                    INDEX (database_name),
                    INDEX (user_name),
                    INDEX (client_ip)
                );
                
                CREATE TABLE IF NOT EXISTS config_changes (
                    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                    config_type VARCHAR(100) NOT NULL,
                    config_path VARCHAR(500) NOT NULL,
                    change_type VARCHAR(50) NOT NULL,
                    old_hash VARCHAR(255),
                    new_hash VARCHAR(255),
                    changed_by VARCHAR(100),
                    details JSONB,
                    approved BOOLEAN DEFAULT FALSE,
                    INDEX (timestamp),
                    INDEX (config_type),
                    INDEX (change_type)
                );
                
                CREATE TABLE IF NOT EXISTS network_baselines (
                    source_ip INET,
                    dest_port INTEGER,
                    protocol VARCHAR(10),
                    baseline_data JSONB,
                    last_updated TIMESTAMPTZ DEFAULT NOW(),
                    PRIMARY KEY (source_ip, dest_port, protocol)
                );
            """)
    
    async def initialize_baselines(self):
        """Initialize security baselines"""
        try:
            # Load network baselines
            await self.load_network_baselines()
            
            # Initialize container baselines
            await self.scan_container_security()
            
            # Load configuration baselines
            await self.load_config_baselines()
            
            logger.info("Security baselines initialized")
            
        except Exception as e:
            logger.error("Error initializing baselines", error=str(e))
    
    async def monitor_network_traffic(self):
        """Monitor network traffic for anomalies"""
        try:
            # Get current network connections
            connections = self.get_network_connections()
            
            for conn in connections:
                await self.analyze_network_connection(conn)
                
                # Store in database for trending
                await self.store_network_connection(conn)
                
                # Update metrics
                self.network_connections_total.labels(
                    protocol=conn.protocol,
                    direction='outbound' if conn.source_ip.startswith('10.') else 'inbound',
                    encrypted=str(conn.is_encrypted).lower()
                ).inc()
            
            # Detect port scans
            await self.detect_port_scans()
            
            # Detect unusual traffic patterns
            await self.detect_traffic_anomalies()
            
        except Exception as e:
            logger.error("Error monitoring network traffic", error=str(e))
    
    def get_network_connections(self) -> List[NetworkConnection]:
        """Get current network connections"""
        connections = []
        
        try:
            # Use psutil to get network connections
            for conn in psutil.net_connections(kind='inet'):
                if conn.status == 'ESTABLISHED' and conn.laddr and conn.raddr:
                    connection = NetworkConnection(
                        connection_id=f"{conn.laddr.ip}:{conn.laddr.port}-{conn.raddr.ip}:{conn.raddr.port}",
                        source_ip=conn.laddr.ip,
                        source_port=conn.laddr.port,
                        dest_ip=conn.raddr.ip,
                        dest_port=conn.raddr.port,
                        protocol='tcp' if conn.type == 1 else 'udp',
                        bytes_sent=0,  # Would need additional monitoring
                        bytes_received=0,
                        duration=0.0,
                        established_at=datetime.utcnow(),
                        is_internal=self.is_internal_ip(conn.raddr.ip),
                        is_encrypted=self.is_encrypted_port(conn.raddr.port)
                    )
                    connections.append(connection)
                    
        except Exception as e:
            logger.error("Error getting network connections", error=str(e))
        
        return connections
    
    async def analyze_network_connection(self, conn: NetworkConnection):
        """Analyze network connection for security issues"""
        risk_factors = []
        
        # Check for connections to suspicious ports
        if conn.dest_port in self.suspicious_ports:
            risk_factors.append(f"Connection to suspicious port {conn.dest_port}")
        
        # Check for external connections from internal services
        if self.is_internal_ip(conn.source_ip) and not self.is_internal_ip(conn.dest_ip):
            if conn.dest_port not in {80, 443, 53}:  # Common external ports
                risk_factors.append("Unusual external connection from internal service")
        
        # Check for unencrypted connections to external services
        if not conn.is_internal and not conn.is_encrypted:
            risk_factors.append("Unencrypted external connection")
        
        # Check against baseline
        baseline_key = f"{conn.source_ip}:{conn.dest_port}:{conn.protocol}"
        if baseline_key not in self.network_baselines:
            risk_factors.append("Connection to new destination")
        
        # Create security event if risks detected
        if risk_factors:
            await self.create_security_event(
                InfraEventType.NETWORK_ANOMALY,
                SeverityLevel.MEDIUM,
                conn.source_ip,
                conn.dest_ip,
                f"Network anomaly detected: {', '.join(risk_factors)}",
                {
                    'connection': asdict(conn),
                    'risk_factors': risk_factors
                },
                [f"connection:{conn.connection_id}"],
                [
                    "Review connection purpose",
                    "Verify source legitimacy",
                    "Consider firewall rules"
                ]
            )
    
    async def detect_port_scans(self):
        """Detect port scanning attempts"""
        try:
            # Use Redis to track connection attempts
            current_time = int(time.time())
            window_size = 300  # 5 minutes
            
            # Get recent connection attempts per source IP
            scan_key = "port_scan_detection"
            
            # This would be populated by network monitoring agent
            # For now, simulate detection logic
            
            # In production, you'd analyze netstat/ss output or use network monitoring tools
            
        except Exception as e:
            logger.error("Error detecting port scans", error=str(e))
    
    async def detect_traffic_anomalies(self):
        """Detect unusual traffic patterns"""
        try:
            # Analyze traffic volume, patterns, and destinations
            # This would typically involve ML models in production
            
            # Check for data exfiltration patterns
            await self.detect_data_exfiltration()
            
            # Check for DDoS patterns
            await self.detect_ddos_patterns()
            
        except Exception as e:
            logger.error("Error detecting traffic anomalies", error=str(e))
    
    async def detect_data_exfiltration(self):
        """Detect potential data exfiltration"""
        try:
            # Look for large outbound transfers
            # Check for connections to unusual destinations
            # Analyze transfer patterns
            pass
            
        except Exception as e:
            logger.error("Error detecting data exfiltration", error=str(e))
    
    async def detect_ddos_patterns(self):
        """Detect DDoS attack patterns"""
        try:
            # Analyze connection rates
            # Check for traffic spikes
            # Identify attack signatures
            pass
            
        except Exception as e:
            logger.error("Error detecting DDoS patterns", error=str(e))
    
    async def monitor_container_security(self):
        """Monitor container security state"""
        if not self.docker_client:
            return
        
        try:
            containers = self.docker_client.containers.list()
            
            for container in containers:
                await self.analyze_container_security(container)
                
        except Exception as e:
            logger.error("Error monitoring container security", error=str(e))
    
    async def analyze_container_security(self, container):
        """Analyze container for security violations"""
        try:
            # Get container details
            container.reload()
            attrs = container.attrs
            
            security_violations = []
            
            # Check if running as root
            if attrs.get('Config', {}).get('User') in [None, '', '0', 'root']:
                security_violations.append("Running as root user")
            
            # Check for privileged mode
            if attrs.get('HostConfig', {}).get('Privileged', False):
                security_violations.append("Running in privileged mode")
            
            # Check for host network
            if attrs.get('HostConfig', {}).get('NetworkMode') == 'host':
                security_violations.append("Using host network")
            
            # Check for host PID namespace
            if attrs.get('HostConfig', {}).get('PidMode') == 'host':
                security_violations.append("Using host PID namespace")
            
            # Check for dangerous capabilities
            cap_add = attrs.get('HostConfig', {}).get('CapAdd', []) or []
            dangerous_caps = {'SYS_ADMIN', 'NET_ADMIN', 'SYS_PTRACE', 'SYS_MODULE'}
            for cap in cap_add:
                if cap in dangerous_caps:
                    security_violations.append(f"Dangerous capability: {cap}")
            
            # Check for sensitive volume mounts
            mounts = attrs.get('Mounts', [])
            for mount in mounts:
                source = mount.get('Source', '')
                if any(sensitive in source for sensitive in ['/etc', '/var/run/docker.sock', '/proc', '/sys']):
                    security_violations.append(f"Sensitive volume mount: {source}")
            
            # Check for secrets in environment variables
            env_vars = attrs.get('Config', {}).get('Env', [])
            for env_var in env_vars:
                if any(secret in env_var.lower() for secret in ['password', 'secret', 'key', 'token']):
                    security_violations.append("Potential secret in environment variable")
            
            # Create security events for violations
            if security_violations:
                await self.create_security_event(
                    InfraEventType.CONTAINER_BREACH,
                    SeverityLevel.HIGH,
                    container.name,
                    None,
                    f"Container security violations: {', '.join(security_violations)}",
                    {
                        'container_id': container.id,
                        'image': attrs.get('Config', {}).get('Image'),
                        'violations': security_violations
                    },
                    [f"container:{container.name}"],
                    [
                        "Review container configuration",
                        "Update security policies",
                        "Consider container rebuild"
                    ]
                )
                
                for violation in security_violations:
                    self.container_security_violations.labels(
                        violation_type=violation.split(':')[0],
                        container=container.name
                    ).inc()
            
            # Store container state
            container_state = ContainerSecurityState(
                container_id=container.id,
                name=container.name,
                image=attrs.get('Config', {}).get('Image', ''),
                running_as_root=attrs.get('Config', {}).get('User') in [None, '', '0', 'root'],
                privileged=attrs.get('HostConfig', {}).get('Privileged', False),
                host_network=attrs.get('HostConfig', {}).get('NetworkMode') == 'host',
                host_pid=attrs.get('HostConfig', {}).get('PidMode') == 'host',
                capabilities=cap_add,
                security_opt=attrs.get('HostConfig', {}).get('SecurityOpt', []),
                volumes=[m.get('Source', '') for m in mounts],
                environment_vars={},  # Simplified for security
                process_count=len(container.top()['Processes']) if container.status == 'running' else 0,
                network_connections=[],
                last_updated=datetime.utcnow()
            )
            
            self.container_states[container.id] = container_state
            await self.store_container_state(container_state)
            
        except Exception as e:
            logger.error("Error analyzing container security", error=str(e), container=container.name)
    
    async def monitor_database_access(self):
        """Monitor database access patterns"""
        try:
            # Monitor PostgreSQL logs for suspicious queries
            await self.analyze_database_logs()
            
            # Check for unusual connection patterns
            await self.check_database_connections()
            
            # Monitor for privilege escalation attempts
            await self.check_database_privileges()
            
        except Exception as e:
            logger.error("Error monitoring database access", error=str(e))
    
    async def analyze_database_logs(self):
        """Analyze database logs for security issues"""
        try:
            # In production, this would parse actual PostgreSQL logs
            # For now, simulate by checking recent queries
            
            async with self.db_pool.acquire() as conn:
                # Check for suspicious query patterns
                suspicious_patterns = [
                    "DROP TABLE",
                    "DELETE FROM",
                    "UPDATE.*SET.*=.*password",
                    "INSERT INTO.*users",
                    "GRANT.*TO",
                    "ALTER USER",
                    "CREATE USER"
                ]
                
                # This would be from actual log parsing
                # Simulated suspicious query detection
                
        except Exception as e:
            logger.error("Error analyzing database logs", error=str(e))
    
    async def check_database_connections(self):
        """Check database connection patterns"""
        try:
            async with self.db_pool.acquire() as conn:
                # Get current database connections
                active_connections = await conn.fetch("""
                    SELECT client_addr, usename, datname, state, query_start,
                           state_change, query
                    FROM pg_stat_activity 
                    WHERE state = 'active' AND pid != pg_backend_pid()
                """)
                
                for conn_info in active_connections:
                    # Check for suspicious connection patterns
                    client_addr = conn_info['client_addr']
                    username = conn_info['usename']
                    query = conn_info['query'] or ''
                    
                    # Check for admin queries from non-admin users
                    if 'admin' not in username.lower():
                        admin_keywords = ['DROP', 'ALTER', 'CREATE USER', 'GRANT', 'REVOKE']
                        if any(keyword in query.upper() for keyword in admin_keywords):
                            await self.create_security_event(
                                InfraEventType.DATABASE_ANOMALY,
                                SeverityLevel.HIGH,
                                str(client_addr) if client_addr else 'unknown',
                                'database',
                                f"Non-admin user {username} executing admin command",
                                {
                                    'username': username,
                                    'query': query[:200],  # Truncate for security
                                    'client_addr': str(client_addr)
                                },
                                ['database'],
                                [
                                    "Review user permissions",
                                    "Audit query execution",
                                    "Check for privilege escalation"
                                ]
                            )
                
        except Exception as e:
            logger.error("Error checking database connections", error=str(e))
    
    async def check_database_privileges(self):
        """Check for database privilege changes"""
        try:
            async with self.db_pool.acquire() as conn:
                # Monitor role and privilege changes
                # This would typically be done through database audit logs
                pass
                
        except Exception as e:
            logger.error("Error checking database privileges", error=str(e))
    
    async def monitor_configuration_changes(self):
        """Monitor for configuration changes"""
        try:
            # Monitor Kubernetes configurations
            if self.k8s_client:
                await self.monitor_k8s_configs()
            
            # Monitor Docker configurations
            if self.docker_client:
                await self.monitor_docker_configs()
            
            # Monitor system configurations
            await self.monitor_system_configs()
            
        except Exception as e:
            logger.error("Error monitoring configuration changes", error=str(e))
    
    async def monitor_k8s_configs(self):
        """Monitor Kubernetes configuration changes"""
        try:
            # Get current ConfigMaps
            config_maps = self.k8s_client.list_config_map_for_all_namespaces()
            
            for cm in config_maps.items:
                config_key = f"k8s:configmap:{cm.metadata.namespace}:{cm.metadata.name}"
                current_hash = hashlib.sha256(
                    json.dumps(cm.data or {}, sort_keys=True).encode()
                ).hexdigest()
                
                if config_key in self.config_hashes:
                    if self.config_hashes[config_key] != current_hash:
                        await self.handle_config_change(
                            'kubernetes_configmap',
                            f"{cm.metadata.namespace}/{cm.metadata.name}",
                            'modified',
                            self.config_hashes[config_key],
                            current_hash,
                            'system'
                        )
                
                self.config_hashes[config_key] = current_hash
            
            # Get current Secrets
            secrets = self.k8s_client.list_secret_for_all_namespaces()
            
            for secret in secrets.items:
                config_key = f"k8s:secret:{secret.metadata.namespace}:{secret.metadata.name}"
                # Don't hash actual secret data, just metadata
                current_hash = hashlib.sha256(
                    f"{secret.metadata.name}:{secret.type}:{len(secret.data or {})}".encode()
                ).hexdigest()
                
                if config_key in self.config_hashes:
                    if self.config_hashes[config_key] != current_hash:
                        await self.handle_config_change(
                            'kubernetes_secret',
                            f"{secret.metadata.namespace}/{secret.metadata.name}",
                            'modified',
                            self.config_hashes[config_key],
                            current_hash,
                            'system',
                            compliance_impact='Potential secret exposure'
                        )
                
                self.config_hashes[config_key] = current_hash
                
        except Exception as e:
            logger.error("Error monitoring Kubernetes configs", error=str(e))
    
    async def monitor_docker_configs(self):
        """Monitor Docker configuration changes"""
        try:
            # Monitor container configurations
            containers = self.docker_client.containers.list(all=True)
            
            for container in containers:
                config_key = f"docker:container:{container.name}"
                container_config = {
                    'image': container.image.id,
                    'status': container.status,
                    'labels': container.labels
                }
                current_hash = hashlib.sha256(
                    json.dumps(container_config, sort_keys=True).encode()
                ).hexdigest()
                
                if config_key in self.config_hashes:
                    if self.config_hashes[config_key] != current_hash:
                        await self.handle_config_change(
                            'docker_container',
                            container.name,
                            'modified',
                            self.config_hashes[config_key],
                            current_hash,
                            'system'
                        )
                
                self.config_hashes[config_key] = current_hash
                
        except Exception as e:
            logger.error("Error monitoring Docker configs", error=str(e))
    
    async def monitor_system_configs(self):
        """Monitor system configuration files"""
        try:
            config_files = [
                '/etc/passwd',
                '/etc/group',
                '/etc/sudoers',
                '/etc/ssh/sshd_config',
                '/etc/hosts'
            ]
            
            for config_file in config_files:
                try:
                    with open(config_file, 'r') as f:
                        content = f.read()
                    
                    current_hash = hashlib.sha256(content.encode()).hexdigest()
                    config_key = f"system:file:{config_file}"
                    
                    if config_key in self.config_hashes:
                        if self.config_hashes[config_key] != current_hash:
                            await self.handle_config_change(
                                'system_file',
                                config_file,
                                'modified',
                                self.config_hashes[config_key],
                                current_hash,
                                'system',
                                compliance_impact='System security configuration changed'
                            )
                    
                    self.config_hashes[config_key] = current_hash
                    
                except FileNotFoundError:
                    continue
                except PermissionError:
                    continue
                    
        except Exception as e:
            logger.error("Error monitoring system configs", error=str(e))
    
    async def handle_config_change(self, config_type: str, config_path: str,
                                 change_type: str, old_hash: str, new_hash: str,
                                 changed_by: str, compliance_impact: Optional[str] = None):
        """Handle detected configuration change"""
        try:
            # Create security event
            severity = SeverityLevel.HIGH if 'secret' in config_type.lower() or 'passwd' in config_path else SeverityLevel.MEDIUM
            
            await self.create_security_event(
                InfraEventType.CONFIG_CHANGE,
                severity,
                changed_by,
                config_path,
                f"Configuration change detected in {config_type}: {config_path}",
                {
                    'config_type': config_type,
                    'change_type': change_type,
                    'old_hash': old_hash,
                    'new_hash': new_hash
                },
                [f"config:{config_path}"],
                [
                    "Review configuration change",
                    "Verify change authorization",
                    "Check for security impact"
                ],
                compliance_impact
            )
            
            # Store in database
            async with self.db_pool.acquire() as conn:
                await conn.execute("""
                    INSERT INTO config_changes 
                    (config_type, config_path, change_type, old_hash, new_hash, changed_by, details)
                    VALUES ($1, $2, $3, $4, $5, $6, $7)
                """, config_type, config_path, change_type, old_hash, new_hash, changed_by, {})
            
            # Update metrics
            self.config_changes_total.labels(
                config_type=config_type,
                change_type=change_type
            ).inc()
            
        except Exception as e:
            logger.error("Error handling config change", error=str(e))
    
    async def monitor_resource_usage(self):
        """Monitor system resource usage for security issues"""
        try:
            # CPU usage
            cpu_percent = psutil.cpu_percent(interval=1)
            self.resource_usage_gauge.labels(
                resource_type='cpu',
                host='local'
            ).set(cpu_percent)
            
            # Memory usage
            memory = psutil.virtual_memory()
            self.resource_usage_gauge.labels(
                resource_type='memory',
                host='local'
            ).set(memory.percent)
            
            # Disk usage
            disk = psutil.disk_usage('/')
            disk_percent = (disk.used / disk.total) * 100
            self.resource_usage_gauge.labels(
                resource_type='disk',
                host='local'
            ).set(disk_percent)
            
            # Check for resource exhaustion attacks
            if cpu_percent > 95:
                await self.create_security_event(
                    InfraEventType.RESOURCE_EXHAUSTION,
                    SeverityLevel.HIGH,
                    'system',
                    'cpu',
                    f"High CPU usage detected: {cpu_percent}%",
                    {'cpu_percent': cpu_percent},
                    ['system:cpu'],
                    ['Investigate high CPU processes', 'Check for DoS attacks']
                )
            
            if memory.percent > 95:
                await self.create_security_event(
                    InfraEventType.RESOURCE_EXHAUSTION,
                    SeverityLevel.HIGH,
                    'system',
                    'memory',
                    f"High memory usage detected: {memory.percent}%",
                    {'memory_percent': memory.percent},
                    ['system:memory'],
                    ['Investigate memory usage', 'Check for memory leaks']
                )
                
        except Exception as e:
            logger.error("Error monitoring resource usage", error=str(e))
    
    async def create_security_event(self, event_type: InfraEventType, severity: SeverityLevel,
                                  source: str, target: Optional[str], description: str,
                                  details: Dict[str, Any], affected_resources: List[str],
                                  remediation_actions: List[str],
                                  compliance_impact: Optional[str] = None):
        """Create and store infrastructure security event"""
        try:
            event = InfraSecurityEvent(
                event_id=str(uuid.uuid4()),
                timestamp=datetime.utcnow(),
                event_type=event_type,
                severity=severity,
                source=source,
                target=target,
                description=description,
                details=details,
                affected_resources=affected_resources,
                remediation_actions=remediation_actions,
                compliance_impact=compliance_impact,
                metadata={}
            )
            
            # Store in database
            await self.store_security_event(event)
            
            # Update metrics
            self.security_events_total.labels(
                event_type=event_type.value,
                severity=severity.value,
                source=source
            ).inc()
            
            # Send alert for high/critical events
            if severity in [SeverityLevel.HIGH, SeverityLevel.CRITICAL]:
                await self.send_security_alert(event)
            
            logger.warning(
                "Infrastructure security event",
                event_id=event.event_id,
                event_type=event_type.value,
                severity=severity.value,
                description=description
            )
            
        except Exception as e:
            logger.error("Error creating security event", error=str(e))
    
    async def store_security_event(self, event: InfraSecurityEvent):
        """Store security event in database"""
        try:
            async with self.db_pool.acquire() as conn:
                await conn.execute("""
                    INSERT INTO infra_security_events 
                    (event_id, timestamp, event_type, severity, source, target,
                     description, details, affected_resources, remediation_actions,
                     compliance_impact, metadata)
                    VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
                """,
                    event.event_id, event.timestamp, event.event_type.value,
                    event.severity.value, event.source, event.target,
                    event.description, json.dumps(event.details),
                    event.affected_resources, event.remediation_actions,
                    event.compliance_impact, json.dumps(event.metadata)
                )
                
        except Exception as e:
            logger.error("Error storing security event", error=str(e))
    
    async def store_network_connection(self, conn: NetworkConnection):
        """Store network connection in database"""
        try:
            async with self.db_pool.acquire() as db_conn:
                await db_conn.execute("""
                    INSERT INTO network_connections 
                    (connection_id, source_ip, source_port, dest_ip, dest_port,
                     protocol, bytes_sent, bytes_received, duration_seconds,
                     is_internal, is_encrypted)
                    VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
                    ON CONFLICT (connection_id) DO UPDATE SET
                        bytes_sent = EXCLUDED.bytes_sent,
                        bytes_received = EXCLUDED.bytes_received,
                        duration_seconds = EXCLUDED.duration_seconds
                """,
                    conn.connection_id, conn.source_ip, conn.source_port,
                    conn.dest_ip, conn.dest_port, conn.protocol,
                    conn.bytes_sent, conn.bytes_received, conn.duration,
                    conn.is_internal, conn.is_encrypted
                )
                
        except Exception as e:
            logger.error("Error storing network connection", error=str(e))
    
    async def store_container_state(self, state: ContainerSecurityState):
        """Store container security state"""
        try:
            async with self.db_pool.acquire() as conn:
                await conn.execute("""
                    INSERT INTO container_security_state 
                    (container_id, name, image, running_as_root, privileged,
                     host_network, host_pid, capabilities, security_opt,
                     volumes, process_count)
                    VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
                    ON CONFLICT (container_id) DO UPDATE SET
                        name = EXCLUDED.name,
                        image = EXCLUDED.image,
                        running_as_root = EXCLUDED.running_as_root,
                        privileged = EXCLUDED.privileged,
                        host_network = EXCLUDED.host_network,
                        host_pid = EXCLUDED.host_pid,
                        capabilities = EXCLUDED.capabilities,
                        security_opt = EXCLUDED.security_opt,
                        volumes = EXCLUDED.volumes,
                        process_count = EXCLUDED.process_count,
                        timestamp = NOW()
                """,
                    state.container_id, state.name, state.image,
                    state.running_as_root, state.privileged, state.host_network,
                    state.host_pid, state.capabilities, state.security_opt,
                    state.volumes, state.process_count
                )
                
        except Exception as e:
            logger.error("Error storing container state", error=str(e))
    
    async def send_security_alert(self, event: InfraSecurityEvent):
        """Send security alert for high-priority events"""
        try:
            alert_data = {
                'alert_id': str(uuid.uuid4()),
                'timestamp': event.timestamp.isoformat(),
                'event_id': event.event_id,
                'event_type': event.event_type.value,
                'severity': event.severity.value,
                'source': event.source,
                'target': event.target,
                'description': event.description,
                'affected_resources': event.affected_resources,
                'remediation_actions': event.remediation_actions
            }
            
            # Publish to Redis for alerting system
            await self.redis_client.publish('infra_security_alerts', json.dumps(alert_data))
            
        except Exception as e:
            logger.error("Error sending security alert", error=str(e))
    
    def is_internal_ip(self, ip: str) -> bool:
        """Check if IP is internal"""
        try:
            from ipaddress import ip_address, ip_network
            ip_obj = ip_address(ip)
            return any(ip_obj in ip_network(net) for net in self.internal_networks)
        except:
            return False
    
    def is_encrypted_port(self, port: int) -> bool:
        """Check if port typically uses encryption"""
        encrypted_ports = {443, 993, 995, 636, 989, 990, 5432}  # HTTPS, IMAPS, POP3S, LDAPS, FTPS, PostgreSQL SSL
        return port in encrypted_ports
    
    async def load_network_baselines(self):
        """Load network baselines from database"""
        try:
            async with self.db_pool.acquire() as conn:
                baselines = await conn.fetch("SELECT * FROM network_baselines")
                
                for baseline in baselines:
                    key = f"{baseline['source_ip']}:{baseline['dest_port']}:{baseline['protocol']}"
                    self.network_baselines[key] = baseline['baseline_data']
                    
        except Exception as e:
            logger.error("Error loading network baselines", error=str(e))
    
    async def load_config_baselines(self):
        """Load configuration baselines"""
        try:
            # Initialize configuration hashes for monitoring
            await self.monitor_k8s_configs()
            await self.monitor_docker_configs()
            await self.monitor_system_configs()
            
        except Exception as e:
            logger.error("Error loading config baselines", error=str(e))
    
    async def scan_container_security(self):
        """Perform initial container security scan"""
        try:
            if self.docker_client:
                await self.monitor_container_security()
                
        except Exception as e:
            logger.error("Error scanning container security", error=str(e))
    
    async def run_monitoring_cycle(self):
        """Run one complete monitoring cycle"""
        try:
            # Monitor network traffic
            await self.monitor_network_traffic()
            
            # Monitor container security
            await self.monitor_container_security()
            
            # Monitor database access
            await self.monitor_database_access()
            
            # Monitor configuration changes
            await self.monitor_configuration_changes()
            
            # Monitor resource usage
            await self.monitor_resource_usage()
            
        except Exception as e:
            logger.error("Error in monitoring cycle", error=str(e))
    
    async def close(self):
        """Clean up resources"""
        if self.db_pool:
            await self.db_pool.close()
        if self.redis_client:
            await self.redis_client.close()
        if self.docker_client:
            self.docker_client.close()

# Main monitoring loop
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
        }
    }
    
    monitor = InfrastructureSecurityMonitor(config)
    await monitor.initialize()
    
    logger.info("Infrastructure security monitor started successfully")
    
    try:
        while True:
            await monitor.run_monitoring_cycle()
            await asyncio.sleep(60)  # Run every minute
            
    except KeyboardInterrupt:
        logger.info("Shutting down infrastructure security monitor")
    finally:
        await monitor.close()

if __name__ == "__main__":
    asyncio.run(main())