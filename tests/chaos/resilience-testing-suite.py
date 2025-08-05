"""
Chaos Engineering and Resilience Testing Suite
==============================================

This module implements chaos engineering tests to validate PyAirtable's resilience
and failure recovery capabilities across the 6-service architecture.

Chaos Scenarios:
1. Service Failures (Individual service crashes)
2. Network Partitions (Service communication failures)
3. Database Connection Failures
4. Resource Exhaustion (CPU, Memory, Disk)
5. Dependency Failures (External APIs)
6. Cascading Failures
7. Recovery Validation

Features:
- Controlled chaos injection
- Real-time system monitoring
- Automatic recovery detection
- Resilience scoring
- Failure analysis and reporting
"""

import asyncio
import json
import logging
import random
import time
from dataclasses import dataclass, asdict
from datetime import datetime, timedelta
from enum import Enum
from pathlib import Path
from typing import Dict, List, Optional, Any, Callable
import httpx
import docker
import psutil
import threading

logger = logging.getLogger(__name__)

class ChaosType(Enum):
    SERVICE_FAILURE = "service_failure"
    NETWORK_PARTITION = "network_partition"
    DATABASE_FAILURE = "database_failure"
    RESOURCE_EXHAUSTION = "resource_exhaustion"
    DEPENDENCY_FAILURE = "dependency_failure"
    CASCADING_FAILURE = "cascading_failure"

class SystemState(Enum):
    HEALTHY = "healthy"
    DEGRADED = "degraded"
    FAILING = "failing"
    RECOVERING = "recovering"
    FAILED = "failed"

@dataclass
class ChaosExperiment:
    """Definition of a chaos engineering experiment"""
    name: str
    chaos_type: ChaosType
    target_service: str
    duration_seconds: int
    impact_radius: List[str]  # Services expected to be affected
    recovery_time_limit: int  # Max time for recovery in seconds
    steady_state_hypothesis: str
    expected_behavior: str
    rollback_strategy: str

@dataclass
class SystemMetrics:
    """System health and performance metrics"""
    timestamp: datetime
    cpu_usage: float
    memory_usage: float
    disk_usage: float
    network_latency: float
    active_connections: int
    error_rate: float
    response_time_p95: float
    service_health: Dict[str, bool]

@dataclass
class ChaosResult:
    """Result of a chaos engineering experiment"""
    experiment: ChaosExperiment
    start_time: datetime
    end_time: Optional[datetime]
    steady_state_maintained: bool
    recovery_time: Optional[float]
    impact_assessment: Dict[str, Any]
    system_behavior: List[SystemMetrics]
    anomalies_detected: List[str]
    recovery_successful: bool
    resilience_score: float
    lessons_learned: List[str]

class ChaosMonkey:
    """Chaos engineering orchestrator for PyAirtable"""
    
    def __init__(self):
        self.docker_client = docker.from_env()
        self.http_client = httpx.AsyncClient(timeout=10.0)
        self.monitoring_active = False
        self.baseline_metrics: Optional[SystemMetrics] = None
        self.current_experiment: Optional[ChaosExperiment] = None
        self.results: List[ChaosResult] = []
        
        # Service definitions
        self.services = {
            'api-gateway': {'port': 8000, 'container': 'pyairtable-compose-api-gateway-1'},
            'auth-service': {'port': 8004, 'container': 'pyairtable-compose-auth-service-1'},
            'llm-orchestrator': {'port': 8003, 'container': 'pyairtable-compose-llm-orchestrator-1'},
            'mcp-server': {'port': 8001, 'container': 'pyairtable-compose-mcp-server-1'},
            'airtable-gateway': {'port': 8002, 'container': 'pyairtable-compose-airtable-gateway-1'},
            'platform-services': {'port': 8005, 'container': 'pyairtable-compose-platform-services-1'}
        }
        
        # Define chaos experiments
        self.chaos_experiments = self._define_chaos_experiments()
    
    def _define_chaos_experiments(self) -> List[ChaosExperiment]:
        """Define chaos engineering experiments"""
        return [
            ChaosExperiment(
                name="LLM Orchestrator Crash",
                chaos_type=ChaosType.SERVICE_FAILURE,
                target_service="llm-orchestrator",
                duration_seconds=60,
                impact_radius=["api-gateway", "mcp-server"],
                recovery_time_limit=120,
                steady_state_hypothesis="API Gateway should handle LLM service failures gracefully",
                expected_behavior="Chat requests return error messages, system remains stable",
                rollback_strategy="Restart LLM Orchestrator service"
            ),
            
            ChaosExperiment(
                name="Database Connection Failure",
                chaos_type=ChaosType.DATABASE_FAILURE,
                target_service="postgres",
                duration_seconds=90,
                impact_radius=["auth-service", "platform-services"],
                recovery_time_limit=180,
                steady_state_hypothesis="Services should degrade gracefully when database is unavailable",
                expected_behavior="Authentication fails gracefully, cached data used where possible",
                rollback_strategy="Restore database connection"
            ),
            
            ChaosExperiment(
                name="API Gateway Memory Exhaustion",
                chaos_type=ChaosType.RESOURCE_EXHAUSTION,
                target_service="api-gateway",
                duration_seconds=120,
                impact_radius=["all"],
                recovery_time_limit=60,
                steady_state_hypothesis="System should handle API Gateway resource pressure",
                expected_behavior="Requests may be slower but system remains functional",
                rollback_strategy="Kill memory-consuming processes and restart if needed"
            ),
            
            ChaosExperiment(
                name="Airtable API Timeout",
                chaos_type=ChaosType.DEPENDENCY_FAILURE,
                target_service="airtable-gateway",
                duration_seconds=180,
                impact_radius=["mcp-server", "llm-orchestrator"],
                recovery_time_limit=90,
                steady_state_hypothesis="System should handle external API failures",
                expected_behavior="Users get informative error messages, system remains stable",
                rollback_strategy="Restore external API connectivity"
            ),
            
            ChaosExperiment(
                name="Network Partition - MCP Isolation",
                chaos_type=ChaosType.NETWORK_PARTITION,
                target_service="mcp-server",
                duration_seconds=150,
                impact_radius=["llm-orchestrator", "airtable-gateway"],
                recovery_time_limit=120,
                steady_state_hypothesis="LLM Orchestrator should detect MCP unavailability",
                expected_behavior="Graceful degradation with user notification",
                rollback_strategy="Restore network connectivity"
            ),
            
            ChaosExperiment(
                name="Cascading Auth Failure",
                chaos_type=ChaosType.CASCADING_FAILURE,
                target_service="auth-service",
                duration_seconds=200,
                impact_radius=["api-gateway", "platform-services", "frontend"],
                recovery_time_limit=300,
                steady_state_hypothesis="Auth failure should not crash entire system",
                expected_behavior="Users redirected to login, public endpoints remain accessible",
                rollback_strategy="Restart auth service and dependent services"
            )
        ]
    
    async def establish_baseline(self) -> SystemMetrics:
        """Establish baseline system metrics"""
        logger.info("Establishing system baseline...")
        
        # Wait for system to stabilize
        await asyncio.sleep(10)
        
        metrics = await self._collect_system_metrics()
        self.baseline_metrics = metrics
        
        logger.info(f"Baseline established: {metrics.cpu_usage:.1f}% CPU, "
                   f"{metrics.memory_usage:.1f}% Memory, "
                   f"{metrics.response_time_p95:.1f}ms P95")
        
        return metrics
    
    async def run_chaos_experiment(self, experiment: ChaosExperiment) -> ChaosResult:
        """Run a single chaos engineering experiment"""
        logger.info(f"Starting chaos experiment: {experiment.name}")
        
        self.current_experiment = experiment
        result = ChaosResult(
            experiment=experiment,
            start_time=datetime.now(),
            end_time=None,
            steady_state_maintained=False,
            recovery_time=None,
            impact_assessment={},
            system_behavior=[],
            anomalies_detected=[],
            recovery_successful=False,
            resilience_score=0.0,
            lessons_learned=[]
        )
        
        try:
            # Pre-chaos validation
            pre_chaos_metrics = await self._collect_system_metrics()
            result.system_behavior.append(pre_chaos_metrics)
            
            # Start monitoring
            monitoring_task = asyncio.create_task(
                self._monitor_system_during_chaos(result)
            )
            
            # Inject chaos
            await self._inject_chaos(experiment)
            
            # Wait for chaos duration
            await asyncio.sleep(experiment.duration_seconds)
            
            # Begin recovery
            recovery_start = time.time()
            await self._initiate_recovery(experiment)
            
            # Wait for recovery
            recovery_successful = await self._wait_for_recovery(
                experiment, experiment.recovery_time_limit
            )
            
            recovery_time = time.time() - recovery_start
            result.recovery_time = recovery_time
            result.recovery_successful = recovery_successful
            
            # Stop monitoring
            monitoring_task.cancel()
            
            # Post-chaos analysis
            result.end_time = datetime.now()
            result.impact_assessment = await self._assess_impact(experiment)
            result.resilience_score = self._calculate_resilience_score(result)
            result.lessons_learned = self._extract_lessons_learned(result)
            
            logger.info(f"Chaos experiment completed: {experiment.name} "
                       f"(Resilience Score: {result.resilience_score:.1f}/10)")
            
        except Exception as e:
            logger.error(f"Chaos experiment failed: {e}")
            result.anomalies_detected.append(f"Experiment execution error: {e}")
            
            # Emergency recovery
            await self._emergency_recovery()
        
        finally:
            self.current_experiment = None
            self.results.append(result)
        
        return result
    
    async def _inject_chaos(self, experiment: ChaosExperiment):
        """Inject chaos based on experiment type"""
        logger.info(f"Injecting chaos: {experiment.chaos_type.value} on {experiment.target_service}")
        
        if experiment.chaos_type == ChaosType.SERVICE_FAILURE:
            await self._crash_service(experiment.target_service)
            
        elif experiment.chaos_type == ChaosType.DATABASE_FAILURE:
            await self._disrupt_database_connection(experiment.target_service)
            
        elif experiment.chaos_type == ChaosType.RESOURCE_EXHAUSTION:
            await self._exhaust_resources(experiment.target_service)
            
        elif experiment.chaos_type == ChaosType.DEPENDENCY_FAILURE:
            await self._disrupt_external_dependency(experiment.target_service)
            
        elif experiment.chaos_type == ChaosType.NETWORK_PARTITION:
            await self._create_network_partition(experiment.target_service)
            
        elif experiment.chaos_type == ChaosType.CASCADING_FAILURE:
            await self._trigger_cascading_failure(experiment.target_service)
    
    async def _crash_service(self, service_name: str):
        """Crash a specific service"""
        try:
            container_name = self.services[service_name]['container']
            container = self.docker_client.containers.get(container_name)
            container.kill()
            logger.info(f"Service {service_name} crashed")
        except Exception as e:
            logger.error(f"Failed to crash service {service_name}: {e}")
    
    async def _disrupt_database_connection(self, db_type: str):
        """Disrupt database connections"""
        try:
            if db_type == "postgres":
                # Stop PostgreSQL container
                container = self.docker_client.containers.get("pyairtable-compose-postgres-1")
                container.stop()
                logger.info("PostgreSQL database stopped")
            elif db_type == "redis":
                # Stop Redis container
                container = self.docker_client.containers.get("pyairtable-compose-redis-1")
                container.stop()
                logger.info("Redis database stopped")
        except Exception as e:
            logger.error(f"Failed to disrupt database {db_type}: {e}")
    
    async def _exhaust_resources(self, service_name: str):
        """Exhaust system resources for a service"""
        try:
            container_name = self.services[service_name]['container']
            container = self.docker_client.containers.get(container_name)
            
            # Simulate CPU and memory stress
            stress_command = """
            python3 -c "
            import time
            import threading
            
            def cpu_stress():
                while True:
                    sum(i*i for i in range(10000))
            
            def memory_stress():
                data = []
                for i in range(100):
                    data.append(' ' * 1024 * 1024)  # 1MB chunks
                    time.sleep(0.1)
            
            # Start stress threads
            for _ in range(4):
                threading.Thread(target=cpu_stress, daemon=True).start()
            
            threading.Thread(target=memory_stress, daemon=True).start()
            time.sleep(120)  # Stress for 2 minutes
            "
            """
            
            container.exec_run(stress_command, detach=True)
            logger.info(f"Resource exhaustion started on {service_name}")
            
        except Exception as e:
            logger.error(f"Failed to exhaust resources for {service_name}: {e}")
    
    async def _disrupt_external_dependency(self, service_name: str):
        """Disrupt external API dependencies"""
        try:
            # Block external API calls by manipulating network rules
            # This is a simplified simulation - in real scenarios, you'd use tools like Toxiproxy
            
            if service_name == "airtable-gateway":
                # Simulate Airtable API being unreachable
                # In practice, this could involve DNS manipulation or firewall rules
                logger.info("Simulating Airtable API unavailability")
                
                # Inject network delays and failures
                container_name = self.services[service_name]['container']
                container = self.docker_client.containers.get(container_name)
                
                # Add artificial delays to external requests
                delay_command = """
                python3 -c "
                import os
                import time
                
                # Set environment variable to trigger artificial delays
                os.environ['CHAOS_INJECT_DELAY'] = '5000'  # 5 second delay
                os.environ['CHAOS_INJECT_FAILURE_RATE'] = '0.8'  # 80% failure rate
                time.sleep(180)  # Maintain chaos for 3 minutes
                "
                """
                
                container.exec_run(delay_command, detach=True)
                
        except Exception as e:
            logger.error(f"Failed to disrupt external dependency for {service_name}: {e}")
    
    async def _create_network_partition(self, service_name: str):
        """Create a network partition isolating a service"""
        try:
            container_name = self.services[service_name]['container']
            container = self.docker_client.containers.get(container_name)
            
            # Simulate network partition by blocking inter-service communication
            # In practice, this would involve iptables rules or network policies
            
            partition_command = """
            # Block outgoing connections to other services
            iptables -A OUTPUT -p tcp --dport 8000:8005 -j DROP
            sleep 150
            # Restore connectivity
            iptables -D OUTPUT -p tcp --dport 8000:8005 -j DROP
            """
            
            container.exec_run(f"bash -c '{partition_command}'", detach=True)
            logger.info(f"Network partition created for {service_name}")
            
        except Exception as e:
            logger.error(f"Failed to create network partition for {service_name}: {e}")
    
    async def _trigger_cascading_failure(self, initial_service: str):
        """Trigger a cascading failure starting from initial service"""
        try:
            # Crash the initial service
            await self._crash_service(initial_service)
            
            # Wait and observe cascading effects
            await asyncio.sleep(30)
            
            # Potentially crash dependent services to simulate cascade
            if initial_service == "auth-service":
                # Simulate auth service failure causing API gateway issues
                await asyncio.sleep(30)
                await self._exhaust_resources("api-gateway")
                
        except Exception as e:
            logger.error(f"Failed to trigger cascading failure from {initial_service}: {e}")
    
    async def _initiate_recovery(self, experiment: ChaosExperiment):
        """Initiate recovery from chaos"""
        logger.info(f"Initiating recovery for {experiment.name}")
        
        try:
            if experiment.chaos_type == ChaosType.SERVICE_FAILURE:
                await self._restart_service(experiment.target_service)
                
            elif experiment.chaos_type == ChaosType.DATABASE_FAILURE:
                await self._restore_database(experiment.target_service)
                
            elif experiment.chaos_type == ChaosType.RESOURCE_EXHAUSTION:
                await self._relieve_resource_pressure(experiment.target_service)
                
            elif experiment.chaos_type in [ChaosType.DEPENDENCY_FAILURE, ChaosType.NETWORK_PARTITION]:
                await self._restore_connectivity(experiment.target_service)
                
            elif experiment.chaos_type == ChaosType.CASCADING_FAILURE:
                await self._recover_from_cascade(experiment.target_service)
                
        except Exception as e:
            logger.error(f"Recovery initiation failed: {e}")
    
    async def _restart_service(self, service_name: str):
        """Restart a crashed service"""
        try:
            container_name = self.services[service_name]['container']
            container = self.docker_client.containers.get(container_name)
            container.restart()
            logger.info(f"Service {service_name} restarted")
        except Exception as e:
            logger.error(f"Failed to restart service {service_name}: {e}")
    
    async def _restore_database(self, db_type: str):
        """Restore database connectivity"""
        try:
            if db_type == "postgres":
                container = self.docker_client.containers.get("pyairtable-compose-postgres-1")
                container.start()
                logger.info("PostgreSQL database restored")
            elif db_type == "redis":
                container = self.docker_client.containers.get("pyairtable-compose-redis-1")
                container.start()
                logger.info("Redis database restored")
        except Exception as e:
            logger.error(f"Failed to restore database {db_type}: {e}")
    
    async def _relieve_resource_pressure(self, service_name: str):
        """Relieve resource pressure on a service"""
        try:
            container_name = self.services[service_name]['container']
            container = self.docker_client.containers.get(container_name)
            
            # Kill stress processes
            kill_command = "pkill -f 'python.*stress' || true"
            container.exec_run(kill_command)
            
            # Restart container if needed
            container.restart()
            logger.info(f"Resource pressure relieved for {service_name}")
            
        except Exception as e:
            logger.error(f"Failed to relieve resource pressure for {service_name}: {e}")
    
    async def _restore_connectivity(self, service_name: str):
        """Restore network connectivity"""
        try:
            container_name = self.services[service_name]['container']
            container = self.docker_client.containers.get(container_name)
            
            # Remove chaos environment variables
            restore_command = """
            unset CHAOS_INJECT_DELAY
            unset CHAOS_INJECT_FAILURE_RATE
            # Restore iptables rules
            iptables -F OUTPUT || true
            """
            
            container.exec_run(f"bash -c '{restore_command}'")
            logger.info(f"Connectivity restored for {service_name}")
            
        except Exception as e:
            logger.error(f"Failed to restore connectivity for {service_name}: {e}")
    
    async def _recover_from_cascade(self, initial_service: str):
        """Recover from cascading failure"""
        try:
            # Restart all affected services in dependency order
            recovery_order = ["auth-service", "api-gateway", "platform-services"]
            
            for service in recovery_order:
                if service in self.services:
                    await self._restart_service(service)
                    await asyncio.sleep(10)  # Wait between restarts
                    
            logger.info("Cascading failure recovery completed")
            
        except Exception as e:
            logger.error(f"Failed to recover from cascading failure: {e}")
    
    async def _wait_for_recovery(self, experiment: ChaosExperiment, timeout: int) -> bool:
        """Wait for system to recover after chaos"""
        logger.info(f"Waiting for recovery (timeout: {timeout}s)")
        
        start_time = time.time()
        
        while time.time() - start_time < timeout:
            try:
                # Check if all services in impact radius are healthy
                all_healthy = True
                
                for service in experiment.impact_radius:
                    if service == "all":
                        # Check all services
                        for svc_name in self.services:
                            if not await self._check_service_health(svc_name):
                                all_healthy = False
                                break
                    else:
                        if service in self.services and not await self._check_service_health(service):
                            all_healthy = False
                            break
                
                if all_healthy:
                    recovery_time = time.time() - start_time
                    logger.info(f"Recovery successful in {recovery_time:.1f}s")
                    return True
                
                await asyncio.sleep(5)
                
            except Exception as e:
                logger.error(f"Error during recovery check: {e}")
                await asyncio.sleep(5)
        
        logger.warning(f"Recovery timeout after {timeout}s")
        return False
    
    async def _check_service_health(self, service_name: str) -> bool:
        """Check if a service is healthy"""
        try:
            port = self.services[service_name]['port']
            response = await self.http_client.get(f"http://localhost:{port}/health", timeout=5.0)
            return response.status_code == 200
        except:
            return False
    
    async def _monitor_system_during_chaos(self, result: ChaosResult):
        """Monitor system metrics during chaos experiment"""
        self.monitoring_active = True
        
        try:
            while self.monitoring_active:
                metrics = await self._collect_system_metrics()
                result.system_behavior.append(metrics)
                
                # Detect anomalies
                anomalies = self._detect_anomalies(metrics)
                result.anomalies_detected.extend(anomalies)
                
                await asyncio.sleep(10)  # Collect metrics every 10 seconds
                
        except asyncio.CancelledError:
            self.monitoring_active = False
    
    async def _collect_system_metrics(self) -> SystemMetrics:
        """Collect current system metrics"""
        # System resource metrics
        cpu_usage = psutil.cpu_percent(interval=1)
        memory = psutil.virtual_memory()
        disk = psutil.disk_usage('/')
        
        # Network and service metrics
        service_health = {}
        total_response_time = 0
        healthy_services = 0
        
        for service_name in self.services:
            try:
                start_time = time.time()
                is_healthy = await self._check_service_health(service_name)
                response_time = (time.time() - start_time) * 1000  # Convert to ms
                
                service_health[service_name] = is_healthy
                if is_healthy:
                    total_response_time += response_time
                    healthy_services += 1
                    
            except Exception:
                service_health[service_name] = False
        
        avg_response_time = total_response_time / healthy_services if healthy_services > 0 else 0
        error_rate = (len(self.services) - healthy_services) / len(self.services)
        
        return SystemMetrics(
            timestamp=datetime.now(),
            cpu_usage=cpu_usage,
            memory_usage=memory.percent,
            disk_usage=disk.percent,
            network_latency=0.0,  # Simplified
            active_connections=len([h for h in service_health.values() if h]),
            error_rate=error_rate,
            response_time_p95=avg_response_time,  # Simplified
            service_health=service_health
        )
    
    def _detect_anomalies(self, metrics: SystemMetrics) -> List[str]:
        """Detect system anomalies compared to baseline"""
        anomalies = []
        
        if not self.baseline_metrics:
            return anomalies
        
        # CPU anomaly
        if metrics.cpu_usage > self.baseline_metrics.cpu_usage * 2:
            anomalies.append(f"High CPU usage: {metrics.cpu_usage:.1f}% (baseline: {self.baseline_metrics.cpu_usage:.1f}%)")
        
        # Memory anomaly
        if metrics.memory_usage > self.baseline_metrics.memory_usage * 1.5:
            anomalies.append(f"High memory usage: {metrics.memory_usage:.1f}% (baseline: {self.baseline_metrics.memory_usage:.1f}%)")
        
        # Response time anomaly
        if metrics.response_time_p95 > self.baseline_metrics.response_time_p95 * 3:
            anomalies.append(f"High response time: {metrics.response_time_p95:.1f}ms (baseline: {self.baseline_metrics.response_time_p95:.1f}ms)")
        
        # Error rate anomaly
        if metrics.error_rate > 0.5:  # More than 50% services unhealthy
            anomalies.append(f"High error rate: {metrics.error_rate:.1%}")
        
        return anomalies
    
    async def _assess_impact(self, experiment: ChaosExperiment) -> Dict[str, Any]:
        """Assess the impact of the chaos experiment"""
        impact = {
            'experiment_name': experiment.name,
            'target_service': experiment.target_service,
            'chaos_type': experiment.chaos_type.value,
            'services_affected': [],
            'user_impact_level': 'low',
            'data_integrity_preserved': True,
            'performance_degradation': 0.0
        }
        
        # Check which services were actually affected
        for service_name in self.services:
            if not await self._check_service_health(service_name):
                impact['services_affected'].append(service_name)
        
        # Assess user impact level
        critical_services = ['api-gateway', 'auth-service']
        if any(svc in impact['services_affected'] for svc in critical_services):
            impact['user_impact_level'] = 'high'
        elif len(impact['services_affected']) > 2:
            impact['user_impact_level'] = 'medium'
        
        # Assess performance degradation
        if self.baseline_metrics and self.results:
            current_metrics = await self._collect_system_metrics()
            if current_metrics.response_time_p95 > self.baseline_metrics.response_time_p95:
                degradation = (current_metrics.response_time_p95 - self.baseline_metrics.response_time_p95) / self.baseline_metrics.response_time_p95
                impact['performance_degradation'] = degradation
        
        return impact
    
    def _calculate_resilience_score(self, result: ChaosResult) -> float:
        """Calculate resilience score (0-10) based on experiment results"""
        score = 10.0
        
        # Deduct points for recovery issues
        if not result.recovery_successful:
            score -= 4.0
        elif result.recovery_time and result.recovery_time > result.experiment.recovery_time_limit:
            score -= 2.0
        
        # Deduct points for anomalies
        anomaly_penalty = min(len(result.anomalies_detected) * 0.5, 3.0)
        score -= anomaly_penalty
        
        # Deduct points based on impact
        if result.impact_assessment.get('user_impact_level') == 'high':
            score -= 2.0
        elif result.impact_assessment.get('user_impact_level') == 'medium':
            score -= 1.0
        
        # Deduct points for performance degradation
        perf_degradation = result.impact_assessment.get('performance_degradation', 0.0)
        if perf_degradation > 1.0:  # More than 100% degradation
            score -= 1.0
        
        return max(0.0, score)
    
    def _extract_lessons_learned(self, result: ChaosResult) -> List[str]:
        """Extract lessons learned from chaos experiment"""
        lessons = []
        
        if not result.recovery_successful:
            lessons.append("System failed to recover automatically - improve recovery mechanisms")
        
        if result.recovery_time and result.recovery_time > 60:
            lessons.append("Recovery time is slow - optimize service restart procedures")
        
        if len(result.anomalies_detected) > 5:
            lessons.append("System exhibited many anomalies - improve monitoring and alerting")
        
        if result.impact_assessment.get('user_impact_level') == 'high':
            lessons.append("High user impact - implement better graceful degradation")
        
        critical_services_affected = [
            svc for svc in result.impact_assessment.get('services_affected', [])
            if svc in ['api-gateway', 'auth-service']
        ]
        
        if critical_services_affected:
            lessons.append("Critical services affected - improve redundancy and failover")
        
        if not lessons:
            lessons.append("System demonstrated good resilience to this failure scenario")
        
        return lessons
    
    async def _emergency_recovery(self):
        """Emergency recovery procedure"""
        logger.warning("Executing emergency recovery...")
        
        try:
            # Restart all services
            for service_name in self.services:
                await self._restart_service(service_name)
                await asyncio.sleep(5)
            
            # Restore databases
            await self._restore_database("postgres")
            await self._restore_database("redis")
            
            logger.info("Emergency recovery completed")
            
        except Exception as e:
            logger.error(f"Emergency recovery failed: {e}")
    
    async def run_full_chaos_suite(self) -> List[ChaosResult]:
        """Run the complete chaos engineering test suite"""
        logger.info("Starting full chaos engineering test suite...")
        
        # Establish baseline
        await self.establish_baseline()
        
        results = []
        
        for experiment in self.chaos_experiments:
            try:
                # Wait between experiments for system to stabilize
                if results:
                    logger.info("Waiting for system stabilization...")
                    await asyncio.sleep(60)
                
                result = await self.run_chaos_experiment(experiment)
                results.append(result)
                
            except Exception as e:
                logger.error(f"Experiment {experiment.name} failed: {e}")
        
        # Generate comprehensive report
        await self._generate_chaos_report(results)
        
        return results
    
    async def _generate_chaos_report(self, results: List[ChaosResult]):
        """Generate comprehensive chaos engineering report"""
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        
        # Calculate overall resilience metrics
        total_score = sum(r.resilience_score for r in results)
        avg_score = total_score / len(results) if results else 0
        
        successful_recoveries = len([r for r in results if r.recovery_successful])
        recovery_success_rate = successful_recoveries / len(results) if results else 0
        
        report = {
            'timestamp': datetime.now().isoformat(),
            'total_experiments': len(results),
            'average_resilience_score': avg_score,
            'recovery_success_rate': recovery_success_rate,
            'experiments': [asdict(result) for result in results],
            'summary': {
                'strongest_areas': [],
                'weakest_areas': [],
                'recommendations': []
            }
        }
        
        # Identify strengths and weaknesses
        sorted_results = sorted(results, key=lambda x: x.resilience_score, reverse=True)
        
        if sorted_results:
            best_experiment = sorted_results[0]
            worst_experiment = sorted_results[-1]
            
            report['summary']['strongest_areas'].append(
                f"{best_experiment.experiment.name} (Score: {best_experiment.resilience_score:.1f})"
            )
            
            report['summary']['weakest_areas'].append(
                f"{worst_experiment.experiment.name} (Score: {worst_experiment.resilience_score:.1f})"
            )
        
        # Generate recommendations
        all_lessons = []
        for result in results:
            all_lessons.extend(result.lessons_learned)
        
        # Count most common lessons
        lesson_counts = {}
        for lesson in all_lessons:
            lesson_counts[lesson] = lesson_counts.get(lesson, 0) + 1
        
        top_recommendations = sorted(lesson_counts.items(), key=lambda x: x[1], reverse=True)[:5]
        report['summary']['recommendations'] = [lesson for lesson, count in top_recommendations]
        
        # Save report
        report_dir = Path("tests/reports/chaos")
        report_dir.mkdir(parents=True, exist_ok=True)
        
        json_file = report_dir / f"chaos_report_{timestamp}.json"
        with open(json_file, 'w') as f:
            json.dump(report, f, indent=2, default=str)
        
        # Generate markdown report
        md_report = self._generate_markdown_chaos_report(report)
        md_file = report_dir / f"chaos_report_{timestamp}.md"
        with open(md_file, 'w') as f:
            f.write(md_report)
        
        logger.info(f"Chaos engineering report saved: {json_file}")
        logger.info(f"Overall resilience score: {avg_score:.1f}/10")
    
    def _generate_markdown_chaos_report(self, report: Dict[str, Any]) -> str:
        """Generate markdown chaos engineering report"""
        
        avg_score = report['average_resilience_score']
        status_emoji = "✅" if avg_score >= 7.0 else "⚠️" if avg_score >= 5.0 else "❌"
        
        md_report = f"""# PyAirtable Chaos Engineering Report {status_emoji}

**Generated**: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}

## Executive Summary

- **Total Experiments**: {report['total_experiments']}
- **Average Resilience Score**: {avg_score:.1f}/10 {status_emoji}
- **Recovery Success Rate**: {report['recovery_success_rate']:.1%}

## Resilience Assessment

"""
        
        if avg_score >= 8.0:
            md_report += "🟢 **EXCELLENT** - System demonstrates exceptional resilience\n"
        elif avg_score >= 7.0:
            md_report += "🟡 **GOOD** - System shows good resilience with minor improvements needed\n"
        elif avg_score >= 5.0:
            md_report += "🟠 **MODERATE** - System has moderate resilience, significant improvements needed\n"
        else:
            md_report += "🔴 **POOR** - System resilience is inadequate, critical improvements required\n"
        
        md_report += "\n## Experiment Results\n\n"
        
        for exp_data in report['experiments']:
            exp = exp_data['experiment']
            score = exp_data['resilience_score']
            recovery = "✅" if exp_data['recovery_successful'] else "❌"
            
            md_report += f"### {exp['name']}\n"
            md_report += f"- **Type**: {exp['chaos_type']}\n"
            md_report += f"- **Target**: {exp['target_service']}\n"
            md_report += f"- **Resilience Score**: {score:.1f}/10\n"
            md_report += f"- **Recovery**: {recovery}\n"
            
            if exp_data['recovery_time']:
                md_report += f"- **Recovery Time**: {exp_data['recovery_time']:.1f}s\n"
            
            md_report += f"- **Anomalies**: {len(exp_data['anomalies_detected'])}\n\n"
        
        md_report += "## Key Findings\n\n"
        
        if report['summary']['strongest_areas']:
            md_report += "### Strengths\n"
            for strength in report['summary']['strongest_areas']:
                md_report += f"- ✅ {strength}\n"
            md_report += "\n"
        
        if report['summary']['weakest_areas']:
            md_report += "### Areas for Improvement\n"
            for weakness in report['summary']['weakest_areas']:
                md_report += f"- ❌ {weakness}\n"
            md_report += "\n"
        
        md_report += "## Recommendations\n\n"
        for i, rec in enumerate(report['summary']['recommendations'], 1):
            md_report += f"{i}. {rec}\n"
        
        md_report += "\n## Next Steps\n\n"
        if avg_score >= 7.0:
            md_report += "- Continue regular chaos testing\n"
            md_report += "- Focus on advanced failure scenarios\n"
            md_report += "- Implement automated resilience testing\n"
        else:
            md_report += "- Address critical resilience gaps\n"
            md_report += "- Improve monitoring and alerting\n"
            md_report += "- Implement automated recovery mechanisms\n"
            md_report += "- Re-run chaos tests after improvements\n"
        
        return md_report

# CLI interface
async def run_chaos_suite():
    """Run complete chaos engineering suite"""
    chaos_monkey = ChaosMonkey()
    results = await chaos_monkey.run_full_chaos_suite()
    
    avg_score = sum(r.resilience_score for r in results) / len(results) if results else 0
    
    print(f"\n{'='*60}")
    print("CHAOS ENGINEERING RESULTS")
    print(f"{'='*60}")
    print(f"Experiments: {len(results)}")
    print(f"Average Resilience Score: {avg_score:.1f}/10")
    print(f"Recovery Success Rate: {len([r for r in results if r.recovery_successful])}/{len(results)}")
    print(f"{'='*60}")
    
    return 0 if avg_score >= 7.0 else 1

if __name__ == "__main__":
    exit_code = asyncio.run(run_chaos_suite())
    exit(exit_code)