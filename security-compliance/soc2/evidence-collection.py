#!/usr/bin/env python3
"""
SOC 2 Evidence Collection Automation

This script automates the collection of evidence for SOC 2 Type II controls,
ensuring comprehensive audit trail generation and compliance monitoring.
"""

import os
import json
import yaml
import logging
import hashlib
import datetime
from typing import Dict, List, Any, Optional
from pathlib import Path
from dataclasses import dataclass, asdict
from enum import Enum
import sqlite3
import asyncio
import aiohttp
import pandas as pd
from cryptography.fernet import Fernet

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/soc2-evidence-collection.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class ControlStatus(Enum):
    IMPLEMENTED = "implemented"
    IN_PROGRESS = "in_progress"
    NOT_IMPLEMENTED = "not_implemented"
    EXCEPTION = "exception"

class EvidenceType(Enum):
    AUTOMATED = "automated"
    MANUAL = "manual"
    SYSTEM_GENERATED = "system_generated"
    DOCUMENT = "document"

@dataclass
class Evidence:
    """Evidence collection record"""
    control_id: str
    evidence_type: EvidenceType
    evidence_data: Dict[str, Any]
    collection_timestamp: datetime.datetime
    collector: str
    hash_value: str
    retention_date: datetime.datetime
    metadata: Dict[str, Any]

@dataclass
class ControlTest:
    """Control testing record"""
    control_id: str
    test_date: datetime.datetime
    test_result: str
    tester: str
    notes: str
    evidence_ids: List[str]
    exceptions: List[str]

class SOC2EvidenceCollector:
    """Main evidence collection class"""
    
    def __init__(self, config_path: str = "soc2-config.yaml"):
        self.config = self._load_config(config_path)
        self.db_path = self.config.get('database_path', 'soc2_evidence.db')
        self.evidence_path = Path(self.config.get('evidence_path', '/secure/evidence'))
        self.encryption_key = self._get_encryption_key()
        self.cipher_suite = Fernet(self.encryption_key)
        self._init_database()
    
    def _load_config(self, config_path: str) -> Dict[str, Any]:
        """Load configuration from YAML file"""
        try:
            with open(config_path, 'r') as f:
                return yaml.safe_load(f)
        except FileNotFoundError:
            logger.warning(f"Config file {config_path} not found, using defaults")
            return self._default_config()
    
    def _default_config(self) -> Dict[str, Any]:
        """Default configuration"""
        return {
            'evidence_retention_years': 7,
            'encryption_enabled': True,
            'auto_collection_enabled': True,
            'collection_frequency': {
                'daily': ['A1.1', 'PI1.1'],
                'weekly': ['CC6.2', 'C1.1'],
                'monthly': ['CC6.1', 'CC6.3', 'A1.2'],
                'quarterly': ['CC2.1', 'CC3.1', 'P1'],
                'annually': ['CC1.1', 'CC1.2', 'CC1.3']
            },
            'system_endpoints': {
                'auth_service': 'http://auth-service:8080',
                'audit_service': 'http://audit-service:8080',
                'monitoring_service': 'http://monitoring-service:8080'
            }
        }
    
    def _get_encryption_key(self) -> bytes:
        """Get or generate encryption key"""
        key_file = Path('.soc2_encryption_key')
        if key_file.exists():
            return key_file.read_bytes()
        else:
            key = Fernet.generate_key()
            key_file.write_bytes(key)
            os.chmod(key_file, 0o600)
            return key
    
    def _init_database(self):
        """Initialize SQLite database for evidence storage"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        # Evidence table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS evidence (
                id TEXT PRIMARY KEY,
                control_id TEXT NOT NULL,
                evidence_type TEXT NOT NULL,
                evidence_data TEXT NOT NULL,
                collection_timestamp TEXT NOT NULL,
                collector TEXT NOT NULL,
                hash_value TEXT NOT NULL,
                retention_date TEXT NOT NULL,
                metadata TEXT,
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP
            )
        ''')
        
        # Control tests table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS control_tests (
                id TEXT PRIMARY KEY,
                control_id TEXT NOT NULL,
                test_date TEXT NOT NULL,
                test_result TEXT NOT NULL,
                tester TEXT NOT NULL,
                notes TEXT,
                evidence_ids TEXT,
                exceptions TEXT,
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP
            )
        ''')
        
        conn.commit()
        conn.close()
    
    def _generate_hash(self, data: str) -> str:
        """Generate SHA-256 hash for evidence integrity"""
        return hashlib.sha256(data.encode()).hexdigest()
    
    def _encrypt_data(self, data: Dict[str, Any]) -> str:
        """Encrypt sensitive evidence data"""
        if self.config.get('encryption_enabled', True):
            json_data = json.dumps(data)
            encrypted_data = self.cipher_suite.encrypt(json_data.encode())
            return encrypted_data.decode()
        return json.dumps(data)
    
    def _decrypt_data(self, encrypted_data: str) -> Dict[str, Any]:
        """Decrypt evidence data"""
        if self.config.get('encryption_enabled', True):
            try:
                decrypted_data = self.cipher_suite.decrypt(encrypted_data.encode())
                return json.loads(decrypted_data.decode())
            except Exception as e:
                logger.error(f"Failed to decrypt data: {e}")
                return {}
        return json.loads(encrypted_data)
    
    async def collect_evidence(self, control_id: str, evidence_type: EvidenceType) -> str:
        """Collect evidence for a specific control"""
        try:
            evidence_data = await self._collect_control_evidence(control_id, evidence_type)
            
            evidence = Evidence(
                control_id=control_id,
                evidence_type=evidence_type,
                evidence_data=evidence_data,
                collection_timestamp=datetime.datetime.utcnow(),
                collector=os.getenv('USER', 'system'),
                hash_value=self._generate_hash(json.dumps(evidence_data)),
                retention_date=datetime.datetime.utcnow() + datetime.timedelta(
                    days=365 * self.config.get('evidence_retention_years', 7)
                ),
                metadata={'collection_method': 'automated', 'version': '1.0'}
            )
            
            evidence_id = self._store_evidence(evidence)
            logger.info(f"Evidence collected for control {control_id}: {evidence_id}")
            return evidence_id
            
        except Exception as e:
            logger.error(f"Failed to collect evidence for control {control_id}: {e}")
            raise
    
    async def _collect_control_evidence(self, control_id: str, evidence_type: EvidenceType) -> Dict[str, Any]:
        """Collect specific evidence based on control ID"""
        evidence_collectors = {
            'CC6.1': self._collect_access_control_evidence,
            'CC6.2': self._collect_mfa_evidence,
            'CC6.3': self._collect_network_access_evidence,
            'CC7.1': self._collect_monitoring_evidence,
            'A1.1': self._collect_availability_evidence,
            'PI1.1': self._collect_processing_integrity_evidence,
            'C1.1': self._collect_confidentiality_evidence,
            'P1': self._collect_privacy_notice_evidence,
            'P2': self._collect_consent_evidence
        }
        
        collector = evidence_collectors.get(control_id, self._collect_generic_evidence)
        return await collector(control_id)
    
    async def _collect_access_control_evidence(self, control_id: str) -> Dict[str, Any]:
        """Collect access control evidence (CC6.1)"""
        async with aiohttp.ClientSession() as session:
            try:
                # Collect user access reviews
                async with session.get(f"{self.config['system_endpoints']['auth_service']}/users") as resp:
                    users = await resp.json()
                
                # Collect role assignments
                async with session.get(f"{self.config['system_endpoints']['auth_service']}/roles") as resp:
                    roles = await resp.json()
                
                # Collect access review logs
                async with session.get(f"{self.config['system_endpoints']['audit_service']}/access-reviews") as resp:
                    access_reviews = await resp.json()
                
                return {
                    'control_id': control_id,
                    'evidence_type': 'access_control_review',
                    'total_users': len(users),
                    'total_roles': len(roles),
                    'recent_access_reviews': len(access_reviews),
                    'users_with_admin_access': len([u for u in users if 'admin' in u.get('roles', [])]),
                    'last_review_date': max([r.get('review_date') for r in access_reviews]) if access_reviews else None,
                    'collection_timestamp': datetime.datetime.utcnow().isoformat()
                }
            except Exception as e:
                logger.error(f"Failed to collect access control evidence: {e}")
                return {'error': str(e), 'control_id': control_id}
    
    async def _collect_mfa_evidence(self, control_id: str) -> Dict[str, Any]:
        """Collect MFA evidence (CC6.2)"""
        async with aiohttp.ClientSession() as session:
            try:
                # Collect MFA enrollment status
                async with session.get(f"{self.config['system_endpoints']['auth_service']}/mfa/status") as resp:
                    mfa_status = await resp.json()
                
                # Collect authentication logs
                async with session.get(f"{self.config['system_endpoints']['audit_service']}/auth-logs") as resp:
                    auth_logs = await resp.json()
                
                mfa_enabled_users = len([u for u in mfa_status if u.get('mfa_enabled', False)])
                total_users = len(mfa_status)
                
                return {
                    'control_id': control_id,
                    'evidence_type': 'mfa_compliance',
                    'total_users': total_users,
                    'mfa_enabled_users': mfa_enabled_users,
                    'mfa_compliance_rate': (mfa_enabled_users / total_users) * 100 if total_users > 0 else 0,
                    'recent_auth_failures': len([log for log in auth_logs if log.get('status') == 'failure']),
                    'collection_timestamp': datetime.datetime.utcnow().isoformat()
                }
            except Exception as e:
                logger.error(f"Failed to collect MFA evidence: {e}")
                return {'error': str(e), 'control_id': control_id}
    
    async def _collect_availability_evidence(self, control_id: str) -> Dict[str, Any]:
        """Collect availability evidence (A1.1)"""
        async with aiohttp.ClientSession() as session:
            try:
                # Collect uptime metrics
                async with session.get(f"{self.config['system_endpoints']['monitoring_service']}/uptime") as resp:
                    uptime_data = await resp.json()
                
                # Collect performance metrics
                async with session.get(f"{self.config['system_endpoints']['monitoring_service']}/performance") as resp:
                    performance_data = await resp.json()
                
                return {
                    'control_id': control_id,
                    'evidence_type': 'availability_metrics',
                    'uptime_percentage': uptime_data.get('uptime_percentage', 0),
                    'average_response_time': performance_data.get('avg_response_time', 0),
                    'incidents_count': len(uptime_data.get('incidents', [])),
                    'sla_compliance': uptime_data.get('sla_compliance', False),
                    'collection_timestamp': datetime.datetime.utcnow().isoformat()
                }
            except Exception as e:
                logger.error(f"Failed to collect availability evidence: {e}")
                return {'error': str(e), 'control_id': control_id}
    
    async def _collect_generic_evidence(self, control_id: str) -> Dict[str, Any]:
        """Generic evidence collection for unmapped controls"""
        return {
            'control_id': control_id,
            'evidence_type': 'generic',
            'status': 'evidence_collected',
            'collection_timestamp': datetime.datetime.utcnow().isoformat(),
            'note': 'Generic evidence collection - manual review required'
        }
    
    def _store_evidence(self, evidence: Evidence) -> str:
        """Store evidence in database"""
        evidence_id = f"{evidence.control_id}_{int(evidence.collection_timestamp.timestamp())}"
        
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        encrypted_data = self._encrypt_data(evidence.evidence_data)
        
        cursor.execute('''
            INSERT INTO evidence (
                id, control_id, evidence_type, evidence_data, collection_timestamp,
                collector, hash_value, retention_date, metadata
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''', (
            evidence_id,
            evidence.control_id,
            evidence.evidence_type.value,
            encrypted_data,
            evidence.collection_timestamp.isoformat(),
            evidence.collector,
            evidence.hash_value,
            evidence.retention_date.isoformat(),
            json.dumps(evidence.metadata)
        ))
        
        conn.commit()
        conn.close()
        
        return evidence_id
    
    def run_control_test(self, control_id: str, test_procedure: str) -> str:
        """Execute control test and record results"""
        try:
            test_result = self._execute_test_procedure(control_id, test_procedure)
            
            test = ControlTest(
                control_id=control_id,
                test_date=datetime.datetime.utcnow(),
                test_result=test_result['status'],
                tester=os.getenv('USER', 'system'),
                notes=test_result.get('notes', ''),
                evidence_ids=test_result.get('evidence_ids', []),
                exceptions=test_result.get('exceptions', [])
            )
            
            test_id = self._store_control_test(test)
            logger.info(f"Control test completed for {control_id}: {test_id}")
            return test_id
            
        except Exception as e:
            logger.error(f"Failed to run control test for {control_id}: {e}")
            raise
    
    def _execute_test_procedure(self, control_id: str, test_procedure: str) -> Dict[str, Any]:
        """Execute specific test procedure"""
        # This would contain the actual test logic
        # For demonstration, returning a sample result
        return {
            'status': 'passed',
            'notes': f'Automated test executed for {control_id}',
            'evidence_ids': [],
            'exceptions': []
        }
    
    def _store_control_test(self, test: ControlTest) -> str:
        """Store control test results"""
        test_id = f"{test.control_id}_test_{int(test.test_date.timestamp())}"
        
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        cursor.execute('''
            INSERT INTO control_tests (
                id, control_id, test_date, test_result, tester,
                notes, evidence_ids, exceptions
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ''', (
            test_id,
            test.control_id,
            test.test_date.isoformat(),
            test.test_result,
            test.tester,
            test.notes,
            json.dumps(test.evidence_ids),
            json.dumps(test.exceptions)
        ))
        
        conn.commit()
        conn.close()
        
        return test_id
    
    async def generate_compliance_report(self, period_start: datetime.datetime, period_end: datetime.datetime) -> Dict[str, Any]:
        """Generate comprehensive compliance report"""
        conn = sqlite3.connect(self.db_path)
        
        # Query evidence and test data
        evidence_df = pd.read_sql_query('''
            SELECT * FROM evidence 
            WHERE collection_timestamp BETWEEN ? AND ?
        ''', conn, params=[period_start.isoformat(), period_end.isoformat()])
        
        tests_df = pd.read_sql_query('''
            SELECT * FROM control_tests 
            WHERE test_date BETWEEN ? AND ?
        ''', conn, params=[period_start.isoformat(), period_end.isoformat()])
        
        conn.close()
        
        # Generate summary statistics
        report = {
            'report_period': {
                'start': period_start.isoformat(),
                'end': period_end.isoformat()
            },
            'evidence_summary': {
                'total_evidence_items': len(evidence_df),
                'controls_with_evidence': evidence_df['control_id'].nunique(),
                'automated_evidence': len(evidence_df[evidence_df['evidence_type'] == 'automated']),
                'manual_evidence': len(evidence_df[evidence_df['evidence_type'] == 'manual'])
            },
            'testing_summary': {
                'total_tests': len(tests_df),
                'passed_tests': len(tests_df[tests_df['test_result'] == 'passed']),
                'failed_tests': len(tests_df[tests_df['test_result'] == 'failed']),
                'controls_tested': tests_df['control_id'].nunique()
            },
            'control_effectiveness': {},
            'exceptions': [],
            'recommendations': []
        }
        
        # Calculate control effectiveness
        for control_id in evidence_df['control_id'].unique():
            control_evidence = evidence_df[evidence_df['control_id'] == control_id]
            control_tests = tests_df[tests_df['control_id'] == control_id]
            
            effectiveness_score = self._calculate_control_effectiveness(control_evidence, control_tests)
            report['control_effectiveness'][control_id] = effectiveness_score
        
        return report
    
    def _calculate_control_effectiveness(self, evidence_df: pd.DataFrame, tests_df: pd.DataFrame) -> Dict[str, Any]:
        """Calculate control effectiveness score"""
        if len(tests_df) == 0:
            return {'score': 0, 'status': 'not_tested', 'evidence_count': len(evidence_df)}
        
        passed_tests = len(tests_df[tests_df['test_result'] == 'passed'])
        total_tests = len(tests_df)
        effectiveness_score = (passed_tests / total_tests) * 100
        
        status = 'effective' if effectiveness_score >= 95 else 'needs_improvement' if effectiveness_score >= 80 else 'ineffective'
        
        return {
            'score': effectiveness_score,
            'status': status,
            'total_tests': total_tests,
            'passed_tests': passed_tests,
            'evidence_count': len(evidence_df)
        }

async def main():
    """Main execution function"""
    collector = SOC2EvidenceCollector()
    
    # Example: Collect evidence for key controls
    key_controls = ['CC6.1', 'CC6.2', 'A1.1', 'PI1.1', 'C1.1']
    
    for control_id in key_controls:
        try:
            evidence_id = await collector.collect_evidence(control_id, EvidenceType.AUTOMATED)
            print(f"Collected evidence for {control_id}: {evidence_id}")
        except Exception as e:
            print(f"Failed to collect evidence for {control_id}: {e}")
    
    # Generate compliance report
    end_date = datetime.datetime.utcnow()
    start_date = end_date - datetime.timedelta(days=30)
    
    report = await collector.generate_compliance_report(start_date, end_date)
    print("\nCompliance Report Summary:")
    print(f"Evidence items: {report['evidence_summary']['total_evidence_items']}")
    print(f"Tests conducted: {report['testing_summary']['total_tests']}")
    print(f"Test pass rate: {report['testing_summary']['passed_tests']}/{report['testing_summary']['total_tests']}")

if __name__ == "__main__":
    asyncio.run(main())