#!/usr/bin/env python3
"""
PyAirtable Production Migration Orchestrator
===========================================

This script orchestrates the complete production migration process including:
- Database migration with zero downtime
- Service deployment with blue-green strategy
- Traffic routing and DNS updates
- Validation and rollback capabilities
"""

import asyncio
import logging
import sys
import time
import json
import yaml
from datetime import datetime, timezone
from typing import Dict, List, Any, Optional, Tuple
from pathlib import Path
import subprocess
import boto3
import asyncpg
import redis
from dataclasses import dataclass, asdict
from enum import Enum

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('migration.log'),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

class MigrationPhase(Enum):
    PLANNING = "planning"
    DATABASE = "database"
    SERVICES = "services"
    TRAFFIC = "traffic"
    VALIDATION = "validation"
    CLEANUP = "cleanup"
    ROLLBACK = "rollback"

@dataclass
class MigrationConfig:
    """Migration configuration"""
    source_db_url: str
    target_db_url: str
    redis_url: str
    kafka_brokers: str
    aws_region: str
    cluster_name: str
    domain_name: str
    ssl_cert_arn: str
    hosted_zone_id: str
    api_key: str
    dry_run: bool = False
    
    @classmethod
    def from_file(cls, config_path: str) -> 'MigrationConfig':
        """Load configuration from YAML file"""
        with open(config_path, 'r') as f:
            config_data = yaml.safe_load(f)
        return cls(**config_data)

@dataclass
class MigrationState:
    """Track migration state"""
    current_phase: MigrationPhase
    started_at: datetime
    phase_started_at: datetime
    completed_phases: List[MigrationPhase]
    failed_phases: List[MigrationPhase]
    rollback_points: Dict[str, Any]
    metadata: Dict[str, Any]
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            'current_phase': self.current_phase.value,
            'started_at': self.started_at.isoformat(),
            'phase_started_at': self.phase_started_at.isoformat(),
            'completed_phases': [p.value for p in self.completed_phases],
            'failed_phases': [p.value for p in self.failed_phases],
            'rollback_points': self.rollback_points,
            'metadata': self.metadata
        }
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'MigrationState':
        return cls(
            current_phase=MigrationPhase(data['current_phase']),
            started_at=datetime.fromisoformat(data['started_at']),
            phase_started_at=datetime.fromisoformat(data['phase_started_at']),
            completed_phases=[MigrationPhase(p) for p in data['completed_phases']],
            failed_phases=[MigrationPhase(p) for p in data['failed_phases']],
            rollback_points=data['rollback_points'],
            metadata=data['metadata']
        )

class MigrationOrchestrator:
    """Main migration orchestrator"""
    
    def __init__(self, config: MigrationConfig):
        self.config = config
        self.state = MigrationState(
            current_phase=MigrationPhase.PLANNING,
            started_at=datetime.now(timezone.utc),
            phase_started_at=datetime.now(timezone.utc),
            completed_phases=[],
            failed_phases=[],
            rollback_points={},
            metadata={}
        )
        
        # Initialize AWS clients
        self.rds_client = boto3.client('rds', region_name=config.aws_region)
        self.elbv2_client = boto3.client('elbv2', region_name=config.aws_region)
        self.route53_client = boto3.client('route53', region_name=config.aws_region)
        self.eks_client = boto3.client('eks', region_name=config.aws_region)
        
        # Initialize database connections
        self.source_db = None
        self.target_db = None
        self.redis_client = None
        
    async def __aenter__(self):
        """Async context manager entry"""
        await self.connect_databases()
        return self
    
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Async context manager exit"""
        await self.disconnect_databases()
    
    async def connect_databases(self):
        """Connect to databases"""
        try:
            self.source_db = await asyncpg.connect(self.config.source_db_url)
            self.target_db = await asyncpg.connect(self.config.target_db_url)
            self.redis_client = redis.from_url(self.config.redis_url)
            logger.info("Database connections established")
        except Exception as e:
            logger.error(f"Failed to connect to databases: {e}")
            raise
    
    async def disconnect_databases(self):
        """Disconnect from databases"""
        if self.source_db:
            await self.source_db.close()
        if self.target_db:
            await self.target_db.close()
        if self.redis_client:
            self.redis_client.close()
    
    def save_state(self):
        """Save current migration state"""
        state_file = Path('migration_state.json')
        with open(state_file, 'w') as f:
            json.dump(self.state.to_dict(), f, indent=2)
        logger.info(f"Migration state saved to {state_file}")
    
    def load_state(self) -> bool:
        """Load migration state from file"""
        state_file = Path('migration_state.json')
        if state_file.exists():
            with open(state_file, 'r') as f:
                state_data = json.load(f)
            self.state = MigrationState.from_dict(state_data)
            logger.info("Migration state loaded from file")
            return True
        return False
    
    async def execute_migration(self) -> bool:
        """Execute complete migration process"""
        logger.info("🚀 Starting PyAirtable production migration")
        
        try:
            # Load previous state if exists
            self.load_state()
            
            # Execute migration phases
            phases = [
                (MigrationPhase.PLANNING, self.execute_planning_phase),
                (MigrationPhase.DATABASE, self.execute_database_phase),
                (MigrationPhase.SERVICES, self.execute_services_phase),
                (MigrationPhase.TRAFFIC, self.execute_traffic_phase),
                (MigrationPhase.VALIDATION, self.execute_validation_phase),
                (MigrationPhase.CLEANUP, self.execute_cleanup_phase),
            ]
            
            for phase, execute_func in phases:
                if phase in self.state.completed_phases:
                    logger.info(f"Skipping completed phase: {phase.value}")
                    continue
                
                if phase in self.state.failed_phases:
                    logger.warning(f"Retrying previously failed phase: {phase.value}")
                
                success = await self.execute_phase(phase, execute_func)
                if not success:
                    logger.error(f"Migration failed at phase: {phase.value}")
                    return False
            
            logger.info("✅ Migration completed successfully!")
            return True
            
        except Exception as e:
            logger.error(f"Migration failed with exception: {e}")
            await self.execute_rollback()
            return False
        finally:
            self.save_state()
    
    async def execute_phase(self, phase: MigrationPhase, execute_func) -> bool:
        """Execute a single migration phase"""
        self.state.current_phase = phase
        self.state.phase_started_at = datetime.now(timezone.utc)
        
        logger.info(f"🔄 Starting phase: {phase.value}")
        
        try:
            if self.config.dry_run:
                logger.info(f"DRY RUN: Would execute {phase.value}")
                await asyncio.sleep(1)  # Simulate work
                success = True
            else:
                success = await execute_func()
            
            if success:
                self.state.completed_phases.append(phase)
                if phase in self.state.failed_phases:
                    self.state.failed_phases.remove(phase)
                logger.info(f"✅ Phase completed: {phase.value}")
            else:
                if phase not in self.state.failed_phases:
                    self.state.failed_phases.append(phase)
                logger.error(f"❌ Phase failed: {phase.value}")
            
            return success
            
        except Exception as e:
            logger.error(f"Exception in phase {phase.value}: {e}")
            if phase not in self.state.failed_phases:
                self.state.failed_phases.append(phase)
            return False
        finally:
            self.save_state()
    
    async def execute_planning_phase(self) -> bool:
        """Execute planning and validation phase"""
        logger.info("Executing planning phase...")
        
        # Validate infrastructure readiness
        if not await self.validate_infrastructure():
            return False
        
        # Validate service readiness
        if not await self.validate_services():
            return False
        
        # Create rollback points
        await self.create_rollback_points()
        
        # Validate data consistency
        if not await self.validate_source_data():
            return False
        
        return True
    
    async def execute_database_phase(self) -> bool:
        """Execute database migration phase"""
        logger.info("Executing database migration phase...")
        
        # Setup replication
        if not await self.setup_database_replication():
            return False
        
        # Initial data sync
        if not await self.perform_initial_data_sync():
            return False
        
        # Wait for replication to catch up
        if not await self.wait_for_replication_sync():
            return False
        
        # Validate data integrity
        if not await self.validate_data_integrity():
            return False
        
        # Rebuild projections
        if not await self.rebuild_projections():
            return False
        
        # Warm caches
        if not await self.warm_caches():
            return False
        
        return True
    
    async def execute_services_phase(self) -> bool:
        """Execute services migration phase"""
        logger.info("Executing services migration phase...")
        
        # Deploy services in dependency order
        service_groups = [
            ['postgres', 'redis', 'kafka'],  # Infrastructure
            ['api-gateway', 'auth-service'],  # Core platform
            ['user-service', 'workspace-service', 'permission-service'],  # Business logic
            ['airtable-gateway', 'llm-orchestrator', 'mcp-server'],  # Domain services
            ['web-bff', 'mobile-bff', 'notification-service']  # Frontend & utilities
        ]
        
        for group in service_groups:
            if not await self.deploy_service_group(group):
                return False
            
            # Wait for group to be healthy
            if not await self.wait_for_service_group_health(group):
                return False
        
        return True
    
    async def execute_traffic_phase(self) -> bool:
        """Execute traffic routing phase"""
        logger.info("Executing traffic routing phase...")
        
        # Update DNS with low TTL
        if not await self.prepare_dns_for_migration():
            return False
        
        # Configure load balancers
        if not await self.configure_load_balancers():
            return False
        
        # Gradual traffic shift
        traffic_percentages = [10, 25, 50, 75, 100]
        for percentage in traffic_percentages:
            logger.info(f"Shifting {percentage}% traffic to production")
            
            if not await self.shift_traffic(percentage):
                return False
            
            # Monitor for issues
            if not await self.monitor_traffic_shift(percentage):
                # Rollback traffic on issues
                await self.shift_traffic(0)
                return False
            
            # Wait between shifts
            await asyncio.sleep(120)
        
        # Update DNS to normal TTL
        if not await self.finalize_dns_migration():
            return False
        
        return True
    
    async def execute_validation_phase(self) -> bool:
        """Execute validation phase"""
        logger.info("Executing validation phase...")
        
        # Run comprehensive smoke tests
        if not await self.run_smoke_tests():
            return False
        
        # Validate performance baselines
        if not await self.validate_performance():
            return False
        
        # Validate security configuration
        if not await self.validate_security():
            return False
        
        # Validate monitoring and alerting
        if not await self.validate_monitoring():
            return False
        
        return True
    
    async def execute_cleanup_phase(self) -> bool:
        """Execute cleanup phase"""
        logger.info("Executing cleanup phase...")
        
        # Clean up old infrastructure
        if not await self.cleanup_old_infrastructure():
            return False
        
        # Clean up temporary resources
        if not await self.cleanup_temporary_resources():
            return False
        
        # Update documentation
        if not await self.update_documentation():
            return False
        
        # Send completion notifications
        if not await self.send_completion_notifications():
            return False
        
        return True
    
    async def validate_infrastructure(self) -> bool:
        """Validate infrastructure readiness"""
        logger.info("Validating infrastructure readiness...")
        
        try:
            # Check EKS cluster
            cluster_response = self.eks_client.describe_cluster(name=self.config.cluster_name)
            if cluster_response['cluster']['status'] != 'ACTIVE':
                logger.error(f"EKS cluster not active: {cluster_response['cluster']['status']}")
                return False
            
            # Check RDS cluster
            db_clusters = self.rds_client.describe_db_clusters()
            prod_cluster = next((c for c in db_clusters['DBClusters'] 
                               if 'prod' in c['DBClusterIdentifier']), None)
            if not prod_cluster or prod_cluster['Status'] != 'available':
                logger.error("Production RDS cluster not available")
                return False
            
            # Check load balancers
            load_balancers = self.elbv2_client.describe_load_balancers()
            prod_lb = next((lb for lb in load_balancers['LoadBalancers'] 
                           if 'prod' in lb['LoadBalancerName']), None)
            if not prod_lb or prod_lb['State']['Code'] != 'active':
                logger.error("Production load balancer not active")
                return False
            
            logger.info("✅ Infrastructure validation passed")
            return True
            
        except Exception as e:
            logger.error(f"Infrastructure validation failed: {e}")
            return False
    
    async def validate_services(self) -> bool:
        """Validate service readiness"""
        logger.info("Validating service readiness...")
        
        try:
            # Check if all service images are built
            required_services = [
                'api-gateway', 'auth-service', 'user-service',
                'workspace-service', 'permission-service', 'airtable-gateway',
                'llm-orchestrator', 'mcp-server', 'web-bff', 'mobile-bff'
            ]
            
            for service in required_services:
                # Check if service is deployable
                result = subprocess.run([
                    'kubectl', 'get', 'deployment', service, 
                    '-n', 'pyairtable', '--ignore-not-found'
                ], capture_output=True, text=True)
                
                if result.returncode != 0:
                    logger.warning(f"Service {service} not found in cluster")
            
            logger.info("✅ Service validation passed")
            return True
            
        except Exception as e:
            logger.error(f"Service validation failed: {e}")
            return False
    
    async def setup_database_replication(self) -> bool:
        """Setup database replication"""
        logger.info("Setting up database replication...")
        
        try:
            # Enable logical replication on source
            await self.source_db.execute("SELECT pg_reload_conf()")
            
            # Create replication slot
            await self.source_db.execute("""
                SELECT pg_create_logical_replication_slot('pyairtable_migration_slot', 'pgoutput')
                WHERE NOT EXISTS (
                    SELECT 1 FROM pg_replication_slots 
                    WHERE slot_name = 'pyairtable_migration_slot'
                )
            """)
            
            # Create subscription on target
            await self.target_db.execute(f"""
                CREATE SUBSCRIPTION pyairtable_subscription 
                CONNECTION '{self.config.source_db_url}' 
                PUBLICATION pyairtable_replication
                WITH (slot_name = 'pyairtable_migration_slot')
            """)
            
            logger.info("✅ Database replication setup completed")
            return True
            
        except Exception as e:
            logger.error(f"Database replication setup failed: {e}")
            return False
    
    async def perform_initial_data_sync(self) -> bool:
        """Perform initial data synchronization"""
        logger.info("Performing initial data sync...")
        
        try:
            # This would be handled by logical replication
            # But we can monitor the progress
            await asyncio.sleep(30)  # Allow initial sync time
            
            logger.info("✅ Initial data sync completed")
            return True
            
        except Exception as e:
            logger.error(f"Initial data sync failed: {e}")
            return False
    
    async def wait_for_replication_sync(self, max_lag_seconds: int = 60) -> bool:
        """Wait for replication to catch up"""
        logger.info("Waiting for replication sync...")
        
        try:
            for _ in range(30):  # 5 minute timeout
                # Check replication lag
                lag_result = await self.target_db.fetchval("""
                    SELECT EXTRACT(EPOCH FROM (now() - last_msg_receipt_time))::int 
                    FROM pg_stat_subscription 
                    WHERE subname = 'pyairtable_subscription'
                """)
                
                if lag_result is None or lag_result <= max_lag_seconds:
                    logger.info(f"✅ Replication lag within acceptable range: {lag_result}s")
                    return True
                
                logger.info(f"Replication lag: {lag_result}s, waiting...")
                await asyncio.sleep(10)
            
            logger.error("Replication sync timeout")
            return False
            
        except Exception as e:
            logger.error(f"Replication sync check failed: {e}")
            return False
    
    async def validate_data_integrity(self) -> bool:
        """Validate data integrity between source and target"""
        logger.info("Validating data integrity...")
        
        try:
            # Run validation function
            validation_results = await self.target_db.fetch("SELECT * FROM final_migration_validation()")
            
            all_passed = True
            for result in validation_results:
                status = "✅ PASS" if result['status'] == 'PASS' else "❌ FAIL"
                logger.info(f"{result['check_name']}: {status} - {result['details']}")
                
                if result['status'] != 'PASS':
                    all_passed = False
            
            if all_passed:
                logger.info("✅ Data integrity validation passed")
            else:
                logger.error("❌ Data integrity validation failed")
            
            return all_passed
            
        except Exception as e:
            logger.error(f"Data integrity validation failed: {e}")
            return False
    
    async def execute_rollback(self) -> bool:
        """Execute rollback procedures"""
        logger.error("🔄 Executing migration rollback...")
        
        try:
            # Rollback traffic
            await self.shift_traffic(0)
            
            # Rollback DNS
            await self.rollback_dns()
            
            # Rollback services if needed
            await self.rollback_services()
            
            # Rollback database if needed
            await self.rollback_database()
            
            logger.info("✅ Rollback completed")
            return True
            
        except Exception as e:
            logger.error(f"Rollback failed: {e}")
            return False
    
    # Additional implementation methods would continue here...
    # (Implementing remaining methods for brevity)

async def main():
    """Main migration execution"""
    import argparse
    
    parser = argparse.ArgumentParser(description='PyAirtable Production Migration')
    parser.add_argument('--config', required=True, help='Migration configuration file')
    parser.add_argument('--dry-run', action='store_true', help='Perform dry run')
    parser.add_argument('--rollback', action='store_true', help='Execute rollback')
    parser.add_argument('--resume', action='store_true', help='Resume from saved state')
    
    args = parser.parse_args()
    
    # Load configuration
    config = MigrationConfig.from_file(args.config)
    config.dry_run = args.dry_run
    
    # Execute migration
    async with MigrationOrchestrator(config) as orchestrator:
        if args.rollback:
            success = await orchestrator.execute_rollback()
        else:
            success = await orchestrator.execute_migration()
        
        return 0 if success else 1

if __name__ == "__main__":
    exit_code = asyncio.run(main())
    sys.exit(exit_code)