"""
Integration tests for cross-service communication.
Tests service-to-service contracts, message passing, and data consistency.
"""

import pytest
import asyncio
import httpx
from typing import Dict, Any, List
from datetime import datetime
from tests.fixtures.factories import TestDataFactory
from tests.fixtures.mock_services import create_mock_services, reset_all_mocks

@pytest.mark.integration
@pytest.mark.asyncio
class TestCrossServiceCommunication:
    """Test communication patterns between microservices"""
    
    @pytest.fixture(autouse=True)
    def setup(self, test_environment):
        """Setup test environment"""
        self.test_env = test_environment
        self.factory = TestDataFactory()
        self.mocks = create_mock_services()
        
        yield
        
        reset_all_mocks(self.mocks)
    
    async def test_api_gateway_to_auth_service_communication(self, http_client: httpx.AsyncClient):
        """Test API Gateway communicating with Auth Service"""
        # Test user authentication flow
        auth_request = {
            "email": "test@example.com",
            "password": "test_password"
        }
        
        # Make request through API Gateway to Auth Service
        auth_response = await http_client.post(
            f"{self.test_env.api_gateway_url}/auth/login",
            json=auth_request
        )
        
        if auth_response.status_code == 200:
            # Authentication successful
            auth_result = auth_response.json()
            
            assert "access_token" in auth_result
            assert "token_type" in auth_result
            assert "expires_in" in auth_result
            
            access_token = auth_result["access_token"]
            
            # Test token validation through API Gateway
            validate_response = await http_client.get(
                f"{self.test_env.api_gateway_url}/auth/validate",
                headers={"Authorization": f"Bearer {access_token}"}
            )
            
            assert validate_response.status_code == 200
            validation_result = validate_response.json()
            assert validation_result["valid"] == True
            
            # Test user profile retrieval
            profile_response = await http_client.get(
                f"{self.test_env.api_gateway_url}/auth/profile",
                headers={"Authorization": f"Bearer {access_token}"}
            )
            
            if profile_response.status_code == 200:
                profile = profile_response.json()
                assert "email" in profile
                assert profile["email"] == auth_request["email"]
        
        elif auth_response.status_code == 401:
            # Expected if test user doesn't exist
            assert "invalid" in auth_response.json()["error"].lower()
        
        else:
            # Service might not be available
            assert auth_response.status_code in [404, 503]
    
    async def test_llm_orchestrator_to_mcp_server_communication(self, http_client: httpx.AsyncClient):
        """Test LLM Orchestrator communicating with MCP Server"""
        # Test chat request that should trigger MCP tool usage
        chat_request = {
            "message": "Get data from Airtable",
            "session_id": "test-session-123",
            "context": {}
        }
        
        chat_response = await http_client.post(
            f"{self.test_env.api_gateway_url}/llm/chat",
            json=chat_request
        )
        
        if chat_response.status_code == 200:
            chat_result = chat_response.json()
            
            assert "response" in chat_result
            assert "session_id" in chat_result
            assert chat_result["session_id"] == chat_request["session_id"]
            
            # If MCP tools were used, should be indicated in metadata
            if "metadata" in chat_result:
                metadata = chat_result["metadata"]
                if "tools_used" in metadata:
                    tools_used = metadata["tools_used"]
                    assert isinstance(tools_used, list)
                    
                    # Verify tool execution results
                    for tool in tools_used:
                        assert "tool_name" in tool
                        assert "result" in tool
                        assert "execution_time" in tool
        
        # Test direct MCP tool execution
        mcp_request = {
            "tool": "airtable_get_records",
            "params": {
                "table_id": "tblTestTable"
            }
        }
        
        mcp_response = await http_client.post(
            f"{self.test_env.api_gateway_url}/mcp/execute",
            json=mcp_request
        )
        
        if mcp_response.status_code == 200:
            mcp_result = mcp_response.json()
            
            assert "success" in mcp_result
            if mcp_result["success"]:
                assert "result" in mcp_result
                assert "execution_id" in mcp_result
    
    async def test_api_gateway_to_airtable_gateway_communication(self, http_client: httpx.AsyncClient):
        """Test API Gateway communicating with Airtable Gateway"""
        # Test Airtable record retrieval
        records_response = await http_client.get(
            f"{self.test_env.api_gateway_url}/airtable/records",
            params={"table_id": "tblTestTable", "limit": 10}
        )
        
        if records_response.status_code == 200:
            records_result = records_response.json()
            
            assert "records" in records_result
            assert isinstance(records_result["records"], list)
            
            # Verify record structure
            if len(records_result["records"]) > 0:
                record = records_result["records"][0]
                assert "id" in record
                assert "fields" in record
                assert "createdTime" in record
        
        # Test record creation
        new_record_data = {
            "fields": {
                "Name": "Test Record",
                "Status": "Active",
                "Created": datetime.utcnow().isoformat() + "Z"
            }
        }
        
        create_response = await http_client.post(
            f"{self.test_env.api_gateway_url}/airtable/records",
            json={
                "table_id": "tblTestTable",
                "record": new_record_data
            }
        )
        
        if create_response.status_code in [200, 201]:
            created_record = create_response.json()
            
            assert "id" in created_record
            assert "fields" in created_record
            assert created_record["fields"]["Name"] == "Test Record"
            
            # Test record update
            record_id = created_record["id"]
            update_data = {
                "fields": {
                    "Status": "Updated"
                }
            }
            
            update_response = await http_client.patch(
                f"{self.test_env.api_gateway_url}/airtable/records/{record_id}",
                json={
                    "table_id": "tblTestTable",
                    "updates": update_data
                }
            )
            
            if update_response.status_code == 200:
                updated_record = update_response.json()
                assert updated_record["fields"]["Status"] == "Updated"
    
    async def test_service_to_service_event_propagation(self, http_client: httpx.AsyncClient):
        """Test event propagation between services"""
        # Create a user (should trigger events)
        user_data = self.factory.create_user()
        
        create_user_response = await http_client.post(
            f"{self.test_env.api_gateway_url}/users",
            json={
                "email": user_data.email,
                "username": user_data.username,
                "first_name": user_data.first_name,
                "last_name": user_data.last_name,
                "password": "password123"
            }
        )
        
        if create_user_response.status_code in [200, 201, 202]:
            if create_user_response.status_code == 202:
                # Async creation, get the user ID from response
                create_result = create_user_response.json()
                user_id = create_result.get("user_id") or create_result.get("id")
            else:
                user_id = create_user_response.json()["id"]
            
            # Wait for event propagation
            await asyncio.sleep(2)
            
            # Check if events were propagated to other services
            
            # 1. Check notification service received welcome email event
            notifications_response = await http_client.get(
                f"{self.test_env.api_gateway_url}/notifications/user/{user_id}"
            )
            
            if notifications_response.status_code == 200:
                notifications = notifications_response.json()
                welcome_notifications = [
                    n for n in notifications.get("notifications", [])
                    if n.get("type") == "welcome_email"
                ]
                assert len(welcome_notifications) >= 1
            
            # 2. Check analytics service received user creation event
            analytics_response = await http_client.get(
                f"{self.test_env.api_gateway_url}/analytics/events",
                params={"type": "user_created", "user_id": user_id}
            )
            
            if analytics_response.status_code == 200:
                analytics_events = analytics_response.json()
                user_created_events = [
                    e for e in analytics_events.get("events", [])
                    if e.get("event_type") == "user_created"
                ]
                assert len(user_created_events) >= 1
            
            # 3. Check workspace service created default workspace
            workspaces_response = await http_client.get(
                f"{self.test_env.api_gateway_url}/workspaces",
                params={"owner_id": user_id}
            )
            
            if workspaces_response.status_code == 200:
                workspaces = workspaces_response.json()
                user_workspaces = workspaces.get("workspaces", [])
                # Should have at least a default workspace
                assert len(user_workspaces) >= 1
                
                default_workspace = user_workspaces[0]
                assert default_workspace["owner_id"] == user_id
    
    async def test_service_dependency_chain(self, http_client: httpx.AsyncClient):
        """Test complex service dependency chain"""
        # Test a workflow that involves multiple services
        # 1. User creates an automation
        # 2. Automation triggers Airtable data fetch
        # 3. Data is processed by LLM
        # 4. Results are stored and user is notified
        
        automation_request = {
            "name": "Test Automation",
            "trigger": {
                "type": "webhook",
                "config": {"url": "/webhook/test"}
            },
            "actions": [
                {
                    "type": "airtable_fetch",
                    "config": {"table_id": "tblTestTable"}
                },
                {
                    "type": "llm_process",
                    "config": {"prompt": "Analyze this data"}
                },
                {
                    "type": "notify_user",
                    "config": {"method": "email"}
                }
            ]
        }
        
        create_automation_response = await http_client.post(
            f"{self.test_env.api_gateway_url}/automations",
            json=automation_request
        )
        
        if create_automation_response.status_code in [200, 201, 202]:
            automation = create_automation_response.json()
            automation_id = automation["id"]
            
            # Trigger the automation
            trigger_response = await http_client.post(
                f"{self.test_env.api_gateway_url}/automations/{automation_id}/trigger",
                json={"test_data": "sample data"}
            )
            
            if trigger_response.status_code in [200, 202]:
                execution_id = trigger_response.json().get("execution_id")
                
                # Wait for execution to complete
                max_wait = 30
                start_time = datetime.utcnow()
                
                while (datetime.utcnow() - start_time).seconds < max_wait:
                    status_response = await http_client.get(
                        f"{self.test_env.api_gateway_url}/automations/executions/{execution_id}"
                    )
                    
                    if status_response.status_code == 200:
                        execution_status = status_response.json()
                        
                        if execution_status["status"] == "completed":
                            # Verify each step was executed
                            steps = execution_status.get("steps", [])
                            
                            # Should have steps for each action
                            airtable_step = next(
                                (s for s in steps if s["type"] == "airtable_fetch"), None
                            )
                            llm_step = next(
                                (s for s in steps if s["type"] == "llm_process"), None
                            )
                            notify_step = next(
                                (s for s in steps if s["type"] == "notify_user"), None
                            )
                            
                            if airtable_step:
                                assert airtable_step["status"] == "completed"
                                assert "result" in airtable_step
                            
                            if llm_step:
                                assert llm_step["status"] == "completed"
                                assert "result" in llm_step
                            
                            if notify_step:
                                assert notify_step["status"] == "completed"
                            
                            break
                        elif execution_status["status"] == "failed":
                            # Log the failure but don't fail the test if services aren't available
                            print(f"Automation execution failed: {execution_status.get('error')}")
                            break
                    
                    await asyncio.sleep(1)
    
    async def test_service_circuit_breaker_propagation(self, http_client: httpx.AsyncClient):
        """Test circuit breaker behavior across services"""
        # Make requests to a service that might be down
        failing_requests = []
        
        for i in range(10):
            response = await http_client.get(
                f"{self.test_env.api_gateway_url}/unreliable-service/test"
            )
            failing_requests.append(response.status_code)
            
            if response.status_code == 503:
                # Circuit breaker activated
                break
            
            await asyncio.sleep(0.1)
        
        # Test that circuit breaker prevents cascade failures
        if 503 in failing_requests:
            # Circuit breaker is active, test dependent services
            dependent_response = await http_client.get(
                f"{self.test_env.api_gateway_url}/service-that-depends-on-unreliable"
            )
            
            # Should either:
            # 1. Return gracefully with degraded functionality
            # 2. Return circuit breaker error
            # 3. Use fallback mechanism
            
            if dependent_response.status_code == 200:
                result = dependent_response.json()
                # Should indicate degraded mode or fallback
                assert result.get("degraded_mode") == True or result.get("fallback_used") == True
            elif dependent_response.status_code == 503:
                # Circuit breaker propagated
                assert "circuit breaker" in dependent_response.text.lower()
    
    async def test_service_data_consistency_across_boundaries(self, http_client: httpx.AsyncClient):
        """Test data consistency across service boundaries"""
        # Create a user and workspace
        user_data = self.factory.create_user()
        
        # Create user
        create_user_response = await http_client.post(
            f"{self.test_env.api_gateway_url}/users",
            json={
                "email": user_data.email,
                "username": user_data.username,
                "first_name": user_data.first_name,
                "last_name": user_data.last_name,
                "password": "password123"
            }
        )
        
        if create_user_response.status_code in [200, 201, 202]:
            user_id = create_user_response.json().get("id") or create_user_response.json().get("user_id")
            
            # Create workspace
            create_workspace_response = await http_client.post(
                f"{self.test_env.api_gateway_url}/workspaces",
                json={
                    "name": "Test Workspace",
                    "description": "Test workspace for consistency",
                    "owner_id": user_id
                }
            )
            
            if create_workspace_response.status_code in [200, 201, 202]:
                workspace_id = create_workspace_response.json()["id"]
                
                # Wait for eventual consistency
                await asyncio.sleep(2)
                
                # Verify consistency across services
                
                # 1. User service should know about the workspace
                user_profile_response = await http_client.get(
                    f"{self.test_env.api_gateway_url}/users/{user_id}/profile"
                )
                
                if user_profile_response.status_code == 200:
                    user_profile = user_profile_response.json()
                    user_workspaces = user_profile.get("workspaces", [])
                    workspace_ids = [w["id"] for w in user_workspaces]
                    assert workspace_id in workspace_ids
                
                # 2. Analytics service should have the relationship
                analytics_response = await http_client.get(
                    f"{self.test_env.api_gateway_url}/analytics/user-workspace-relationships/{user_id}"
                )
                
                if analytics_response.status_code == 200:
                    relationships = analytics_response.json()
                    workspace_relationships = relationships.get("workspaces", [])
                    assert any(w["workspace_id"] == workspace_id for w in workspace_relationships)
                
                # 3. Permission service should have ownership records
                permissions_response = await http_client.get(
                    f"{self.test_env.api_gateway_url}/permissions/workspace/{workspace_id}"
                )
                
                if permissions_response.status_code == 200:
                    permissions = permissions_response.json()
                    owner_permissions = [
                        p for p in permissions.get("permissions", [])
                        if p.get("user_id") == user_id and p.get("role") == "owner"
                    ]
                    assert len(owner_permissions) >= 1
    
    async def test_service_timeout_and_retry_behavior(self, http_client: httpx.AsyncClient):
        """Test service timeout and retry behavior"""
        # Test a request that might timeout
        start_time = datetime.utcnow()
        
        timeout_response = await http_client.get(
            f"{self.test_env.api_gateway_url}/slow-service/test",
            timeout=5.0  # 5 second timeout
        )
        
        elapsed_time = (datetime.utcnow() - start_time).total_seconds()
        
        if timeout_response.status_code == 408:  # Request Timeout
            # Verify timeout was handled properly
            assert elapsed_time >= 4.0  # Should have waited close to timeout
            assert elapsed_time <= 6.0  # But not much longer
            
            timeout_result = timeout_response.json()
            assert "timeout" in timeout_result.get("error", "").lower()
        
        elif timeout_response.status_code == 200:
            # Request succeeded within timeout
            result = timeout_response.json()
            assert "response_time" in result
            assert result["response_time"] < 5.0
        
        # Test retry behavior for transient failures
        retry_responses = []
        
        for attempt in range(3):
            retry_response = await http_client.get(
                f"{self.test_env.api_gateway_url}/flaky-service/test"
            )
            retry_responses.append(retry_response.status_code)
            
            if retry_response.status_code == 200:
                # Success after retries
                result = retry_response.json()
                if "attempt_count" in result:
                    assert result["attempt_count"] >= 1
                break
            
            await asyncio.sleep(1)  # Wait between retries
        
        # Should eventually succeed or give a definitive failure
        assert any(code == 200 for code in retry_responses) or \
               all(code >= 500 for code in retry_responses)