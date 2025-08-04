"""
End-to-end tests for Unit of Work pattern implementation.
Tests transaction boundary management and data consistency.
"""

import pytest
import asyncio
import httpx
from typing import Dict, Any, List
from datetime import datetime
from tests.fixtures.factories import TestDataFactory
from tests.fixtures.mock_services import create_mock_services, reset_all_mocks

@pytest.mark.e2e
@pytest.mark.asyncio
class TestUnitOfWork:
    """Test Unit of Work pattern for transaction management"""
    
    @pytest.fixture(autouse=True)
    def setup(self, test_environment):
        """Setup test environment"""
        self.test_env = test_environment
        self.factory = TestDataFactory()
        self.mocks = create_mock_services()
        
        # Unit of Work endpoints
        self.uow_url = f"{test_environment.api_gateway_url}/unit-of-work"
        self.commands_url = f"{test_environment.api_gateway_url}/commands"
        self.transactions_url = f"{test_environment.api_gateway_url}/transactions"
        
        yield
        
        reset_all_mocks(self.mocks)
    
    async def test_successful_unit_of_work_commit(self, http_client: httpx.AsyncClient):
        """Test successful Unit of Work transaction with multiple operations"""
        # Arrange
        user_data = self.factory.create_user()
        workspace_data = self.factory.create_workspace()
        
        # Start Unit of Work transaction
        uow_start_response = await http_client.post(
            f"{self.uow_url}/begin",
            json={
                "transaction_id": f"tx_{user_data.id}",
                "operations": [
                    {
                        "type": "CREATE_USER",
                        "entity": "User",
                        "data": {
                            "email": user_data.email,
                            "username": user_data.username,
                            "first_name": user_data.first_name,
                            "last_name": user_data.last_name,
                            "password": "password123"
                        }
                    },
                    {
                        "type": "CREATE_WORKSPACE",
                        "entity": "Workspace",
                        "data": {
                            "name": workspace_data.name,
                            "description": workspace_data.description,
                            "owner_id": "${USER_ID}"  # Will be resolved from first operation
                        },
                        "depends_on": ["CREATE_USER"]
                    },
                    {
                        "type": "SEND_NOTIFICATION",
                        "entity": "Notification",
                        "data": {
                            "type": "welcome_email",
                            "recipient": user_data.email,
                            "user_id": "${USER_ID}",
                            "workspace_id": "${WORKSPACE_ID}"
                        },
                        "depends_on": ["CREATE_USER", "CREATE_WORKSPACE"]
                    }
                ],
                "timeout": 30
            }
        )
        
        assert uow_start_response.status_code == 202
        transaction_id = uow_start_response.json()["transaction_id"]
        
        # Wait for transaction completion
        completion_timeout = 35
        start_time = datetime.utcnow()
        
        while True:
            status_response = await http_client.get(
                f"{self.uow_url}/status/{transaction_id}"
            )
            assert status_response.status_code == 200
            
            status = status_response.json()
            
            if status["status"] == "COMMITTED":
                break
            elif status["status"] in ["FAILED", "ROLLED_BACK"]:
                pytest.fail(f"Unit of Work failed: {status.get('error')}")
            elif (datetime.utcnow() - start_time).seconds > completion_timeout:
                pytest.fail("Unit of Work timeout")
            
            await asyncio.sleep(1)
        
        # Assert - Verify all operations were committed
        assert status["status"] == "COMMITTED"
        assert len(status["operations"]) == 3
        
        committed_operations = [op for op in status["operations"] if op["status"] == "COMMITTED"]
        assert len(committed_operations) == 3
        
        # Verify user was created
        user_id = status["resolved_variables"]["USER_ID"]
        user_response = await http_client.get(
            f"{self.test_env.auth_service_url}/users/{user_id}"
        )
        assert user_response.status_code == 200
        
        user_details = user_response.json()
        assert user_details["email"] == user_data.email
        assert user_details["username"] == user_data.username
        
        # Verify workspace was created and linked to user
        workspace_id = status["resolved_variables"]["WORKSPACE_ID"]
        workspace_response = await http_client.get(
            f"{self.test_env.api_gateway_url}/workspaces/{workspace_id}"
        )
        assert workspace_response.status_code == 200
        
        workspace_details = workspace_response.json()
        assert workspace_details["name"] == workspace_data.name
        assert workspace_details["owner_id"] == user_id
        
        # Verify notification was sent
        notification_operation = next(op for op in status["operations"] if op["type"] == "SEND_NOTIFICATION")
        assert notification_operation["status"] == "COMMITTED"
        assert notification_operation["result"]["sent"] == True
    
    async def test_unit_of_work_rollback_on_failure(self, http_client: httpx.AsyncClient):
        """Test Unit of Work rollback when any operation fails"""
        # Arrange
        user_data = self.factory.create_user()
        
        # Create a transaction that will fail on the second operation
        uow_start_response = await http_client.post(
            f"{self.uow_url}/begin",
            json={
                "transaction_id": f"tx_fail_{user_data.id}",
                "operations": [
                    {
                        "type": "CREATE_USER",
                        "entity": "User",
                        "data": {
                            "email": user_data.email,
                            "username": user_data.username,
                            "first_name": user_data.first_name,
                            "last_name": user_data.last_name,
                            "password": "password123"
                        }
                    },
                    {
                        "type": "CREATE_WORKSPACE",
                        "entity": "Workspace",
                        "data": {
                            "name": "",  # Invalid name - will cause failure
                            "description": "This will fail",
                            "owner_id": "${USER_ID}"
                        },
                        "depends_on": ["CREATE_USER"]
                    },
                    {
                        "type": "SEND_NOTIFICATION",
                        "entity": "Notification",
                        "data": {
                            "type": "welcome_email",
                            "recipient": user_data.email,
                            "user_id": "${USER_ID}"
                        },
                        "depends_on": ["CREATE_USER", "CREATE_WORKSPACE"]
                    }
                ],
                "rollback_on_failure": True,
                "timeout": 30
            }
        )
        
        assert uow_start_response.status_code == 202
        transaction_id = uow_start_response.json()["transaction_id"]
        
        # Wait for transaction completion (should fail and rollback)
        completion_timeout = 35
        start_time = datetime.utcnow()
        
        while True:
            status_response = await http_client.get(
                f"{self.uow_url}/status/{transaction_id}"
            )
            status = status_response.json()
            
            if status["status"] in ["ROLLED_BACK", "FAILED"]:
                break
            elif status["status"] == "COMMITTED":
                pytest.fail("Transaction should have failed and rolled back")
            elif (datetime.utcnow() - start_time).seconds > completion_timeout:
                pytest.fail("Unit of Work timeout")
            
            await asyncio.sleep(1)
        
        # Assert - Verify rollback occurred
        assert status["status"] == "ROLLED_BACK"
        
        # Verify the failing operation
        failed_operations = [op for op in status["operations"] if op["status"] == "FAILED"]
        assert len(failed_operations) >= 1
        
        workspace_op = next(op for op in status["operations"] if op["type"] == "CREATE_WORKSPACE")
        assert workspace_op["status"] == "FAILED"
        assert workspace_op["error"] is not None
        
        # Verify rollback operations were executed
        rollback_operations = [op for op in status["operations"] if op.get("is_rollback", False)]
        assert len(rollback_operations) >= 1
        
        # Most importantly, verify no partial state remains
        # User should not exist (rolled back)
        if "USER_ID" in status.get("resolved_variables", {}):
            user_id = status["resolved_variables"]["USER_ID"]
            user_response = await http_client.get(
                f"{self.test_env.auth_service_url}/users/{user_id}"
            )
            # User should not exist or be marked as deleted
            assert user_response.status_code in [404, 410]
        
        # Workspace should definitely not exist
        if "WORKSPACE_ID" in status.get("resolved_variables", {}):
            workspace_id = status["resolved_variables"]["WORKSPACE_ID"]
            workspace_response = await http_client.get(
                f"{self.test_env.api_gateway_url}/workspaces/{workspace_id}"
            )
            assert workspace_response.status_code in [404, 410]
    
    async def test_unit_of_work_dependency_resolution(self, http_client: httpx.AsyncClient):
        """Test proper dependency resolution between operations"""
        # Arrange
        user_data = self.factory.create_user()
        
        uow_start_response = await http_client.post(
            f"{self.uow_url}/begin",
            json={
                "transaction_id": f"tx_deps_{user_data.id}",
                "operations": [
                    {
                        "operation_id": "op1",
                        "type": "CREATE_USER",
                        "entity": "User",
                        "data": {
                            "email": user_data.email,
                            "username": user_data.username,
                            "first_name": user_data.first_name,
                            "last_name": user_data.last_name,
                            "password": "password123"
                        }
                    },
                    {
                        "operation_id": "op2",
                        "type": "CREATE_WORKSPACE",
                        "entity": "Workspace",
                        "data": {
                            "name": "Primary Workspace",
                            "description": "User's primary workspace",
                            "owner_id": "${op1.USER_ID}"
                        },
                        "depends_on": ["op1"]
                    },
                    {
                        "operation_id": "op3",
                        "type": "CREATE_WORKSPACE",
                        "entity": "Workspace",
                        "data": {
                            "name": "Secondary Workspace",
                            "description": "User's secondary workspace", 
                            "owner_id": "${op1.USER_ID}"
                        },
                        "depends_on": ["op1"]
                    },
                    {
                        "operation_id": "op4",
                        "type": "LINK_WORKSPACES",
                        "entity": "WorkspaceLink",
                        "data": {
                            "primary_workspace_id": "${op2.WORKSPACE_ID}",
                            "secondary_workspace_id": "${op3.WORKSPACE_ID}",
                            "link_type": "related"
                        },
                        "depends_on": ["op2", "op3"]
                    }
                ]
            }
        )
        
        transaction_id = uow_start_response.json()["transaction_id"]
        
        # Wait for completion
        while True:
            status_response = await http_client.get(
                f"{self.uow_url}/status/{transaction_id}"
            )
            status = status_response.json()
            
            if status["status"] == "COMMITTED":
                break
            elif status["status"] in ["FAILED", "ROLLED_BACK"]:
                pytest.fail(f"Transaction failed: {status}")
            
            await asyncio.sleep(1)
        
        # Assert - Verify dependency execution order
        operations = status["operations"]
        
        # Find execution timestamps
        op1_time = datetime.fromisoformat(
            next(op for op in operations if op["operation_id"] == "op1")["completed_at"].replace('Z', '+00:00')
        )
        op2_time = datetime.fromisoformat(
            next(op for op in operations if op["operation_id"] == "op2")["completed_at"].replace('Z', '+00:00')
        )
        op3_time = datetime.fromisoformat(
            next(op for op in operations if op["operation_id"] == "op3")["completed_at"].replace('Z', '+00:00')
        )
        op4_time = datetime.fromisoformat(
            next(op for op in operations if op["operation_id"] == "op4")["completed_at"].replace('Z', '+00:00')
        )
        
        # Verify execution order respects dependencies
        assert op1_time < op2_time, "op2 should execute after op1"
        assert op1_time < op3_time, "op3 should execute after op1"
        assert op2_time < op4_time, "op4 should execute after op2"
        assert op3_time < op4_time, "op4 should execute after op3"
        
        # op2 and op3 can execute in parallel (both depend only on op1)
        # But op4 must wait for both
        
        # Verify variable resolution worked correctly
        user_id = status["resolved_variables"]["op1.USER_ID"]
        primary_workspace_id = status["resolved_variables"]["op2.WORKSPACE_ID"]
        secondary_workspace_id = status["resolved_variables"]["op3.WORKSPACE_ID"]
        
        # Verify the final linking operation used correct IDs
        link_operation = next(op for op in operations if op["operation_id"] == "op4")
        assert link_operation["resolved_data"]["primary_workspace_id"] == primary_workspace_id
        assert link_operation["resolved_data"]["secondary_workspace_id"] == secondary_workspace_id
    
    async def test_unit_of_work_concurrent_transactions(self, http_client: httpx.AsyncClient):
        """Test concurrent Unit of Work transactions don't interfere"""
        # Arrange - Start multiple concurrent transactions
        num_transactions = 5
        user_data_list = [self.factory.create_user() for _ in range(num_transactions)]
        
        async def execute_transaction(user_data, tx_index):
            uow_response = await http_client.post(
                f"{self.uow_url}/begin",
                json={
                    "transaction_id": f"concurrent_tx_{tx_index}",
                    "operations": [
                        {
                            "type": "CREATE_USER",
                            "entity": "User",
                            "data": {
                                "email": user_data.email,
                                "username": user_data.username,
                                "first_name": user_data.first_name,
                                "last_name": user_data.last_name,
                                "password": "password123"
                            }
                        },
                        {
                            "type": "CREATE_WORKSPACE",
                            "entity": "Workspace",
                            "data": {
                                "name": f"Workspace {tx_index}",
                                "description": f"Concurrent workspace {tx_index}",
                                "owner_id": "${USER_ID}"
                            },
                            "depends_on": ["CREATE_USER"]
                        }
                    ]
                }
            )
            
            transaction_id = uow_response.json()["transaction_id"]
            
            # Wait for completion
            while True:
                status_response = await http_client.get(
                    f"{self.uow_url}/status/{transaction_id}"
                )
                status = status_response.json()
                
                if status["status"] in ["COMMITTED", "FAILED", "ROLLED_BACK"]:
                    return status
                
                await asyncio.sleep(0.5)
        
        # Act - Execute all transactions concurrently
        tasks = [
            execute_transaction(user_data, i) 
            for i, user_data in enumerate(user_data_list)
        ]
        
        results = await asyncio.gather(*tasks, return_exceptions=True)
        
        # Assert - All transactions should complete successfully
        successful_transactions = [
            result for result in results 
            if isinstance(result, dict) and result["status"] == "COMMITTED"
        ]
        
        assert len(successful_transactions) == num_transactions
        
        # Verify no data corruption - each transaction created distinct entities
        created_user_ids = []
        created_workspace_ids = []
        
        for result in successful_transactions:
            user_id = result["resolved_variables"]["USER_ID"]
            workspace_id = result["resolved_variables"]["WORKSPACE_ID"]
            
            created_user_ids.append(user_id)
            created_workspace_ids.append(workspace_id)
        
        # All IDs should be unique (no conflicts)
        assert len(created_user_ids) == len(set(created_user_ids))
        assert len(created_workspace_ids) == len(set(created_workspace_ids))
        
        # Verify each user owns exactly one workspace
        for i, result in enumerate(successful_transactions):
            user_id = result["resolved_variables"]["USER_ID"]
            workspace_id = result["resolved_variables"]["WORKSPACE_ID"]
            
            workspace_response = await http_client.get(
                f"{self.test_env.api_gateway_url}/workspaces/{workspace_id}"
            )
            workspace = workspace_response.json()
            
            assert workspace["owner_id"] == user_id
            assert workspace["name"] == f"Workspace {i}"
    
    async def test_unit_of_work_timeout_handling(self, http_client: httpx.AsyncClient):
        """Test Unit of Work timeout and cleanup"""
        # Arrange
        user_data = self.factory.create_user()
        
        uow_start_response = await http_client.post(
            f"{self.uow_url}/begin",
            json={
                "transaction_id": f"tx_timeout_{user_data.id}",
                "operations": [
                    {
                        "type": "CREATE_USER",
                        "entity": "User",
                        "data": {
                            "email": user_data.email,
                            "username": user_data.username,
                            "first_name": user_data.first_name,
                            "last_name": user_data.last_name,
                            "password": "password123"
                        }
                    },
                    {
                        "type": "SLOW_OPERATION",  # This will take longer than timeout
                        "entity": "SlowProcess",
                        "data": {
                            "duration": 15,  # 15 seconds
                            "user_id": "${USER_ID}"
                        },
                        "depends_on": ["CREATE_USER"]
                    }
                ],
                "timeout": 5  # 5 second timeout
            }
        )
        
        transaction_id = uow_start_response.json()["transaction_id"]
        
        # Wait for timeout to occur
        await asyncio.sleep(7)  # Wait longer than timeout
        
        # Check transaction status
        status_response = await http_client.get(
            f"{self.uow_url}/status/{transaction_id}"
        )
        status = status_response.json()
        
        # Assert - Transaction should have timed out
        assert status["status"] in ["TIMEOUT", "ROLLED_BACK"]
        assert status["timed_out"] == True
        assert status["timeout_occurred_at"] is not None
        
        # Verify cleanup occurred (partial operations rolled back)
        if "USER_ID" in status.get("resolved_variables", {}):
            user_id = status["resolved_variables"]["USER_ID"]
            user_response = await http_client.get(
                f"{self.test_env.auth_service_url}/users/{user_id}"
            )
            # User should be cleaned up due to timeout rollback
            assert user_response.status_code in [404, 410]
    
    async def test_unit_of_work_savepoints_and_partial_rollback(self, http_client: httpx.AsyncClient):
        """Test savepoints and partial rollback within Unit of Work"""
        # Arrange
        user_data = self.factory.create_user()
        
        uow_start_response = await http_client.post(
            f"{self.uow_url}/begin",
            json={
                "transaction_id": f"tx_savepoint_{user_data.id}",
                "operations": [
                    {
                        "operation_id": "create_user",
                        "type": "CREATE_USER",
                        "entity": "User",
                        "data": {
                            "email": user_data.email,
                            "username": user_data.username,
                            "first_name": user_data.first_name,
                            "last_name": user_data.last_name,
                            "password": "password123"
                        },
                        "savepoint_after": True
                    },
                    {
                        "operation_id": "create_workspace1",
                        "type": "CREATE_WORKSPACE",
                        "entity": "Workspace",
                        "data": {
                            "name": "Workspace 1",
                            "description": "First workspace",
                            "owner_id": "${create_user.USER_ID}"
                        },
                        "depends_on": ["create_user"],
                        "savepoint_after": True
                    },
                    {
                        "operation_id": "create_workspace2",
                        "type": "CREATE_WORKSPACE",
                        "entity": "Workspace",
                        "data": {
                            "name": "",  # This will fail
                            "description": "This will fail",
                            "owner_id": "${create_user.USER_ID}"
                        },
                        "depends_on": ["create_user"],
                        "rollback_to_savepoint_on_failure": "create_workspace1"
                    },
                    {
                        "operation_id": "create_workspace3",
                        "type": "CREATE_WORKSPACE",
                        "entity": "Workspace",
                        "data": {
                            "name": "Workspace 3",
                            "description": "Third workspace (after recovery)",
                            "owner_id": "${create_user.USER_ID}"
                        },
                        "depends_on": ["create_user"],
                        "execute_after_rollback": True
                    }
                ],
                "partial_rollback_enabled": True
            }
        )
        
        transaction_id = uow_start_response.json()["transaction_id"]
        
        # Wait for completion
        while True:
            status_response = await http_client.get(
                f"{self.uow_url}/status/{transaction_id}"
            )
            status = status_response.json()
            
            if status["status"] in ["COMMITTED", "PARTIALLY_COMMITTED", "FAILED"]:
                break
            
            await asyncio.sleep(1)
        
        # Assert - Should be partially committed (user + workspace1 + workspace3)
        assert status["status"] in ["COMMITTED", "PARTIALLY_COMMITTED"]
        
        # Verify savepoint operations
        create_user_op = next(op for op in status["operations"] if op["operation_id"] == "create_user")
        create_ws1_op = next(op for op in status["operations"] if op["operation_id"] == "create_workspace1")
        create_ws2_op = next(op for op in status["operations"] if op["operation_id"] == "create_workspace2")
        create_ws3_op = next(op for op in status["operations"] if op["operation_id"] == "create_workspace3")
        
        assert create_user_op["status"] == "COMMITTED"
        assert create_ws1_op["status"] == "COMMITTED"
        assert create_ws2_op["status"] == "FAILED"
        assert create_ws3_op["status"] == "COMMITTED"  # Executed after recovery
        
        # Verify actual data state
        user_id = status["resolved_variables"]["create_user.USER_ID"]
        workspace1_id = status["resolved_variables"]["create_workspace1.WORKSPACE_ID"]
        workspace3_id = status["resolved_variables"]["create_workspace3.WORKSPACE_ID"]
        
        # User should exist
        user_response = await http_client.get(f"{self.test_env.auth_service_url}/users/{user_id}")
        assert user_response.status_code == 200
        
        # Workspace 1 should exist
        ws1_response = await http_client.get(f"{self.test_env.api_gateway_url}/workspaces/{workspace1_id}")
        assert ws1_response.status_code == 200
        assert ws1_response.json()["name"] == "Workspace 1"
        
        # Workspace 3 should exist (created after recovery)
        ws3_response = await http_client.get(f"{self.test_env.api_gateway_url}/workspaces/{workspace3_id}")
        assert ws3_response.status_code == 200
        assert ws3_response.json()["name"] == "Workspace 3"
        
        # Workspace 2 should NOT exist (failed and rolled back)
        assert "create_workspace2.WORKSPACE_ID" not in status["resolved_variables"]