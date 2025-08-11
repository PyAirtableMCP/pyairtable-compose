#!/usr/bin/env python3
"""
GDPR/CCPA Privacy Management System

Comprehensive privacy management system for handling data subject rights,
consent management, breach notification, and compliance monitoring.
"""

import os
import json
import yaml
import logging
import hashlib
import datetime
import uuid
from typing import Dict, List, Any, Optional, Union
from pathlib import Path
from dataclasses import dataclass, asdict
from enum import Enum
import sqlite3
import asyncio
import aiohttp
import pandas as pd
from cryptography.fernet import Fernet
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/privacy-management.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class DataSubjectRight(Enum):
    ACCESS = "access"
    RECTIFICATION = "rectification"
    ERASURE = "erasure"
    RESTRICT_PROCESSING = "restrict_processing"
    DATA_PORTABILITY = "data_portability"
    OBJECT = "object"
    OPT_OUT = "opt_out"  # CCPA

class ConsentStatus(Enum):
    GIVEN = "given"
    WITHDRAWN = "withdrawn"
    EXPIRED = "expired"
    PENDING = "pending"

class ProcessingBasis(Enum):
    CONSENT = "consent"
    CONTRACT = "contract"
    LEGAL_OBLIGATION = "legal_obligation"
    VITAL_INTERESTS = "vital_interests"
    PUBLIC_TASK = "public_task"
    LEGITIMATE_INTERESTS = "legitimate_interests"

class BreachSeverity(Enum):
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"
    CRITICAL = "critical"

@dataclass
class DataSubjectRequest:
    """Data Subject Access Request record"""
    request_id: str
    data_subject_email: str
    request_type: DataSubjectRight
    request_date: datetime.datetime
    description: str
    status: str
    assigned_to: str
    due_date: datetime.datetime
    completed_date: Optional[datetime.datetime] = None
    response_data: Optional[Dict[str, Any]] = None
    verification_status: str = "pending"

@dataclass
class ConsentRecord:
    """Consent management record"""
    consent_id: str
    data_subject_id: str
    purpose: str
    legal_basis: ProcessingBasis
    consent_status: ConsentStatus
    consent_date: datetime.datetime
    expiry_date: Optional[datetime.datetime]
    withdrawal_date: Optional[datetime.datetime]
    consent_method: str
    consent_version: str
    metadata: Dict[str, Any]

@dataclass
class PrivacyBreach:
    """Privacy breach incident record"""
    breach_id: str
    incident_date: datetime.datetime
    discovery_date: datetime.datetime
    breach_type: str
    severity: BreachSeverity
    affected_individuals: int
    data_categories: List[str]
    description: str
    containment_measures: List[str]
    notification_required: bool
    notification_sent: bool
    root_cause: str
    remedial_actions: List[str]

class PrivacyManagementSystem:
    """Main privacy management system"""
    
    def __init__(self, config_path: str = "privacy-config.yaml"):
        self.config = self._load_config(config_path)
        self.db_path = self.config.get('database_path', 'privacy_management.db')
        self.encryption_key = self._get_encryption_key()
        self.cipher_suite = Fernet(self.encryption_key)
        self._init_database()
    
    def _load_config(self, config_path: str) -> Dict[str, Any]:
        """Load privacy configuration"""
        try:
            with open(config_path, 'r') as f:
                return yaml.safe_load(f)
        except FileNotFoundError:
            logger.warning(f"Config file {config_path} not found, using defaults")
            return self._default_config()
    
    def _default_config(self) -> Dict[str, Any]:
        """Default privacy configuration"""
        return {
            'dsar_response_days': 30,
            'ccpa_response_days': 45,
            'breach_notification_hours': 72,
            'consent_renewal_months': 24,
            'retention_periods': {
                'customer_data': 2555,  # 7 years in days
                'marketing_data': 1095,  # 3 years
                'transaction_data': 3650,  # 10 years
                'log_data': 730  # 2 years
            },
            'notification_settings': {
                'smtp_server': 'localhost',
                'smtp_port': 587,
                'from_email': 'privacy@pyairtable.com',
                'dpo_email': 'dpo@pyairtable.com'
            }
        }
    
    def _get_encryption_key(self) -> bytes:
        """Get or generate encryption key for PII protection"""
        key_file = Path('.privacy_encryption_key')
        if key_file.exists():
            return key_file.read_bytes()
        else:
            key = Fernet.generate_key()
            key_file.write_bytes(key)
            os.chmod(key_file, 0o600)
            return key
    
    def _init_database(self):
        """Initialize privacy management database"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        # Data Subject Requests table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS data_subject_requests (
                request_id TEXT PRIMARY KEY,
                data_subject_email TEXT NOT NULL,
                request_type TEXT NOT NULL,
                request_date TEXT NOT NULL,
                description TEXT,
                status TEXT NOT NULL DEFAULT 'received',
                assigned_to TEXT,
                due_date TEXT NOT NULL,
                completed_date TEXT,
                response_data TEXT,
                verification_status TEXT DEFAULT 'pending',
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP
            )
        ''')
        
        # Consent Records table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS consent_records (
                consent_id TEXT PRIMARY KEY,
                data_subject_id TEXT NOT NULL,
                purpose TEXT NOT NULL,
                legal_basis TEXT NOT NULL,
                consent_status TEXT NOT NULL,
                consent_date TEXT NOT NULL,
                expiry_date TEXT,
                withdrawal_date TEXT,
                consent_method TEXT NOT NULL,
                consent_version TEXT NOT NULL,
                metadata TEXT,
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP
            )
        ''')
        
        # Privacy Breaches table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS privacy_breaches (
                breach_id TEXT PRIMARY KEY,
                incident_date TEXT NOT NULL,
                discovery_date TEXT NOT NULL,
                breach_type TEXT NOT NULL,
                severity TEXT NOT NULL,
                affected_individuals INTEGER NOT NULL,
                data_categories TEXT NOT NULL,
                description TEXT NOT NULL,
                containment_measures TEXT,
                notification_required BOOLEAN NOT NULL,
                notification_sent BOOLEAN DEFAULT FALSE,
                root_cause TEXT,
                remedial_actions TEXT,
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP
            )
        ''')
        
        # Data Processing Activities table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS processing_activities (
                activity_id TEXT PRIMARY KEY,
                controller_name TEXT NOT NULL,
                activity_name TEXT NOT NULL,
                purpose TEXT NOT NULL,
                legal_basis TEXT NOT NULL,
                data_categories TEXT NOT NULL,
                data_subjects TEXT NOT NULL,
                recipients TEXT,
                transfers TEXT,
                retention_period TEXT,
                security_measures TEXT,
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                last_updated DATETIME DEFAULT CURRENT_TIMESTAMP
            )
        ''')
        
        conn.commit()
        conn.close()
    
    def _encrypt_pii(self, data: str) -> str:
        """Encrypt personally identifiable information"""
        if data:
            return self.cipher_suite.encrypt(data.encode()).decode()
        return data
    
    def _decrypt_pii(self, encrypted_data: str) -> str:
        """Decrypt personally identifiable information"""
        if encrypted_data:
            try:
                return self.cipher_suite.decrypt(encrypted_data.encode()).decode()
            except Exception as e:
                logger.error(f"Failed to decrypt PII: {e}")
                return ""
        return encrypted_data
    
    async def submit_data_subject_request(self, 
                                        email: str, 
                                        request_type: DataSubjectRight, 
                                        description: str = "") -> str:
        """Submit a new data subject request"""
        try:
            request_id = str(uuid.uuid4())
            request_date = datetime.datetime.utcnow()
            
            # Determine response deadline based on regulation
            response_days = self.config.get('ccpa_response_days', 45) if request_type == DataSubjectRight.OPT_OUT else self.config.get('dsar_response_days', 30)
            due_date = request_date + datetime.timedelta(days=response_days)
            
            request = DataSubjectRequest(
                request_id=request_id,
                data_subject_email=self._encrypt_pii(email),
                request_type=request_type,
                request_date=request_date,
                description=description,
                status="received",
                assigned_to="",
                due_date=due_date
            )
            
            # Store request in database
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            
            cursor.execute('''
                INSERT INTO data_subject_requests (
                    request_id, data_subject_email, request_type, request_date,
                    description, status, due_date
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
            ''', (
                request.request_id,
                request.data_subject_email,
                request.request_type.value,
                request.request_date.isoformat(),
                request.description,
                request.status,
                request.due_date.isoformat()
            ))
            
            conn.commit()
            conn.close()
            
            # Send confirmation email to data subject
            await self._send_request_confirmation(email, request_id, request_type)
            
            # Notify privacy team
            await self._notify_privacy_team("new_request", {
                "request_id": request_id,
                "request_type": request_type.value,
                "email": email,
                "due_date": due_date.isoformat()
            })
            
            logger.info(f"Data subject request submitted: {request_id}")
            return request_id
            
        except Exception as e:
            logger.error(f"Failed to submit data subject request: {e}")
            raise
    
    async def process_access_request(self, request_id: str) -> Dict[str, Any]:
        """Process GDPR Article 15 access request"""
        try:
            # Retrieve request details
            request = self._get_request(request_id)
            if not request or request.request_type != DataSubjectRight.ACCESS:
                raise ValueError("Invalid access request")
            
            email = self._decrypt_pii(request.data_subject_email)
            
            # Collect personal data from all systems
            personal_data = await self._collect_personal_data(email)
            
            # Generate access report
            access_report = {
                "data_subject": email,
                "request_date": request.request_date.isoformat(),
                "data_categories": personal_data.keys(),
                "personal_data": personal_data,
                "processing_purposes": await self._get_processing_purposes(email),
                "retention_periods": self._get_retention_periods(),
                "third_party_recipients": await self._get_third_party_recipients(email),
                "data_sources": await self._get_data_sources(email),
                "rights_information": self._get_rights_information(),
                "contact_information": self._get_contact_information()
            }
            
            # Update request status
            self._update_request_status(request_id, "completed", access_report)
            
            # Send response to data subject
            await self._send_access_response(email, access_report)
            
            logger.info(f"Access request processed: {request_id}")
            return access_report
            
        except Exception as e:
            logger.error(f"Failed to process access request {request_id}: {e}")
            self._update_request_status(request_id, "failed", {"error": str(e)})
            raise
    
    async def process_erasure_request(self, request_id: str) -> bool:
        """Process GDPR Article 17 right to erasure request"""
        try:
            request = self._get_request(request_id)
            if not request or request.request_type != DataSubjectRight.ERASURE:
                raise ValueError("Invalid erasure request")
            
            email = self._decrypt_pii(request.data_subject_email)
            
            # Check if erasure is legally possible
            legal_basis_check = await self._check_erasure_legal_basis(email)
            if not legal_basis_check["can_erase"]:
                self._update_request_status(request_id, "rejected", {
                    "reason": legal_basis_check["reason"],
                    "explanation": legal_basis_check["explanation"]
                })
                await self._send_erasure_rejection(email, legal_basis_check)
                return False
            
            # Perform data erasure across all systems
            erasure_results = await self._execute_data_erasure(email)
            
            # Verify erasure completion
            verification_results = await self._verify_data_erasure(email)
            
            # Update request status
            self._update_request_status(request_id, "completed", {
                "erasure_results": erasure_results,
                "verification_results": verification_results,
                "completion_date": datetime.datetime.utcnow().isoformat()
            })
            
            # Send confirmation to data subject
            await self._send_erasure_confirmation(email, erasure_results)
            
            logger.info(f"Erasure request processed: {request_id}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to process erasure request {request_id}: {e}")
            self._update_request_status(request_id, "failed", {"error": str(e)})
            raise
    
    async def record_consent(self, 
                           data_subject_id: str, 
                           purpose: str, 
                           legal_basis: ProcessingBasis,
                           consent_method: str = "web_form",
                           expiry_months: int = 24) -> str:
        """Record new consent with GDPR compliance"""
        try:
            consent_id = str(uuid.uuid4())
            consent_date = datetime.datetime.utcnow()
            expiry_date = consent_date + datetime.timedelta(days=30 * expiry_months)
            
            consent = ConsentRecord(
                consent_id=consent_id,
                data_subject_id=self._encrypt_pii(data_subject_id),
                purpose=purpose,
                legal_basis=legal_basis,
                consent_status=ConsentStatus.GIVEN,
                consent_date=consent_date,
                expiry_date=expiry_date,
                withdrawal_date=None,
                consent_method=consent_method,
                consent_version="v1.0",
                metadata={
                    "ip_address": "127.0.0.1",  # Should be actual IP
                    "user_agent": "Mozilla/5.0...",  # Should be actual user agent
                    "timestamp": consent_date.isoformat()
                }
            )
            
            # Store consent record
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            
            cursor.execute('''
                INSERT INTO consent_records (
                    consent_id, data_subject_id, purpose, legal_basis,
                    consent_status, consent_date, expiry_date, consent_method,
                    consent_version, metadata
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ''', (
                consent.consent_id,
                consent.data_subject_id,
                consent.purpose,
                consent.legal_basis.value,
                consent.consent_status.value,
                consent.consent_date.isoformat(),
                consent.expiry_date.isoformat() if consent.expiry_date else None,
                consent.consent_method,
                consent.consent_version,
                json.dumps(consent.metadata)
            ))
            
            conn.commit()
            conn.close()
            
            logger.info(f"Consent recorded: {consent_id}")
            return consent_id
            
        except Exception as e:
            logger.error(f"Failed to record consent: {e}")
            raise
    
    async def withdraw_consent(self, data_subject_id: str, purpose: str) -> bool:
        """Process consent withdrawal"""
        try:
            withdrawal_date = datetime.datetime.utcnow()
            encrypted_id = self._encrypt_pii(data_subject_id)
            
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            
            # Update consent status
            cursor.execute('''
                UPDATE consent_records 
                SET consent_status = ?, withdrawal_date = ?
                WHERE data_subject_id = ? AND purpose = ? AND consent_status = ?
            ''', (
                ConsentStatus.WITHDRAWN.value,
                withdrawal_date.isoformat(),
                encrypted_id,
                purpose,
                ConsentStatus.GIVEN.value
            ))
            
            rows_affected = cursor.rowcount
            conn.commit()
            conn.close()
            
            if rows_affected > 0:
                # Stop processing for this purpose
                await self._stop_processing_for_purpose(data_subject_id, purpose)
                
                logger.info(f"Consent withdrawn for {data_subject_id}, purpose: {purpose}")
                return True
            else:
                logger.warning(f"No active consent found for withdrawal: {data_subject_id}, {purpose}")
                return False
                
        except Exception as e:
            logger.error(f"Failed to withdraw consent: {e}")
            raise
    
    async def report_privacy_breach(self, 
                                  breach_type: str,
                                  severity: BreachSeverity,
                                  affected_individuals: int,
                                  data_categories: List[str],
                                  description: str) -> str:
        """Report and manage privacy breach incident"""
        try:
            breach_id = str(uuid.uuid4())
            incident_date = datetime.datetime.utcnow()
            discovery_date = datetime.datetime.utcnow()
            
            # Assess notification requirements
            notification_required = self._assess_breach_notification_requirement(
                severity, affected_individuals, data_categories
            )
            
            breach = PrivacyBreach(
                breach_id=breach_id,
                incident_date=incident_date,
                discovery_date=discovery_date,
                breach_type=breach_type,
                severity=severity,
                affected_individuals=affected_individuals,
                data_categories=data_categories,
                description=description,
                containment_measures=[],
                notification_required=notification_required,
                notification_sent=False,
                root_cause="",
                remedial_actions=[]
            )
            
            # Store breach record
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            
            cursor.execute('''
                INSERT INTO privacy_breaches (
                    breach_id, incident_date, discovery_date, breach_type,
                    severity, affected_individuals, data_categories, description,
                    notification_required
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ''', (
                breach.breach_id,
                breach.incident_date.isoformat(),
                breach.discovery_date.isoformat(),
                breach.breach_type,
                breach.severity.value,
                breach.affected_individuals,
                json.dumps(breach.data_categories),
                breach.description,
                breach.notification_required
            ))
            
            conn.commit()
            conn.close()
            
            # Immediate notification to privacy team
            await self._notify_privacy_team("breach_reported", {
                "breach_id": breach_id,
                "severity": severity.value,
                "affected_individuals": affected_individuals,
                "notification_required": notification_required
            })
            
            # Start 72-hour notification clock if required
            if notification_required:
                await self._schedule_breach_notification(breach_id)
            
            logger.info(f"Privacy breach reported: {breach_id}")
            return breach_id
            
        except Exception as e:
            logger.error(f"Failed to report privacy breach: {e}")
            raise
    
    async def generate_compliance_report(self, 
                                       start_date: datetime.datetime,
                                       end_date: datetime.datetime) -> Dict[str, Any]:
        """Generate comprehensive privacy compliance report"""
        try:
            conn = sqlite3.connect(self.db_path)
            
            # DSAR metrics
            dsar_df = pd.read_sql_query('''
                SELECT * FROM data_subject_requests 
                WHERE request_date BETWEEN ? AND ?
            ''', conn, params=[start_date.isoformat(), end_date.isoformat()])
            
            # Consent metrics
            consent_df = pd.read_sql_query('''
                SELECT * FROM consent_records 
                WHERE consent_date BETWEEN ? AND ?
            ''', conn, params=[start_date.isoformat(), end_date.isoformat()])
            
            # Breach metrics
            breach_df = pd.read_sql_query('''
                SELECT * FROM privacy_breaches 
                WHERE discovery_date BETWEEN ? AND ?
            ''', conn, params=[start_date.isoformat(), end_date.isoformat()])
            
            conn.close()
            
            report = {
                "report_period": {
                    "start": start_date.isoformat(),
                    "end": end_date.isoformat()
                },
                "dsar_metrics": {
                    "total_requests": len(dsar_df),
                    "completed_requests": len(dsar_df[dsar_df['status'] == 'completed']),
                    "pending_requests": len(dsar_df[dsar_df['status'].isin(['received', 'in_progress'])]),
                    "average_response_time": self._calculate_average_response_time(dsar_df),
                    "request_types": dsar_df['request_type'].value_counts().to_dict() if len(dsar_df) > 0 else {}
                },
                "consent_metrics": {
                    "total_consents": len(consent_df),
                    "active_consents": len(consent_df[consent_df['consent_status'] == 'given']),
                    "withdrawn_consents": len(consent_df[consent_df['consent_status'] == 'withdrawn']),
                    "consent_rate": self._calculate_consent_rate(consent_df),
                    "purposes": consent_df['purpose'].value_counts().to_dict() if len(consent_df) > 0 else {}
                },
                "breach_metrics": {
                    "total_breaches": len(breach_df),
                    "high_risk_breaches": len(breach_df[breach_df['severity'].isin(['high', 'critical'])]),
                    "notification_rate": len(breach_df[breach_df['notification_required'] == True]) / len(breach_df) * 100 if len(breach_df) > 0 else 0,
                    "breach_types": breach_df['breach_type'].value_counts().to_dict() if len(breach_df) > 0 else {}
                },
                "compliance_score": self._calculate_compliance_score(dsar_df, consent_df, breach_df),
                "recommendations": self._generate_compliance_recommendations(dsar_df, consent_df, breach_df)
            }
            
            return report
            
        except Exception as e:
            logger.error(f"Failed to generate compliance report: {e}")
            raise
    
    def _calculate_compliance_score(self, dsar_df: pd.DataFrame, consent_df: pd.DataFrame, breach_df: pd.DataFrame) -> Dict[str, Any]:
        """Calculate overall privacy compliance score"""
        score_components = {
            "dsar_compliance": 100 if len(dsar_df) == 0 else (len(dsar_df[dsar_df['status'] == 'completed']) / len(dsar_df)) * 100,
            "consent_management": 100 if len(consent_df) == 0 else (len(consent_df[consent_df['consent_status'] == 'given']) / len(consent_df)) * 100,
            "breach_management": 100 if len(breach_df) == 0 else max(0, 100 - (len(breach_df[breach_df['severity'].isin(['high', 'critical'])]) * 20))
        }
        
        overall_score = sum(score_components.values()) / len(score_components)
        
        return {
            "overall_score": round(overall_score, 2),
            "components": score_components,
            "grade": "A" if overall_score >= 95 else "B" if overall_score >= 85 else "C" if overall_score >= 75 else "D"
        }

async def main():
    """Main execution function for testing"""
    pms = PrivacyManagementSystem()
    
    # Example: Submit a data subject access request
    request_id = await pms.submit_data_subject_request(
        email="test.user@example.com",
        request_type=DataSubjectRight.ACCESS,
        description="I would like to access all my personal data"
    )
    print(f"DSAR submitted: {request_id}")
    
    # Example: Record consent
    consent_id = await pms.record_consent(
        data_subject_id="test.user@example.com",
        purpose="marketing_communications",
        legal_basis=ProcessingBasis.CONSENT
    )
    print(f"Consent recorded: {consent_id}")
    
    # Example: Generate compliance report
    end_date = datetime.datetime.utcnow()
    start_date = end_date - datetime.timedelta(days=30)
    
    report = await pms.generate_compliance_report(start_date, end_date)
    print("\nCompliance Report:")
    print(f"Overall Score: {report['compliance_score']['overall_score']}%")
    print(f"Grade: {report['compliance_score']['grade']}")

if __name__ == "__main__":
    asyncio.run(main())