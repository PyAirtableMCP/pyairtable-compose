#!/usr/bin/env python3
"""
OWASP Top 10 Security Framework

Comprehensive security framework implementing OWASP Top 10 vulnerability 
remediation with automated scanning, testing, and compliance monitoring.
"""

import os
import json
import yaml
import logging
import hashlib
import datetime
import subprocess
import asyncio
import aiohttp
import pandas as pd
from typing import Dict, List, Any, Optional, Union
from pathlib import Path
from dataclasses import dataclass, asdict
from enum import Enum
import sqlite3
import xml.etree.ElementTree as ET
from urllib.parse import urlparse, urljoin
import requests
from cryptography.fernet import Fernet
import jwt
import bcrypt
import secrets

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/owasp-security-framework.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class VulnerabilityType(Enum):
    BROKEN_ACCESS_CONTROL = "A01:2021-Broken_Access_Control"
    CRYPTOGRAPHIC_FAILURES = "A02:2021-Cryptographic_Failures"
    INJECTION = "A03:2021-Injection"
    INSECURE_DESIGN = "A04:2021-Insecure_Design"
    SECURITY_MISCONFIGURATION = "A05:2021-Security_Misconfiguration"
    VULNERABLE_COMPONENTS = "A06:2021-Vulnerable_and_Outdated_Components"
    AUTH_FAILURES = "A07:2021-Identification_and_Authentication_Failures"
    INTEGRITY_FAILURES = "A08:2021-Software_and_Data_Integrity_Failures"
    LOGGING_FAILURES = "A09:2021-Security_Logging_and_Monitoring_Failures"
    SSRF = "A10:2021-Server-Side_Request_Forgery"

class SeverityLevel(Enum):
    CRITICAL = "critical"
    HIGH = "high"
    MEDIUM = "medium"
    LOW = "low"
    INFO = "info"

class ScanType(Enum):
    SAST = "static_analysis"
    DAST = "dynamic_analysis"
    SCA = "composition_analysis"
    IAST = "interactive_analysis"
    MANUAL = "manual_testing"

@dataclass
class SecurityVulnerability:
    """Security vulnerability record"""
    vuln_id: str
    vulnerability_type: VulnerabilityType
    severity: SeverityLevel
    title: str
    description: str
    location: str
    scan_type: ScanType
    discovery_date: datetime.datetime
    remediation_status: str
    remediation_date: Optional[datetime.datetime] = None
    false_positive: bool = False
    risk_score: float = 0.0
    cwe_id: Optional[str] = None
    owasp_category: Optional[str] = None

@dataclass
class SecurityScanResult:
    """Security scan execution result"""
    scan_id: str
    scan_type: ScanType
    target: str
    start_time: datetime.datetime
    end_time: datetime.datetime
    status: str
    vulnerabilities_found: int
    critical_count: int
    high_count: int
    medium_count: int
    low_count: int
    scan_data: Dict[str, Any]

class OWASPSecurityFramework:
    """Main OWASP security framework implementation"""
    
    def __init__(self, config_path: str = "owasp-config.yaml"):
        self.config = self._load_config(config_path)
        self.db_path = self.config.get('database_path', 'owasp_security.db')
        self.tools_config = self.config.get('security_tools', {})
        self._init_database()
    
    def _load_config(self, config_path: str) -> Dict[str, Any]:
        """Load OWASP security configuration"""
        try:
            with open(config_path, 'r') as f:
                return yaml.safe_load(f)
        except FileNotFoundError:
            logger.warning(f"Config file {config_path} not found, using defaults")
            return self._default_config()
    
    def _default_config(self) -> Dict[str, Any]:
        """Default OWASP security configuration"""
        return {
            'scan_schedule': {
                'sast': 'daily',
                'dast': 'weekly',
                'sca': 'daily',
                'manual': 'monthly'
            },
            'severity_thresholds': {
                'critical': 0,
                'high': 5,
                'medium': 20,
                'low': 50
            },
            'security_tools': {
                'sonarqube': {
                    'enabled': True,
                    'url': 'http://sonarqube:9000',
                    'token': 'sonar_token'
                },
                'owasp_zap': {
                    'enabled': True,
                    'url': 'http://zap:8080',
                    'api_key': 'zap_api_key'
                },
                'snyk': {
                    'enabled': True,
                    'token': 'snyk_token'
                },
                'dependency_check': {
                    'enabled': True,
                    'nvd_api_key': 'nvd_api_key'
                }
            },
            'compliance_frameworks': ['OWASP_ASVS', 'NIST_CSF', 'ISO_27001']
        }
    
    def _init_database(self):
        """Initialize security vulnerability database"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        # Vulnerabilities table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS vulnerabilities (
                vuln_id TEXT PRIMARY KEY,
                vulnerability_type TEXT NOT NULL,
                severity TEXT NOT NULL,
                title TEXT NOT NULL,
                description TEXT NOT NULL,
                location TEXT NOT NULL,
                scan_type TEXT NOT NULL,
                discovery_date TEXT NOT NULL,
                remediation_status TEXT DEFAULT 'open',
                remediation_date TEXT,
                false_positive BOOLEAN DEFAULT FALSE,
                risk_score REAL DEFAULT 0.0,
                cwe_id TEXT,
                owasp_category TEXT,
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP
            )
        ''')
        
        # Scan results table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS scan_results (
                scan_id TEXT PRIMARY KEY,
                scan_type TEXT NOT NULL,
                target TEXT NOT NULL,
                start_time TEXT NOT NULL,
                end_time TEXT NOT NULL,
                status TEXT NOT NULL,
                vulnerabilities_found INTEGER DEFAULT 0,
                critical_count INTEGER DEFAULT 0,
                high_count INTEGER DEFAULT 0,
                medium_count INTEGER DEFAULT 0,
                low_count INTEGER DEFAULT 0,
                scan_data TEXT,
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP
            )
        ''')
        
        # Security metrics table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS security_metrics (
                metric_id TEXT PRIMARY KEY,
                metric_name TEXT NOT NULL,
                metric_value REAL NOT NULL,
                measurement_date TEXT NOT NULL,
                category TEXT NOT NULL,
                metadata TEXT,
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP
            )
        ''')
        
        conn.commit()
        conn.close()
    
    async def run_sast_scan(self, project_path: str, language: str = "python") -> str:
        """Run Static Application Security Testing (SAST)"""
        try:
            scan_id = f"sast_{int(datetime.datetime.utcnow().timestamp())}"
            start_time = datetime.datetime.utcnow()
            
            logger.info(f"Starting SAST scan: {scan_id}")
            
            # Run multiple SAST tools
            scan_results = {}
            
            # SonarQube scan
            if self.tools_config.get('sonarqube', {}).get('enabled', False):
                sonar_results = await self._run_sonarqube_scan(project_path)
                scan_results['sonarqube'] = sonar_results
            
            # Semgrep scan
            semgrep_results = await self._run_semgrep_scan(project_path, language)
            scan_results['semgrep'] = semgrep_results
            
            # Bandit scan (for Python)
            if language.lower() == 'python':
                bandit_results = await self._run_bandit_scan(project_path)
                scan_results['bandit'] = bandit_results
            
            end_time = datetime.datetime.utcnow()
            
            # Process and store results
            vulnerabilities = await self._process_sast_results(scan_results, scan_id)
            
            # Create scan result record
            scan_result = SecurityScanResult(
                scan_id=scan_id,
                scan_type=ScanType.SAST,
                target=project_path,
                start_time=start_time,
                end_time=end_time,
                status="completed",
                vulnerabilities_found=len(vulnerabilities),
                critical_count=len([v for v in vulnerabilities if v.severity == SeverityLevel.CRITICAL]),
                high_count=len([v for v in vulnerabilities if v.severity == SeverityLevel.HIGH]),
                medium_count=len([v for v in vulnerabilities if v.severity == SeverityLevel.MEDIUM]),
                low_count=len([v for v in vulnerabilities if v.severity == SeverityLevel.LOW]),
                scan_data=scan_results
            )
            
            self._store_scan_result(scan_result)
            
            logger.info(f"SAST scan completed: {scan_id}, found {len(vulnerabilities)} vulnerabilities")
            return scan_id
            
        except Exception as e:
            logger.error(f"SAST scan failed: {e}")
            raise
    
    async def run_dast_scan(self, target_url: str, scan_policy: str = "baseline") -> str:
        """Run Dynamic Application Security Testing (DAST)"""
        try:
            scan_id = f"dast_{int(datetime.datetime.utcnow().timestamp())}"
            start_time = datetime.datetime.utcnow()
            
            logger.info(f"Starting DAST scan: {scan_id} for {target_url}")
            
            # Validate target URL
            if not self._is_valid_scan_target(target_url):
                raise ValueError(f"Invalid or unauthorized scan target: {target_url}")
            
            scan_results = {}
            
            # OWASP ZAP scan
            if self.tools_config.get('owasp_zap', {}).get('enabled', False):
                zap_results = await self._run_zap_scan(target_url, scan_policy)
                scan_results['zap'] = zap_results
            
            # Nuclei scan
            nuclei_results = await self._run_nuclei_scan(target_url)
            scan_results['nuclei'] = nuclei_results
            
            end_time = datetime.datetime.utcnow()
            
            # Process and store results
            vulnerabilities = await self._process_dast_results(scan_results, scan_id)
            
            # Create scan result record
            scan_result = SecurityScanResult(
                scan_id=scan_id,
                scan_type=ScanType.DAST,
                target=target_url,
                start_time=start_time,
                end_time=end_time,
                status="completed",
                vulnerabilities_found=len(vulnerabilities),
                critical_count=len([v for v in vulnerabilities if v.severity == SeverityLevel.CRITICAL]),
                high_count=len([v for v in vulnerabilities if v.severity == SeverityLevel.HIGH]),
                medium_count=len([v for v in vulnerabilities if v.severity == SeverityLevel.MEDIUM]),
                low_count=len([v for v in vulnerabilities if v.severity == SeverityLevel.LOW]),
                scan_data=scan_results
            )
            
            self._store_scan_result(scan_result)
            
            logger.info(f"DAST scan completed: {scan_id}, found {len(vulnerabilities)} vulnerabilities")
            return scan_id
            
        except Exception as e:
            logger.error(f"DAST scan failed: {e}")
            raise
    
    async def run_sca_scan(self, project_path: str, package_manager: str = "pip") -> str:
        """Run Software Composition Analysis (SCA)"""
        try:
            scan_id = f"sca_{int(datetime.datetime.utcnow().timestamp())}"
            start_time = datetime.datetime.utcnow()
            
            logger.info(f"Starting SCA scan: {scan_id}")
            
            scan_results = {}
            
            # Snyk scan
            if self.tools_config.get('snyk', {}).get('enabled', False):
                snyk_results = await self._run_snyk_scan(project_path)
                scan_results['snyk'] = snyk_results
            
            # OWASP Dependency Check
            if self.tools_config.get('dependency_check', {}).get('enabled', False):
                dep_check_results = await self._run_dependency_check(project_path)
                scan_results['dependency_check'] = dep_check_results
            
            # Safety scan (for Python)
            if package_manager == "pip":
                safety_results = await self._run_safety_scan(project_path)
                scan_results['safety'] = safety_results
            
            end_time = datetime.datetime.utcnow()
            
            # Process and store results
            vulnerabilities = await self._process_sca_results(scan_results, scan_id)
            
            # Create scan result record
            scan_result = SecurityScanResult(
                scan_id=scan_id,
                scan_type=ScanType.SCA,
                target=project_path,
                start_time=start_time,
                end_time=end_time,
                status="completed",
                vulnerabilities_found=len(vulnerabilities),
                critical_count=len([v for v in vulnerabilities if v.severity == SeverityLevel.CRITICAL]),
                high_count=len([v for v in vulnerabilities if v.severity == SeverityLevel.HIGH]),
                medium_count=len([v for v in vulnerabilities if v.severity == SeverityLevel.MEDIUM]),
                low_count=len([v for v in vulnerabilities if v.severity == SeverityLevel.LOW]),
                scan_data=scan_results
            )
            
            self._store_scan_result(scan_result)
            
            logger.info(f"SCA scan completed: {scan_id}, found {len(vulnerabilities)} vulnerabilities")
            return scan_id
            
        except Exception as e:
            logger.error(f"SCA scan failed: {e}")
            raise
    
    async def _run_semgrep_scan(self, project_path: str, language: str) -> Dict[str, Any]:
        """Run Semgrep static analysis"""
        try:
            # Prepare Semgrep command
            cmd = [
                "semgrep",
                "--config=auto",
                "--json",
                "--no-rewrite-rule-ids",
                project_path
            ]
            
            # Execute Semgrep
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=1800  # 30 minutes timeout
            )
            
            if result.returncode == 0 or result.returncode == 1:  # 1 means findings found
                scan_data = json.loads(result.stdout) if result.stdout else {"results": []}
                return {
                    "status": "success",
                    "findings": scan_data.get("results", []),
                    "errors": scan_data.get("errors", [])
                }
            else:
                logger.error(f"Semgrep scan failed: {result.stderr}")
                return {"status": "failed", "error": result.stderr}
                
        except Exception as e:
            logger.error(f"Semgrep execution failed: {e}")
            return {"status": "failed", "error": str(e)}
    
    async def _run_bandit_scan(self, project_path: str) -> Dict[str, Any]:
        """Run Bandit Python security analysis"""
        try:
            cmd = [
                "bandit",
                "-r", project_path,
                "-f", "json",
                "-ll"  # Only report medium and high severity
            ]
            
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=900  # 15 minutes timeout
            )
            
            if result.returncode in [0, 1]:
                scan_data = json.loads(result.stdout) if result.stdout else {"results": []}
                return {
                    "status": "success",
                    "findings": scan_data.get("results", []),
                    "metrics": scan_data.get("metrics", {})
                }
            else:
                logger.error(f"Bandit scan failed: {result.stderr}")
                return {"status": "failed", "error": result.stderr}
                
        except Exception as e:
            logger.error(f"Bandit execution failed: {e}")
            return {"status": "failed", "error": str(e)}
    
    async def _run_zap_scan(self, target_url: str, scan_policy: str) -> Dict[str, Any]:
        """Run OWASP ZAP dynamic scan"""
        try:
            zap_config = self.tools_config.get('owasp_zap', {})
            zap_url = zap_config.get('url', 'http://localhost:8080')
            api_key = zap_config.get('api_key', '')
            
            async with aiohttp.ClientSession() as session:
                # Start spider scan
                spider_url = f"{zap_url}/JSON/spider/action/scan/"
                spider_params = {
                    'url': target_url,
                    'apikey': api_key
                }
                
                async with session.get(spider_url, params=spider_params) as resp:
                    spider_result = await resp.json()
                    scan_id = spider_result.get('scan')
                
                # Wait for spider to complete
                await self._wait_for_zap_scan_completion(session, zap_url, api_key, scan_id, 'spider')
                
                # Start active scan
                ascan_url = f"{zap_url}/JSON/ascan/action/scan/"
                ascan_params = {
                    'url': target_url,
                    'apikey': api_key
                }
                
                async with session.get(ascan_url, params=ascan_params) as resp:
                    ascan_result = await resp.json()
                    ascan_id = ascan_result.get('scan')
                
                # Wait for active scan to complete
                await self._wait_for_zap_scan_completion(session, zap_url, api_key, ascan_id, 'ascan')
                
                # Get scan results
                alerts_url = f"{zap_url}/JSON/core/view/alerts/"
                alerts_params = {
                    'baseurl': target_url,
                    'apikey': api_key
                }
                
                async with session.get(alerts_url, params=alerts_params) as resp:
                    alerts_result = await resp.json()
                
                return {
                    "status": "success",
                    "alerts": alerts_result.get('alerts', []),
                    "spider_scan_id": scan_id,
                    "active_scan_id": ascan_id
                }
                
        except Exception as e:
            logger.error(f"ZAP scan failed: {e}")
            return {"status": "failed", "error": str(e)}
    
    async def _run_nuclei_scan(self, target_url: str) -> Dict[str, Any]:
        """Run Nuclei vulnerability scan"""
        try:
            cmd = [
                "nuclei",
                "-u", target_url,
                "-json",
                "-severity", "medium,high,critical",
                "-rate-limit", "10"
            ]
            
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=1800  # 30 minutes timeout
            )
            
            if result.returncode == 0:
                # Parse JSON output (one JSON object per line)
                findings = []
                if result.stdout:
                    for line in result.stdout.strip().split('\n'):
                        if line.strip():
                            try:
                                findings.append(json.loads(line))
                            except json.JSONDecodeError:
                                continue
                
                return {
                    "status": "success",
                    "findings": findings
                }
            else:
                logger.error(f"Nuclei scan failed: {result.stderr}")
                return {"status": "failed", "error": result.stderr}
                
        except Exception as e:
            logger.error(f"Nuclei execution failed: {e}")
            return {"status": "failed", "error": str(e)}
    
    async def _run_snyk_scan(self, project_path: str) -> Dict[str, Any]:
        """Run Snyk dependency vulnerability scan"""
        try:
            snyk_token = self.tools_config.get('snyk', {}).get('token', '')
            
            cmd = [
                "snyk", "test",
                "--json",
                "--all-projects",
                f"--project-path={project_path}"
            ]
            
            env = os.environ.copy()
            env['SNYK_TOKEN'] = snyk_token
            
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=900,  # 15 minutes timeout
                env=env,
                cwd=project_path
            )
            
            if result.stdout:
                try:
                    scan_data = json.loads(result.stdout)
                    return {
                        "status": "success",
                        "vulnerabilities": scan_data.get("vulnerabilities", []),
                        "summary": scan_data.get("summary", {})
                    }
                except json.JSONDecodeError:
                    return {"status": "failed", "error": "Invalid JSON response"}
            else:
                return {"status": "failed", "error": result.stderr}
                
        except Exception as e:
            logger.error(f"Snyk scan failed: {e}")
            return {"status": "failed", "error": str(e)}
    
    def _store_vulnerability(self, vulnerability: SecurityVulnerability):
        """Store vulnerability in database"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        cursor.execute('''
            INSERT OR REPLACE INTO vulnerabilities (
                vuln_id, vulnerability_type, severity, title, description,
                location, scan_type, discovery_date, remediation_status,
                false_positive, risk_score, cwe_id, owasp_category
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''', (
            vulnerability.vuln_id,
            vulnerability.vulnerability_type.value,
            vulnerability.severity.value,
            vulnerability.title,
            vulnerability.description,
            vulnerability.location,
            vulnerability.scan_type.value,
            vulnerability.discovery_date.isoformat(),
            vulnerability.remediation_status,
            vulnerability.false_positive,
            vulnerability.risk_score,
            vulnerability.cwe_id,
            vulnerability.owasp_category
        ))
        
        conn.commit()
        conn.close()
    
    def _store_scan_result(self, scan_result: SecurityScanResult):
        """Store scan result in database"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        cursor.execute('''
            INSERT INTO scan_results (
                scan_id, scan_type, target, start_time, end_time,
                status, vulnerabilities_found, critical_count,
                high_count, medium_count, low_count, scan_data
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''', (
            scan_result.scan_id,
            scan_result.scan_type.value,
            scan_result.target,
            scan_result.start_time.isoformat(),
            scan_result.end_time.isoformat(),
            scan_result.status,
            scan_result.vulnerabilities_found,
            scan_result.critical_count,
            scan_result.high_count,
            scan_result.medium_count,
            scan_result.low_count,
            json.dumps(scan_result.scan_data)
        ))
        
        conn.commit()
        conn.close()
    
    async def generate_security_report(self, 
                                     start_date: datetime.datetime,
                                     end_date: datetime.datetime) -> Dict[str, Any]:
        """Generate comprehensive security report"""
        try:
            conn = sqlite3.connect(self.db_path)
            
            # Get vulnerabilities in date range
            vulns_df = pd.read_sql_query('''
                SELECT * FROM vulnerabilities 
                WHERE discovery_date BETWEEN ? AND ?
            ''', conn, params=[start_date.isoformat(), end_date.isoformat()])
            
            # Get scan results in date range
            scans_df = pd.read_sql_query('''
                SELECT * FROM scan_results 
                WHERE start_time BETWEEN ? AND ?
            ''', conn, params=[start_date.isoformat(), end_date.isoformat()])
            
            conn.close()
            
            # Calculate metrics
            report = {
                "report_period": {
                    "start": start_date.isoformat(),
                    "end": end_date.isoformat()
                },
                "vulnerability_summary": {
                    "total_vulnerabilities": len(vulns_df),
                    "critical": len(vulns_df[vulns_df['severity'] == 'critical']),
                    "high": len(vulns_df[vulns_df['severity'] == 'high']),
                    "medium": len(vulns_df[vulns_df['severity'] == 'medium']),
                    "low": len(vulns_df[vulns_df['severity'] == 'low']),
                    "remediated": len(vulns_df[vulns_df['remediation_status'] == 'fixed']),
                    "open": len(vulns_df[vulns_df['remediation_status'] == 'open'])
                },
                "owasp_top10_breakdown": self._calculate_owasp_breakdown(vulns_df),
                "scan_summary": {
                    "total_scans": len(scans_df),
                    "sast_scans": len(scans_df[scans_df['scan_type'] == 'static_analysis']),
                    "dast_scans": len(scans_df[scans_df['scan_type'] == 'dynamic_analysis']),
                    "sca_scans": len(scans_df[scans_df['scan_type'] == 'composition_analysis'])
                },
                "security_metrics": self._calculate_security_metrics(vulns_df, scans_df),
                "recommendations": self._generate_security_recommendations(vulns_df)
            }
            
            return report
            
        except Exception as e:
            logger.error(f"Failed to generate security report: {e}")
            raise

async def main():
    """Main execution function for testing"""
    framework = OWASPSecurityFramework()
    
    # Example: Run SAST scan
    try:
        project_path = "/app/src"
        sast_scan_id = await framework.run_sast_scan(project_path, "python")
        print(f"SAST scan completed: {sast_scan_id}")
    except Exception as e:
        print(f"SAST scan failed: {e}")
    
    # Example: Run SCA scan
    try:
        sca_scan_id = await framework.run_sca_scan(project_path, "pip")
        print(f"SCA scan completed: {sca_scan_id}")
    except Exception as e:
        print(f"SCA scan failed: {e}")
    
    # Example: Generate security report
    try:
        end_date = datetime.datetime.utcnow()
        start_date = end_date - datetime.timedelta(days=30)
        
        report = await framework.generate_security_report(start_date, end_date)
        print("\nSecurity Report Summary:")
        print(f"Total vulnerabilities: {report['vulnerability_summary']['total_vulnerabilities']}")
        print(f"Critical: {report['vulnerability_summary']['critical']}")
        print(f"High: {report['vulnerability_summary']['high']}")
        print(f"Total scans: {report['scan_summary']['total_scans']}")
    except Exception as e:
        print(f"Report generation failed: {e}")

if __name__ == "__main__":
    asyncio.run(main())