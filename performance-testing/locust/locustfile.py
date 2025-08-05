"""
Comprehensive Locust Load Testing Suite for PyAirtable Platform
This file defines realistic user behavior patterns and performance scenarios
"""

import json
import random
import time
from datetime import datetime
from typing import Dict, List, Optional

from locust import HttpUser, task, between, events
from locust.env import Environment
from locust.exception import StopUser


class PyAirtableUser(HttpUser):
    """Base user class for PyAirtable performance testing"""
    
    wait_time = between(1, 5)  # Think time between requests
    
    def __init__(self, environment):
        super().__init__(environment)
        self.auth_token: Optional[str] = None
        self.user_id: Optional[str] = None
        self.workspaces: List[Dict] = []
        self.current_workspace: Optional[Dict] = None
        self.current_table: Optional[Dict] = None
        
    def on_start(self):
        """Setup tasks performed when user starts"""
        self.authenticate()
        self.load_user_data()
        
    def authenticate(self):
        """Authenticate user and store auth token"""
        # Select random test user
        users = [
            {"email": "admin@test.com", "password": "admin123", "role": "admin"},
            {"email": "user1@test.com", "password": "user123", "role": "user"},
            {"email": "user2@test.com", "password": "user123", "role": "user"},
            {"email": "power@test.com", "password": "power123", "role": "power_user"},
            {"email": "readonly@test.com", "password": "readonly123", "role": "readonly"},
        ]
        
        user_data = random.choice(users)
        
        with self.client.post(
            "/api/auth/login",
            json={"email": user_data["email"], "password": user_data["password"]},
            headers={"Content-Type": "application/json"},
            catch_response=True,
            name="Authentication"
        ) as response:
            if response.status_code == 200:
                data = response.json()
                self.auth_token = data.get("token")
                self.user_id = data.get("user_id")
                response.success()
            else:
                response.failure(f"Authentication failed: {response.status_code}")
                raise StopUser()
                
    def load_user_data(self):
        """Load user's workspaces and initial data"""
        if not self.auth_token:
            return
            
        headers = {"Authorization": f"Bearer {self.auth_token}"}
        
        # Get user profile
        with self.client.get(
            "/api/users/profile",
            headers=headers,
            catch_response=True,
            name="Get User Profile"
        ) as response:
            if response.status_code != 200:
                response.failure(f"Profile load failed: {response.status_code}")
                
        # Get workspaces
        with self.client.get(
            "/api/workspaces",
            headers=headers,
            catch_response=True,
            name="List Workspaces"
        ) as response:
            if response.status_code == 200:
                data = response.json()
                self.workspaces = data.get("data", [])
                if self.workspaces:
                    self.current_workspace = random.choice(self.workspaces)
                response.success()
            else:
                response.failure(f"Workspace load failed: {response.status_code}")


class RegularUser(PyAirtableUser):
    """Regular user behavior - typical application usage"""
    
    weight = 70  # 70% of users are regular users
    
    @task(30)
    def browse_workspaces(self):
        """Browse and interact with workspaces"""
        if not self.auth_token:
            return
            
        headers = {"Authorization": f"Bearer {self.auth_token}"}
        
        # List workspaces
        self.client.get("/api/workspaces", headers=headers, name="Browse Workspaces")
        
        if self.workspaces:
            workspace = random.choice(self.workspaces)
            
            # Get workspace details
            self.client.get(
                f"/api/workspaces/{workspace['id']}", 
                headers=headers,
                name="Get Workspace Details"
            )
            
            # List tables in workspace
            with self.client.get(
                f"/api/workspaces/{workspace['id']}/tables",
                headers=headers,
                catch_response=True,
                name="List Tables"
            ) as response:
                if response.status_code == 200:
                    tables = response.json().get("data", [])
                    if tables:
                        self.current_table = random.choice(tables)
                        
    @task(25)
    def work_with_records(self):
        """Work with table records - view, create, update"""
        if not self.auth_token or not self.current_workspace or not self.current_table:
            return
            
        headers = {"Authorization": f"Bearer {self.auth_token}"}
        workspace_id = self.current_workspace["id"]
        table_id = self.current_table["id"]
        
        # Get records
        self.client.get(
            f"/api/workspaces/{workspace_id}/tables/{table_id}/records",
            headers=headers,
            name="Get Table Records"
        )
        
        # Create new record (30% chance)
        if random.random() < 0.3:
            record_data = {
                "fields": {
                    "Name": f"Test Record {datetime.now().strftime('%Y%m%d_%H%M%S')}",
                    "Description": "Created by Locust load test",
                    "Status": random.choice(["Active", "Pending", "Completed"]),
                    "Priority": random.randint(1, 5),
                }
            }
            
            with self.client.post(
                f"/api/workspaces/{workspace_id}/tables/{table_id}/records",
                json=record_data,
                headers=headers,
                catch_response=True,
                name="Create Record"
            ) as response:
                if response.status_code == 201:
                    # Update the record immediately (simulate quick edit)
                    record_id = response.json().get("id")
                    if record_id:
                        update_data = {
                            "fields": {
                                "Description": "Updated by Locust load test",
                                "Status": "Updated"
                            }
                        }
                        self.client.patch(
                            f"/api/workspaces/{workspace_id}/tables/{table_id}/records/{record_id}",
                            json=update_data,
                            headers=headers,
                            name="Update Record"
                        )
                        
    @task(15)
    def search_and_analytics(self):
        """Search functionality and analytics dashboard"""
        if not self.auth_token:
            return
            
        headers = {"Authorization": f"Bearer {self.auth_token}"}
        
        # Search query
        search_terms = ["project", "task", "report", "analysis", "data", "test"]
        search_data = {
            "query": random.choice(search_terms),
            "limit": random.randint(10, 50),
            "filters": {"status": "active"} if random.random() > 0.5 else {}
        }
        
        self.client.post(
            "/api/search",
            json=search_data,
            headers=headers,
            name="Search Query"
        )
        
        # Analytics dashboard
        self.client.get("/api/analytics/dashboard", headers=headers, name="Analytics Dashboard")
        
    @task(10)
    def notifications_and_settings(self):
        """Check notifications and settings"""
        if not self.auth_token:
            return
            
        headers = {"Authorization": f"Bearer {self.auth_token}"}
        
        # Get notifications
        self.client.get("/api/notifications", headers=headers, name="Get Notifications")
        
        # Get settings
        self.client.get("/api/settings", headers=headers, name="Get Settings")
        
    @task(5)
    def health_checks(self):
        """Periodic health checks"""
        self.client.get("/api/health", name="Health Check")


class PowerUser(PyAirtableUser):
    """Power user behavior - more intensive operations"""
    
    weight = 15  # 15% of users are power users
    
    @task(20)
    def bulk_operations(self):
        """Perform bulk operations on data"""
        if not self.auth_token or not self.current_workspace or not self.current_table:
            return
            
        headers = {"Authorization": f"Bearer {self.auth_token}"}
        workspace_id = self.current_workspace["id"]
        table_id = self.current_table["id"]
        
        # Bulk create records
        bulk_records = []
        for i in range(random.randint(5, 15)):
            bulk_records.append({
                "fields": {
                    "Name": f"Bulk Record {i}_{datetime.now().strftime('%H%M%S')}",
                    "Description": f"Bulk operation record {i}",
                    "Status": random.choice(["Active", "Pending"]),
                    "Priority": random.randint(1, 5),
                }
            })
        
        self.client.post(
            f"/api/workspaces/{workspace_id}/tables/{table_id}/records/bulk",
            json={"records": bulk_records},
            headers=headers,
            name="Bulk Create Records"
        )
        
    @task(25)
    def complex_queries(self):
        """Execute complex database queries"""
        if not self.auth_token:
            return
            
        headers = {"Authorization": f"Bearer {self.auth_token}"}
        
        # Large dataset query
        self.client.get(
            f"/api/analytics/reports/large-dataset?limit=1000&offset={random.randint(0, 10000)}",
            headers=headers,
            name="Large Dataset Query"
        )
        
        # Aggregation query
        self.client.get(
            "/api/analytics/aggregations?groupBy=status&timeRange=30d",
            headers=headers,
            name="Aggregation Query"
        )
        
        # Full-text search
        search_data = {
            "query": "complex search query with filters",
            "filters": {
                "status": "active",
                "created_date": {"gte": "2024-01-01"},
                "priority": {"in": [3, 4, 5]}
            },
            "limit": 100
        }
        
        self.client.post(
            "/api/search/fulltext",
            json=search_data,
            headers=headers,
            name="Complex Search"
        )
        
    @task(15)
    def export_operations(self):
        """Data export and reporting operations"""
        if not self.auth_token or not self.current_workspace:
            return
            
        headers = {"Authorization": f"Bearer {self.auth_token}"}
        workspace_id = self.current_workspace["id"]
        
        # Export workspace data
        export_params = {
            "format": random.choice(["csv", "xlsx", "json"]),
            "include_metadata": True,
            "date_range": "last_30_days"
        }
        
        self.client.post(
            f"/api/workspaces/{workspace_id}/export",
            json=export_params,
            headers=headers,
            name="Export Data"
        )
        
    @task(10)
    def automation_workflows(self):
        """Interact with automation services"""
        if not self.auth_token:
            return
            
        headers = {"Authorization": f"Bearer {self.auth_token}"}
        
        # List automation workflows
        self.client.get("/api/automation/workflows", headers=headers, name="List Workflows")
        
        # Trigger workflow
        workflow_data = {
            "workflow_id": f"test_workflow_{random.randint(1, 10)}",
            "parameters": {
                "action": "process_data",
                "batch_size": random.randint(100, 1000)
            }
        }
        
        self.client.post(
            "/api/automation/trigger",
            json=workflow_data,
            headers=headers,
            name="Trigger Workflow"
        )


class AdminUser(PyAirtableUser):
    """Admin user behavior - system management operations"""
    
    weight = 5  # 5% of users are admins
    
    @task(20)
    def user_management(self):
        """User and permission management"""
        if not self.auth_token:
            return
            
        headers = {"Authorization": f"Bearer {self.auth_token}"}
        
        # List users
        self.client.get("/api/admin/users", headers=headers, name="List Users")
        
        # Get system stats
        self.client.get("/api/admin/stats", headers=headers, name="System Stats")
        
        # Check permissions
        self.client.get("/api/admin/permissions", headers=headers, name="Check Permissions")
        
    @task(15)
    def system_monitoring(self):
        """System monitoring and health checks"""
        if not self.auth_token:
            return
            
        headers = {"Authorization": f"Bearer {self.auth_token}"}
        
        # System metrics
        self.client.get("/api/admin/metrics", headers=headers, name="System Metrics")
        
        # Service health
        self.client.get("/api/admin/services/health", headers=headers, name="Service Health")
        
        # Performance metrics
        self.client.get("/api/admin/performance", headers=headers, name="Performance Metrics")
        
    @task(10)
    def configuration_management(self):
        """System configuration and settings"""
        if not self.auth_token:
            return
            
        headers = {"Authorization": f"Bearer {self.auth_token}"}
        
        # Get system configuration
        self.client.get("/api/admin/config", headers=headers, name="System Config")
        
        # Update settings (simulation)
        config_data = {
            "max_concurrent_users": random.randint(100, 1000),
            "cache_ttl": random.randint(300, 3600),
            "rate_limit": random.randint(100, 1000)
        }
        
        self.client.patch(
            "/api/admin/config",
            json=config_data,
            headers=headers,
            name="Update Config"
        )


class ReadOnlyUser(PyAirtableUser):
    """Read-only user behavior - browsing and viewing only"""
    
    weight = 10  # 10% of users are read-only
    
    @task(40)
    def browse_data(self):
        """Browse data without modifications"""
        if not self.auth_token:
            return
            
        headers = {"Authorization": f"Bearer {self.auth_token}"}
        
        # Browse workspaces
        self.client.get("/api/workspaces", headers=headers, name="Browse Workspaces")
        
        if self.workspaces:
            workspace = random.choice(self.workspaces)
            
            # View workspace
            self.client.get(
                f"/api/workspaces/{workspace['id']}", 
                headers=headers,
                name="View Workspace"
            )
            
            # View tables
            with self.client.get(
                f"/api/workspaces/{workspace['id']}/tables",
                headers=headers,
                name="View Tables"
            ) as response:
                if response.status_code == 200:
                    tables = response.json().get("data", [])
                    if tables:
                        table = random.choice(tables)
                        
                        # View records
                        self.client.get(
                            f"/api/workspaces/{workspace['id']}/tables/{table['id']}/records",
                            headers=headers,
                            name="View Records"
                        )
                        
    @task(30)
    def search_and_reports(self):
        """Search and view reports"""
        if not self.auth_token:
            return
            
        headers = {"Authorization": f"Bearer {self.auth_token}"}
        
        # Search operations
        search_terms = ["report", "data", "analysis", "summary"]
        search_data = {
            "query": random.choice(search_terms),
            "limit": random.randint(20, 100)
        }
        
        self.client.post(
            "/api/search",
            json=search_data,
            headers=headers,
            name="Search Data"
        )
        
        # View reports
        self.client.get("/api/reports/dashboard", headers=headers, name="View Reports")
        
    @task(20)
    def analytics_viewing(self):
        """View analytics and dashboards"""
        if not self.auth_token:
            return
            
        headers = {"Authorization": f"Bearer {self.auth_token}"}
        
        # Analytics dashboard
        self.client.get("/api/analytics/dashboard", headers=headers, name="View Analytics")
        
        # Charts and visualizations
        self.client.get("/api/analytics/charts", headers=headers, name="View Charts")


# Custom events for detailed monitoring
@events.request.add_listener
def on_request(request_type, name, response_time, response_length, exception, context, **kwargs):
    """Log detailed request information"""
    if exception:
        print(f"Request failed: {name} - {exception}")


@events.test_start.add_listener
def on_test_start(environment, **kwargs):
    """Initialize test environment"""
    print("Starting PyAirtable Performance Test Suite")
    print(f"Target host: {environment.host}")
    print(f"User classes: RegularUser, PowerUser, AdminUser, ReadOnlyUser")


@events.test_stop.add_listener
def on_test_stop(environment, **kwargs):
    """Cleanup and final reporting"""
    print("PyAirtable Performance Test Suite completed")
    
    # Calculate custom metrics
    stats = environment.stats
    total_requests = stats.total.num_requests
    total_failures = stats.total.num_failures
    
    if total_requests > 0:
        error_rate = (total_failures / total_requests) * 100
        print(f"Total requests: {total_requests}")
        print(f"Total failures: {total_failures}")
        print(f"Error rate: {error_rate:.2f}%")
        print(f"Average response time: {stats.total.avg_response_time:.2f}ms")
        print(f"95th percentile: {stats.total.get_response_time_percentile(0.95):.2f}ms")


# Test scenarios for different load types
class StressTestUser(RegularUser):
    """High-intensity user for stress testing"""
    wait_time = between(0.1, 0.5)  # Minimal wait time
    
    @task(50)
    def rapid_requests(self):
        """Make rapid consecutive requests"""
        if not self.auth_token:
            return
            
        headers = {"Authorization": f"Bearer {self.auth_token}"}
        
        # Rapid health checks
        for _ in range(random.randint(5, 10)):
            self.client.get("/api/health", headers=headers, name="Rapid Health Check")
            
        # Rapid API calls
        endpoints = [
            "/api/users/profile",
            "/api/workspaces",
            "/api/notifications",
            "/api/settings"
        ]
        
        for endpoint in random.sample(endpoints, random.randint(2, 4)):
            self.client.get(endpoint, headers=headers, name=f"Rapid API Call")


class SoakTestUser(RegularUser):
    """User for long-running soak tests"""
    wait_time = between(5, 15)  # Longer wait times for soak testing
    
    def on_start(self):
        """Extended initialization for soak testing"""
        super().on_start()
        self.request_count = 0
        self.start_time = time.time()
        
    @task
    def soak_operations(self):
        """Perform consistent operations over long periods"""
        super().browse_workspaces()
        super().work_with_records()
        
        self.request_count += 1
        
        # Log progress every 100 requests
        if self.request_count % 100 == 0:
            elapsed = time.time() - self.start_time
            print(f"Soak test user {self.user_id}: {self.request_count} requests in {elapsed:.1f}s")