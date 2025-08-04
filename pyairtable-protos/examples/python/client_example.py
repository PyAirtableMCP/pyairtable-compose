#!/usr/bin/env python3
"""
PyAirtable gRPC Client Example

This example demonstrates how to use the generated Python gRPC clients
to interact with PyAirtable services.
"""

import asyncio
import logging
import time
import uuid
from typing import Optional

import grpc
from grpc import aio

# Import generated protobuf modules
from pyairtable.auth.v1 import auth_pb2, auth_pb2_grpc
from pyairtable.user.v1 import user_pb2, user_pb2_grpc
from pyairtable.permission.v1 import permission_pb2, permission_pb2_grpc
from pyairtable.common.v1 import common_pb2

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class PyAirtableClient:
    """PyAirtable gRPC client with connection management and authentication."""
    
    def __init__(self, service_address: str, use_tls: bool = False):
        self.service_address = service_address
        self.use_tls = use_tls
        self.channel: Optional[aio.Channel] = None
        self.access_token: Optional[str] = None
        
        # Service clients
        self.auth_client: Optional[auth_pb2_grpc.AuthServiceStub] = None
        self.user_client: Optional[user_pb2_grpc.UserServiceStub] = None
        self.permission_client: Optional[permission_pb2_grpc.PermissionServiceStub] = None
    
    async def connect(self):
        """Establish gRPC connection to services."""
        if self.use_tls:
            credentials = grpc.ssl_channel_credentials()
            self.channel = aio.secure_channel(self.service_address, credentials)
        else:
            self.channel = aio.insecure_channel(self.service_address)
        
        # Initialize service clients
        self.auth_client = auth_pb2_grpc.AuthServiceStub(self.channel)
        self.user_client = user_pb2_grpc.UserServiceStub(self.channel)
        self.permission_client = permission_pb2_grpc.PermissionServiceStub(self.channel)
        
        logger.info(f"Connected to PyAirtable services at {self.service_address}")
    
    async def close(self):
        """Close the gRPC connection."""
        if self.channel:
            await self.channel.close()
            logger.info("Connection closed")
    
    async def __aenter__(self):
        """Async context manager entry."""
        await self.connect()
        return self
    
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Async context manager exit."""
        await self.close()
    
    def _create_request_metadata(self) -> common_pb2.RequestMetadata:
        """Create request metadata with request ID and timestamp."""
        return common_pb2.RequestMetadata(
            request_id=f"req_{uuid.uuid4().hex[:8]}",
            timestamp=common_pb2.google.protobuf.timestamp_pb2.Timestamp(
                seconds=int(time.time())
            )
        )
    
    def _get_auth_metadata(self) -> Optional[tuple]:
        """Get authentication metadata for requests."""
        if self.access_token:
            return ("authorization", f"Bearer {self.access_token}")
        return None
    
    async def login(self, email: str, password: str) -> auth_pb2.LoginResponse:
        """Authenticate user and store access token."""
        request = auth_pb2.LoginRequest(
            request_metadata=self._create_request_metadata(),
            credentials=auth_pb2.AuthCredentials(
                email=email,
                password=password,
                provider=auth_pb2.AuthProvider.AUTH_PROVIDER_LOCAL
            )
        )
        
        response = await self.auth_client.Login(request)
        
        # Store access token for future requests
        self.access_token = response.access_token.token
        
        logger.info(f"Login successful for user: {response.user_context.email}")
        return response
    
    async def logout(self) -> auth_pb2.LogoutResponse:
        """Logout user and clear access token."""
        metadata = [self._get_auth_metadata()] if self.access_token else []
        
        request = auth_pb2.LogoutRequest(
            request_metadata=self._create_request_metadata(),
            access_token=self.access_token or "",
            all_devices=False
        )
        
        response = await self.auth_client.Logout(request, metadata=metadata)
        
        # Clear stored token
        self.access_token = None
        
        logger.info("Logout successful")
        return response
    
    async def get_user(self, user_id: str) -> user_pb2.GetUserResponse:
        """Get user information by ID."""
        metadata = [self._get_auth_metadata()] if self.access_token else []
        
        request = user_pb2.GetUserRequest(
            request_metadata=self._create_request_metadata(),
            user_id=user_id
        )
        
        response = await self.user_client.GetUser(request, metadata=metadata)
        logger.info(f"Retrieved user: {response.user.email}")
        return response
    
    async def create_user(self, email: str, first_name: str, last_name: str) -> user_pb2.CreateUserResponse:
        """Create a new user."""
        metadata = [self._get_auth_metadata()] if self.access_token else []
        
        request = user_pb2.CreateUserRequest(
            request_metadata=self._create_request_metadata(),
            email=email,
            profile=user_pb2.UserProfile(
                first_name=first_name,
                last_name=last_name
            )
        )
        
        response = await self.user_client.CreateUser(request, metadata=metadata)
        logger.info(f"Created user: {response.user.email} (ID: {response.user.metadata.id})")
        return response
    
    async def list_users(self, page: int = 1, page_size: int = 10) -> user_pb2.ListUsersResponse:
        """List users with pagination."""
        metadata = [self._get_auth_metadata()] if self.access_token else []
        
        request = user_pb2.ListUsersRequest(
            request_metadata=self._create_request_metadata(),
            pagination=common_pb2.PaginationRequest(
                page=page,
                page_size=page_size
            )
        )
        
        response = await self.user_client.ListUsers(request, metadata=metadata)
        logger.info(f"Retrieved {len(response.users)} users")
        return response
    
    async def check_permission(
        self, 
        user_id: str, 
        resource_type: permission_pb2.ResourceType, 
        resource_id: str, 
        action: str
    ) -> permission_pb2.CheckPermissionResponse:
        """Check if user has permission for an action."""
        metadata = [self._get_auth_metadata()] if self.access_token else []
        
        request = permission_pb2.CheckPermissionRequest(
            request_metadata=self._create_request_metadata(),
            user_id=user_id,
            resource_type=resource_type,
            resource_id=resource_id,
            action=action
        )
        
        response = await self.permission_client.CheckPermission(request, metadata=metadata)
        logger.info(f"Permission check: user={user_id}, action={action}, allowed={response.allowed}")
        return response
    
    async def grant_permission(
        self, 
        user_id: str, 
        resource_type: permission_pb2.ResourceType, 
        resource_id: str, 
        level: permission_pb2.PermissionLevel
    ) -> permission_pb2.GrantPermissionResponse:
        """Grant permission to a user."""
        metadata = [self._get_auth_metadata()] if self.access_token else []
        
        request = permission_pb2.GrantPermissionRequest(
            request_metadata=self._create_request_metadata(),
            user_id=user_id,
            resource_type=resource_type,
            resource_id=resource_id,
            level=level
        )
        
        response = await self.permission_client.GrantPermission(request, metadata=metadata)
        logger.info(f"Granted permission: user={user_id}, level={level}")
        return response


async def main():
    """Example usage of the PyAirtable client."""
    
    # Connect to PyAirtable services
    async with PyAirtableClient("localhost:50051", use_tls=False) as client:
        try:
            # Login
            login_response = await client.login("admin@example.com", "password")
            print(f"✓ Login successful: {login_response.user_context.email}")
            
            # Create a new user
            create_response = await client.create_user(
                email="newuser@example.com",
                first_name="John",
                last_name="Doe"
            )
            new_user_id = create_response.user.metadata.id
            print(f"✓ User created: {create_response.user.email} (ID: {new_user_id})")
            
            # Get user details
            user_response = await client.get_user(new_user_id)
            print(f"✓ Retrieved user: {user_response.user.profile.first_name} {user_response.user.profile.last_name}")
            
            # Check permission (should fail initially)
            perm_response = await client.check_permission(
                user_id=new_user_id,
                resource_type=permission_pb2.ResourceType.RESOURCE_TYPE_WORKSPACE,
                resource_id="workspace-123",
                action="read"
            )
            print(f"✓ Initial permission check: allowed={perm_response.allowed}")
            
            # Grant permission
            grant_response = await client.grant_permission(
                user_id=new_user_id,
                resource_type=permission_pb2.ResourceType.RESOURCE_TYPE_WORKSPACE,
                resource_id="workspace-123",
                level=permission_pb2.PermissionLevel.PERMISSION_LEVEL_READ
            )
            print(f"✓ Permission granted")
            
            # Check permission again (should succeed now)
            perm_response2 = await client.check_permission(
                user_id=new_user_id,
                resource_type=permission_pb2.ResourceType.RESOURCE_TYPE_WORKSPACE,
                resource_id="workspace-123",
                action="read"
            )
            print(f"✓ Updated permission check: allowed={perm_response2.allowed}")
            
            # List all users
            list_response = await client.list_users(page=1, page_size=5)
            print(f"✓ Listed {len(list_response.users)} users")
            for user in list_response.users:
                print(f"  - {user.email} ({user.metadata.id})")
            
            # Logout
            await client.logout()
            print("✓ Logout successful")
            
        except grpc.RpcError as e:
            logger.error(f"gRPC error: {e.code()} - {e.details()}")
        except Exception as e:
            logger.error(f"Unexpected error: {e}")


if __name__ == "__main__":
    asyncio.run(main())