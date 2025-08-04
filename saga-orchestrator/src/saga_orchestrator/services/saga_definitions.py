"""SAGA definitions for various business processes."""

from typing import Dict, Any, List

from ..models.sagas import SagaStep


class UserOnboardingSaga:
    """SAGA for user onboarding process."""
    
    @staticmethod
    def create_steps(user_data: Dict[str, Any]) -> List[SagaStep]:
        """Create steps for user onboarding SAGA."""
        return [
            SagaStep(
                name="Create User Profile",
                service="user-service",
                command={
                    "action": "create_profile",
                    "data": {
                        "user_id": user_data.get("user_id"),
                        "email": user_data.get("email"),
                        "first_name": user_data.get("first_name"),
                        "last_name": user_data.get("last_name"),
                        "tenant_id": user_data.get("tenant_id")
                    }
                },
                compensation_command={
                    "action": "delete_profile",
                    "data": {"user_id": user_data.get("user_id")}
                },
                timeout_seconds=30
            ),
            SagaStep(
                name="Setup Default Workspace",
                service="permission-service",
                command={
                    "action": "create_workspace",
                    "data": {
                        "user_id": user_data.get("user_id"),
                        "workspace_name": f"{user_data.get('first_name', 'My')} Workspace",
                        "tenant_id": user_data.get("tenant_id"),
                        "plan": "free"
                    }
                },
                compensation_command={
                    "action": "delete_workspace",
                    "data": {"workspace_id": "{{output.workspace_id}}"}
                },
                timeout_seconds=30
            ),
            SagaStep(
                name="Send Welcome Email",
                service="notification-service",
                command={
                    "action": "send_notification",
                    "data": {
                        "user_id": user_data.get("user_id"),
                        "template": "welcome_email",
                        "recipient": user_data.get("email"),
                        "data": {
                            "user_name": user_data.get("first_name", "User"),
                            "workspace_name": "{{output.workspace_name}}"
                        }
                    }
                },
                # No compensation needed for notification
                timeout_seconds=30
            ),
            SagaStep(
                name="Setup Default Airtable Integration",
                service="airtable-connector",
                command={
                    "action": "create_sample_base",
                    "data": {
                        "user_id": user_data.get("user_id"),
                        "workspace_id": "{{output.workspace_id}}",
                        "tenant_id": user_data.get("tenant_id")
                    }
                },
                compensation_command={
                    "action": "delete_sample_base",
                    "data": {"base_id": "{{output.base_id}}"}
                },
                timeout_seconds=60
            )
        ]


class AirtableIntegrationSaga:
    """SAGA for connecting an Airtable base."""
    
    @staticmethod
    def create_steps(integration_data: Dict[str, Any]) -> List[SagaStep]:
        """Create steps for Airtable integration SAGA."""
        return [
            SagaStep(
                name="Validate Airtable Access",
                service="airtable-connector",
                command={
                    "action": "validate_access",
                    "data": {
                        "base_id": integration_data["base_id"],
                        "api_key": integration_data["api_key"],
                        "user_id": integration_data["user_id"]
                    }
                },
                timeout_seconds=30
            ),
            SagaStep(
                name="Fetch Base Schema",
                service="schema-service",
                command={
                    "action": "fetch_schema",
                    "data": {
                        "base_id": integration_data["base_id"],
                        "tenant_id": integration_data["tenant_id"],
                        "user_id": integration_data["user_id"]
                    }
                },
                compensation_command={
                    "action": "delete_schema",
                    "data": {"base_id": integration_data["base_id"]}
                },
                timeout_seconds=60
            ),
            SagaStep(
                name="Setup Airtable Webhook",
                service="webhook-service",
                command={
                    "action": "create_webhook",
                    "data": {
                        "base_id": integration_data["base_id"],
                        "tenant_id": integration_data["tenant_id"],
                        "user_id": integration_data["user_id"],
                        "callback_url": integration_data.get("webhook_url", "https://api.pyairtable.com/webhooks/receive")
                    }
                },
                compensation_command={
                    "action": "delete_webhook",
                    "data": {"webhook_id": "{{output.webhook_id}}"}
                },
                timeout_seconds=30
            ),
            SagaStep(
                name="Perform Initial Data Sync",
                service="data-sync-service",
                command={
                    "action": "full_sync",
                    "data": {
                        "base_id": integration_data["base_id"],
                        "tenant_id": integration_data["tenant_id"],
                        "user_id": integration_data["user_id"]
                    }
                },
                timeout_seconds=600  # 10 minutes for initial sync
            ),
            SagaStep(
                name="Send Integration Success Notification",
                service="notification-service",
                command={
                    "action": "send_notification",
                    "data": {
                        "user_id": integration_data["user_id"],
                        "template": "airtable_integration_success",
                        "data": {
                            "base_name": "{{output.base_name}}",
                            "tables_count": "{{output.tables_count}}",
                            "records_synced": "{{output.records_synced}}"
                        }
                    }
                },
                timeout_seconds=30
            )
        ]


class WorkflowExecutionSaga:
    """SAGA for executing complex workflows."""
    
    @staticmethod
    def create_steps(workflow_data: Dict[str, Any]) -> List[SagaStep]:
        """Create steps for workflow execution SAGA."""
        return [
            SagaStep(
                name="Initialize Workflow",
                service="automation-services",
                command={
                    "action": "initialize_workflow",
                    "data": {
                        "workflow_id": workflow_data["workflow_id"],
                        "user_id": workflow_data["user_id"],
                        "tenant_id": workflow_data["tenant_id"],
                        "input_data": workflow_data.get("input_data", {})
                    }
                },
                compensation_command={
                    "action": "cleanup_workflow",
                    "data": {"execution_id": "{{output.execution_id}}"}
                },
                timeout_seconds=30
            ),
            SagaStep(
                name="Process Files",
                service="automation-services",
                command={
                    "action": "process_files",
                    "data": {
                        "execution_id": "{{output.execution_id}}",
                        "files": workflow_data.get("files", [])
                    }
                },
                compensation_command={
                    "action": "cleanup_processed_files",
                    "data": {"execution_id": "{{output.execution_id}}"}
                },
                timeout_seconds=300  # 5 minutes
            ),
            SagaStep(
                name="Update Airtable Records",
                service="airtable-connector",
                command={
                    "action": "bulk_update",
                    "data": {
                        "base_id": workflow_data["base_id"],
                        "table_name": workflow_data["table_name"],
                        "records": "{{output.processed_records}}"
                    }
                },
                compensation_command={
                    "action": "revert_updates",
                    "data": {
                        "base_id": workflow_data["base_id"],
                        "backup_id": "{{output.backup_id}}"
                    }
                },
                timeout_seconds=180  # 3 minutes
            ),
            SagaStep(
                name="Send Completion Notification",
                service="notification-service",
                command={
                    "action": "send_notification",
                    "data": {
                        "user_id": workflow_data["user_id"],
                        "template": "workflow_completed",
                        "data": {
                            "workflow_name": workflow_data.get("workflow_name"),
                            "records_processed": "{{output.records_processed}}",
                            "execution_time": "{{output.execution_time}}"
                        }
                    }
                },
                timeout_seconds=30
            )
        ]