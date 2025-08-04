"""
Critical user journey tests for PyAirtable system.
Tests complete end-to-end workflows that users commonly perform.
"""

import pytest
import httpx
import asyncio
import time
from typing import Dict, Any, Optional, List
from dataclasses import dataclass, asdict
import json


@dataclass
class TestUser:
    """Test user data."""
    email: str
    password: str
    name: str
    tenant_id: str
    access_token: Optional[str] = None
    refresh_token: Optional[str] = None
    user_id: Optional[str] = None


@dataclass
class TestWorkspace:
    """Test workspace data."""
    id: Optional[str] = None
    name: str = ""
    description: str = ""
    tenant_id: str = ""
    owner_id: str = ""


@dataclass
class TestAirtableBase:
    """Test Airtable base data."""
    id: str
    name: str
    tables: List[Dict[str, Any]] = None


class UserJourneyTestFramework:
    """Framework for testing user journeys."""
    
    def __init__(self, base_url: str = "http://localhost:8000"):
        self.base_url = base_url
        self.session: Optional[httpx.AsyncClient] = None
        
    async def __aenter__(self):
        self.session = httpx.AsyncClient(timeout=60.0)
        return self
        
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        if self.session:
            await self.session.aclose()
    
    async def register_user(self, user: TestUser) -> Dict[str, Any]:
        """Register a new user."""
        payload = {
            "email": user.email,
            "password": user.password,
            "name": user.name,
            "tenant_id": user.tenant_id
        }
        
        response = await self.session.post(
            f"{self.base_url}/api/v1/auth/register",
            json=payload
        )
        
        if response.status_code == 201:
            data = response.json()["data"]
            user.access_token = data["tokens"]["access_token"]
            user.refresh_token = data["tokens"]["refresh_token"]
            user.user_id = data["user"]["id"]
        
        return {
            "status_code": response.status_code,
            "data": response.json() if response.text else None,
            "success": response.status_code == 201
        }
    
    async def login_user(self, user: TestUser) -> Dict[str, Any]:
        """Login user."""
        payload = {
            "email": user.email,
            "password": user.password
        }
        
        response = await self.session.post(
            f"{self.base_url}/api/v1/auth/login",
            json=payload
        )
        
        if response.status_code == 200:
            data = response.json()["data"]
            user.access_token = data["tokens"]["access_token"]
            user.refresh_token = data["tokens"]["refresh_token"]
            user.user_id = data["user"]["id"]
        
        return {
            "status_code": response.status_code,
            "data": response.json() if response.text else None,
            "success": response.status_code == 200
        }
    
    def _get_auth_headers(self, user: TestUser) -> Dict[str, str]:
        """Get authentication headers."""
        return {
            "Authorization": f"Bearer {user.access_token}",
            "Content-Type": "application/json"
        }
    
    async def create_workspace(self, user: TestUser, workspace: TestWorkspace) -> Dict[str, Any]:
        """Create a workspace."""
        payload = {
            "name": workspace.name,
            "description": workspace.description
        }
        
        response = await self.session.post(
            f"{self.base_url}/api/v1/workspaces",
            json=payload,
            headers=self._get_auth_headers(user)
        )
        
        if response.status_code == 201:
            data = response.json()["data"]["workspace"]
            workspace.id = data["id"]
            workspace.tenant_id = data["tenant_id"]
            workspace.owner_id = data["owner_id"]
        
        return {
            "status_code": response.status_code,
            "data": response.json() if response.text else None,
            "success": response.status_code == 201
        }
    
    async def list_workspaces(self, user: TestUser) -> Dict[str, Any]:
        """List user workspaces."""
        response = await self.session.get(
            f"{self.base_url}/api/v1/workspaces",
            headers=self._get_auth_headers(user)
        )
        
        return {
            "status_code": response.status_code,
            "data": response.json() if response.text else None,
            "success": response.status_code == 200
        }
    
    async def get_workspace(self, user: TestUser, workspace_id: str) -> Dict[str, Any]:
        """Get workspace details."""
        response = await self.session.get(
            f"{self.base_url}/api/v1/workspaces/{workspace_id}",
            headers=self._get_auth_headers(user)
        )
        
        return {
            "status_code": response.status_code,
            "data": response.json() if response.text else None,
            "success": response.status_code == 200
        }
    
    async def update_workspace(self, user: TestUser, workspace: TestWorkspace) -> Dict[str, Any]:
        """Update workspace."""
        payload = {
            "name": workspace.name,
            "description": workspace.description
        }
        
        response = await self.session.put(
            f"{self.base_url}/api/v1/workspaces/{workspace.id}",
            json=payload,
            headers=self._get_auth_headers(user)
        )
        
        return {
            "status_code": response.status_code,
            "data": response.json() if response.text else None,
            "success": response.status_code == 200
        }
    
    async def delete_workspace(self, user: TestUser, workspace_id: str) -> Dict[str, Any]:
        """Delete workspace."""
        response = await self.session.delete(
            f"{self.base_url}/api/v1/workspaces/{workspace_id}",
            headers=self._get_auth_headers(user)
        )
        
        return {
            "status_code": response.status_code,
            "data": response.json() if response.text else None,
            "success": response.status_code in [200, 204]
        }
    
    async def list_airtable_bases(self, user: TestUser) -> Dict[str, Any]:
        """List Airtable bases."""
        response = await self.session.get(
            f"{self.base_url}/api/v1/airtable/bases",
            headers=self._get_auth_headers(user)
        )
        
        return {
            "status_code": response.status_code,
            "data": response.json() if response.text else None,
            "success": response.status_code == 200
        }
    
    async def get_airtable_tables(self, user: TestUser, base_id: str) -> Dict[str, Any]:
        """Get Airtable tables for a base."""
        response = await self.session.get(
            f"{self.base_url}/api/v1/airtable/bases/{base_id}/tables",
            headers=self._get_auth_headers(user)
        )
        
        return {
            "status_code": response.status_code,
            "data": response.json() if response.text else None,
            "success": response.status_code == 200
        }
    
    async def get_airtable_records(self, user: TestUser, base_id: str, table_id: str, 
                                 limit: int = 10) -> Dict[str, Any]:
        """Get Airtable records."""
        params = {"limit": limit}
        
        response = await self.session.get(
            f"{self.base_url}/api/v1/airtable/bases/{base_id}/tables/{table_id}/records",
            params=params,
            headers=self._get_auth_headers(user)
        )
        
        return {
            "status_code": response.status_code,
            "data": response.json() if response.text else None,
            "success": response.status_code == 200
        }
    
    async def chat_with_ai(self, user: TestUser, message: str, context: Dict[str, Any] = None) -> Dict[str, Any]:
        """Chat with AI assistant."""
        payload = {
            "message": message,
            "session_id": f"test_session_{user.user_id}_{int(time.time())}",
            "context": context or {}
        }
        
        response = await self.session.post(
            f"{self.base_url}/api/v1/chat",
            json=payload,
            headers=self._get_auth_headers(user)
        )
        
        return {
            "status_code": response.status_code,
            "data": response.json() if response.text else None,
            "success": response.status_code == 200
        }
    
    async def get_user_profile(self, user: TestUser) -> Dict[str, Any]:
        """Get user profile."""
        response = await self.session.get(
            f"{self.base_url}/api/v1/auth/me",
            headers=self._get_auth_headers(user)
        )
        
        return {
            "status_code": response.status_code,
            "data": response.json() if response.text else None,
            "success": response.status_code == 200
        }
    
    async def refresh_token(self, user: TestUser) -> Dict[str, Any]:
        """Refresh user token."""
        payload = {
            "refresh_token": user.refresh_token
        }
        
        response = await self.session.post(
            f"{self.base_url}/api/v1/auth/refresh",
            json=payload
        )
        
        if response.status_code == 200:
            data = response.json()["data"]["tokens"]
            user.access_token = data["access_token"]
            user.refresh_token = data["refresh_token"]
        
        return {
            "status_code": response.status_code,
            "data": response.json() if response.text else None,
            "success": response.status_code == 200
        }


@pytest.mark.critical_path
class TestNewUserOnboarding:
    """Test new user onboarding journey."""
    
    @pytest.fixture
    async def framework(self):
        async with UserJourneyTestFramework() as framework:
            yield framework
    
    @pytest.fixture
    def test_user(self):
        return TestUser(
            email=f"newuser{int(time.time())}@example.com",
            password="SecurePassword123!",
            name="New Test User",
            tenant_id="test-tenant"
        )
    
    @pytest.mark.asyncio
    async def test_complete_user_onboarding_journey(self, framework, test_user):
        """Test complete user onboarding from registration to first workspace."""
        print(f"Testing onboarding for user: {test_user.email}")
        
        # Step 1: User Registration
        print("1. Registering new user...")
        register_result = await framework.register_user(test_user)
        assert register_result["success"], f"Registration failed: {register_result}"
        assert test_user.access_token is not None, "No access token received"
        print("✓ User registered successfully")
        
        # Step 2: Get User Profile
        print("2. Getting user profile...")
        profile_result = await framework.get_user_profile(test_user)
        assert profile_result["success"], f"Get profile failed: {profile_result}"
        
        profile_data = profile_result["data"]["data"]["user"]
        assert profile_data["email"] == test_user.email
        assert profile_data["name"] == test_user.name
        print("✓ User profile retrieved successfully")
        
        # Step 3: Create First Workspace
        print("3. Creating first workspace...")
        workspace = TestWorkspace(
            name="My First Workspace",
            description="This is my first workspace in PyAirtable"
        )
        
        create_result = await framework.create_workspace(test_user, workspace)
        assert create_result["success"], f"Workspace creation failed: {create_result}"
        assert workspace.id is not None, "No workspace ID received"
        print(f"✓ Workspace created: {workspace.id}")
        
        # Step 4: List Workspaces
        print("4. Listing workspaces...")
        list_result = await framework.list_workspaces(test_user)
        assert list_result["success"], f"List workspaces failed: {list_result}"
        
        workspaces = list_result["data"]["data"]["workspaces"]
        assert len(workspaces) >= 1, "No workspaces found"
        assert any(w["id"] == workspace.id for w in workspaces), "Created workspace not in list"
        print(f"✓ Found {len(workspaces)} workspace(s)")
        
        # Step 5: Test Airtable Integration Setup
        print("5. Testing Airtable integration...")
        bases_result = await framework.list_airtable_bases(test_user)
        
        if bases_result["success"]:
            bases = bases_result["data"]["data"]["bases"]
            print(f"✓ Found {len(bases)} Airtable base(s)")
            
            # If bases exist, test table listing
            if bases:
                base_id = bases[0]["id"]
                tables_result = await framework.get_airtable_tables(test_user, base_id)
                
                if tables_result["success"]:
                    tables = tables_result["data"]["data"]["tables"]
                    print(f"✓ Found {len(tables)} table(s) in base {base_id}")
        else:
            print("⚠ Airtable integration not configured or failed")
        
        # Step 6: Test AI Chat
        print("6. Testing AI chat functionality...")
        chat_result = await framework.chat_with_ai(
            test_user, 
            "Hello! I'm a new user. Can you help me understand how to use PyAirtable?",
            {"context": "onboarding"}
        )
        
        if chat_result["success"]:
            response_text = chat_result["data"]["data"]["response"]
            assert len(response_text) > 0, "Empty AI response"
            print("✓ AI chat working")
        else:
            print("⚠ AI chat not available or failed")
        
        print("✓ Complete user onboarding journey successful!")


@pytest.mark.critical_path
class TestWorkspaceManagement:
    """Test workspace management journey."""
    
    @pytest.fixture
    async def framework(self):
        async with UserJourneyTestFramework() as framework:
            yield framework
    
    @pytest.fixture
    async def authenticated_user(self, framework):
        user = TestUser(
            email="workspaceuser@example.com",
            password="TestPassword123!",
            name="Workspace Test User",
            tenant_id="test-tenant"
        )
        
        # Try to login first, register if fails
        login_result = await framework.login_user(user)
        if not login_result["success"]:
            register_result = await framework.register_user(user)
            assert register_result["success"], "Failed to register test user"
        
        return user
    
    @pytest.mark.asyncio
    async def test_workspace_lifecycle_management(self, framework, authenticated_user):
        """Test complete workspace lifecycle: create, read, update, delete."""
        user = authenticated_user
        
        print("Testing workspace lifecycle management...")
        
        # Step 1: Create Multiple Workspaces
        print("1. Creating multiple workspaces...")
        workspaces = []
        
        for i in range(3):
            workspace = TestWorkspace(
                name=f"Test Workspace {i+1}",
                description=f"Description for workspace {i+1}"
            )
            
            create_result = await framework.create_workspace(user, workspace)
            assert create_result["success"], f"Failed to create workspace {i+1}"
            workspaces.append(workspace)
        
        print(f"✓ Created {len(workspaces)} workspaces")
        
        # Step 2: List All Workspaces
        print("2. Listing all workspaces...")
        list_result = await framework.list_workspaces(user)
        assert list_result["success"], "Failed to list workspaces"
        
        workspace_list = list_result["data"]["data"]["workspaces"]
        assert len(workspace_list) >= len(workspaces), "Not all workspaces found in list"
        print(f"✓ Listed {len(workspace_list)} workspaces")
        
        # Step 3: Get Individual Workspace Details
        print("3. Getting workspace details...")
        for workspace in workspaces:
            get_result = await framework.get_workspace(user, workspace.id)
            assert get_result["success"], f"Failed to get workspace {workspace.id}"
            
            workspace_data = get_result["data"]["data"]["workspace"]
            assert workspace_data["name"] == workspace.name
            assert workspace_data["description"] == workspace.description
        
        print("✓ Retrieved all workspace details")
        
        # Step 4: Update Workspaces
        print("4. Updating workspaces...")
        for i, workspace in enumerate(workspaces):
            workspace.name = f"Updated Workspace {i+1}"
            workspace.description = f"Updated description for workspace {i+1}"
            
            update_result = await framework.update_workspace(user, workspace)
            assert update_result["success"], f"Failed to update workspace {workspace.id}"
            
            # Verify update
            get_result = await framework.get_workspace(user, workspace.id)
            updated_data = get_result["data"]["data"]["workspace"]
            assert updated_data["name"] == workspace.name
        
        print("✓ Updated all workspaces")
        
        # Step 5: Delete Workspaces
        print("5. Deleting workspaces...")
        for workspace in workspaces:
            delete_result = await framework.delete_workspace(user, workspace.id)
            assert delete_result["success"], f"Failed to delete workspace {workspace.id}"
        
        print("✓ Deleted all workspaces")
        
        # Step 6: Verify Deletion
        print("6. Verifying deletion...")
        list_result = await framework.list_workspaces(user)
        assert list_result["success"], "Failed to list workspaces after deletion"
        
        remaining_workspaces = list_result["data"]["data"]["workspaces"]
        created_workspace_ids = {w.id for w in workspaces}
        remaining_ids = {w["id"] for w in remaining_workspaces}
        
        assert not created_workspace_ids.intersection(remaining_ids), "Some workspaces not deleted"
        print("✓ All workspaces successfully deleted")
        
        print("✓ Complete workspace lifecycle management successful!")


@pytest.mark.critical_path
class TestAirtableIntegration:
    """Test Airtable integration journey."""
    
    @pytest.fixture
    async def framework(self):
        async with UserJourneyTestFramework() as framework:
            yield framework
    
    @pytest.fixture
    async def authenticated_user(self, framework):
        user = TestUser(
            email="airtableuser@example.com",
            password="TestPassword123!",
            name="Airtable Test User",
            tenant_id="test-tenant"
        )
        
        login_result = await framework.login_user(user)
        if not login_result["success"]:
            register_result = await framework.register_user(user)
            assert register_result["success"], "Failed to register test user"
        
        return user
    
    @pytest.mark.asyncio
    async def test_airtable_data_exploration(self, framework, authenticated_user):
        """Test Airtable data exploration workflow."""
        user = authenticated_user
        
        print("Testing Airtable data exploration...")
        
        # Step 1: List Available Bases
        print("1. Listing Airtable bases...")
        bases_result = await framework.list_airtable_bases(user)
        
        if not bases_result["success"]:
            pytest.skip("Airtable integration not available or configured")
        
        bases = bases_result["data"]["data"]["bases"]
        if not bases:
            pytest.skip("No Airtable bases available for testing")
        
        print(f"✓ Found {len(bases)} Airtable base(s)")
        
        # Step 2: Explore Each Base
        for base in bases[:2]:  # Test first 2 bases to avoid rate limits
            base_id = base["id"]
            base_name = base["name"]
            
            print(f"2. Exploring base: {base_name} ({base_id})")
            
            # Get tables in base
            tables_result = await framework.get_airtable_tables(user, base_id)
            assert tables_result["success"], f"Failed to get tables for base {base_id}"
            
            tables = tables_result["data"]["data"]["tables"]
            print(f"   ✓ Found {len(tables)} table(s)")
            
            # Step 3: Explore Records in Tables
            for table in tables[:2]:  # Test first 2 tables per base
                table_id = table["id"]
                table_name = table["name"]
                
                print(f"   3. Getting records from table: {table_name}")
                
                records_result = await framework.get_airtable_records(user, base_id, table_id, limit=5)
                assert records_result["success"], f"Failed to get records from table {table_id}"
                
                records = records_result["data"]["data"]["records"]
                print(f"      ✓ Retrieved {len(records)} record(s)")
                
                # Verify record structure
                if records:
                    record = records[0]
                    assert "id" in record, "Record missing ID"
                    assert "fields" in record, "Record missing fields"
                    assert "createdTime" in record, "Record missing created time"
        
        print("✓ Airtable data exploration successful!")
    
    @pytest.mark.asyncio
    async def test_airtable_ai_integration(self, framework, authenticated_user):
        """Test AI integration with Airtable data."""
        user = authenticated_user
        
        print("Testing Airtable AI integration...")
        
        # Step 1: Query AI about Airtable data
        ai_queries = [
            "What Airtable bases do I have access to?",
            "Show me the tables in my first base",
            "How many records are in my main table?",
            "Summarize the data structure of my Airtable bases"
        ]
        
        for query in ai_queries:
            print(f"Asking AI: {query}")
            
            chat_result = await framework.chat_with_ai(
                user, 
                query,
                {"context": "airtable_integration", "include_data": True}
            )
            
            if chat_result["success"]:
                response = chat_result["data"]["data"]["response"]
                assert len(response) > 0, "Empty AI response"
                print(f"   ✓ AI responded: {response[:100]}...")
            else:
                print(f"   ⚠ AI query failed: {query}")
        
        print("✓ Airtable AI integration test completed!")


@pytest.mark.critical_path
class TestTokenRefreshFlow:
    """Test token refresh and session management."""
    
    @pytest.fixture
    async def framework(self):
        async with UserJourneyTestFramework() as framework:
            yield framework
    
    @pytest.fixture
    async def authenticated_user(self, framework):
        user = TestUser(
            email="tokenuser@example.com",
            password="TestPassword123!",
            name="Token Test User",
            tenant_id="test-tenant"
        )
        
        login_result = await framework.login_user(user)
        if not login_result["success"]:
            register_result = await framework.register_user(user)
            assert register_result["success"], "Failed to register test user"
        
        return user
    
    @pytest.mark.asyncio
    async def test_token_refresh_workflow(self, framework, authenticated_user):
        """Test token refresh workflow."""
        user = authenticated_user
        
        print("Testing token refresh workflow...")
        
        # Step 1: Store original tokens
        original_access_token = user.access_token
        original_refresh_token = user.refresh_token
        
        print("1. Original tokens stored")
        
        # Step 2: Make authenticated request
        print("2. Making authenticated request...")
        profile_result = await framework.get_user_profile(user)
        assert profile_result["success"], "Initial authenticated request failed"
        print("✓ Initial request successful")
        
        # Step 3: Refresh tokens
        print("3. Refreshing tokens...")
        refresh_result = await framework.refresh_token(user)
        assert refresh_result["success"], f"Token refresh failed: {refresh_result}"
        
        # Verify new tokens are different
        assert user.access_token != original_access_token, "Access token not refreshed"
        assert user.refresh_token != original_refresh_token, "Refresh token not refreshed"
        print("✓ Tokens refreshed successfully")
        
        # Step 4: Use new tokens for request
        print("4. Using new tokens...")
        new_profile_result = await framework.get_user_profile(user)
        assert new_profile_result["success"], "Request with new tokens failed"
        print("✓ New tokens working")
        
        # Step 5: Multiple refresh cycles
        print("5. Testing multiple refresh cycles...")
        for i in range(3):
            old_access_token = user.access_token
            refresh_result = await framework.refresh_token(user)
            assert refresh_result["success"], f"Refresh cycle {i+1} failed"
            assert user.access_token != old_access_token, f"Token not changed in cycle {i+1}"
            
            # Test token still works
            test_result = await framework.get_user_profile(user)
            assert test_result["success"], f"Token validation failed in cycle {i+1}"
        
        print("✓ Multiple refresh cycles successful")
        
        print("✓ Token refresh workflow completed successfully!")


# CLI runner for critical path tests
async def run_critical_path_tests():
    """Run critical path tests."""
    print("Starting critical path tests...")
    
    async with UserJourneyTestFramework() as framework:
        # Test 1: New User Onboarding
        print("\n=== Testing New User Onboarding ===")
        try:
            user = TestUser(
                email=f"criticaltest{int(time.time())}@example.com",
                password="TestPassword123!",
                name="Critical Path Test User",
                tenant_id="test-tenant"
            )
            
            # Registration
            register_result = await framework.register_user(user)
            if not register_result["success"]:
                print(f"✗ User registration failed: {register_result}")
                return False
            print("✓ User registration successful")
            
            # Create workspace
            workspace = TestWorkspace(
                name="Critical Path Test Workspace",
                description="Testing critical path functionality"
            )
            
            create_result = await framework.create_workspace(user, workspace)
            if not create_result["success"]:
                print(f"✗ Workspace creation failed: {create_result}")
                return False
            print("✓ Workspace creation successful")
            
            # Test AI chat
            chat_result = await framework.chat_with_ai(user, "Hello, this is a test message")
            if chat_result["success"]:
                print("✓ AI chat functional")
            else:
                print("⚠ AI chat not available")
            
        except Exception as e:
            print(f"✗ Critical path test failed: {e}")
            return False
    
    print("✓ All critical path tests completed successfully!")
    return True


if __name__ == "__main__":
    success = asyncio.run(run_critical_path_tests())
    exit(0 if success else 1)