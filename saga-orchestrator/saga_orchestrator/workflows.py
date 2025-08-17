#!/usr/bin/env python3
"""
SAGA Workflow Examples and Templates
Demonstrates common distributed transaction patterns for PyAirtable services
"""

from typing import Dict, Any, List
from .main import SagaStepRequest, SagaPattern


class WorkflowTemplates:
    """Pre-defined SAGA workflow templates for common operations"""
    
    @staticmethod
    def user_registration_workflow(user_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        User registration workflow with rollback capabilities
        Steps: Validate -> Create User -> Create Profile -> Send Welcome Email
        """
        return {
            "pattern": SagaPattern.ORCHESTRATION,
            "timeout": 600,  # 10 minutes
            "metadata": {
                "workflow_type": "user_registration",
                "user_email": user_data.get("email")
            },
            "steps": [
                SagaStepRequest(
                    step_id="validate_user_data",
                    service_url="http://platform-services:8007",
                    action="auth/validate-registration",
                    payload=user_data,
                    compensation_action="auth/cleanup-validation",
                    timeout=30
                ),
                SagaStepRequest(
                    step_id="create_user_account",
                    service_url="http://platform-services:8007",
                    action="auth/register",
                    payload=user_data,
                    compensation_action="auth/delete-user",
                    compensation_payload={"user_id": "${step_result.user_id}"},
                    timeout=60
                ),
                SagaStepRequest(
                    step_id="create_user_profile",
                    service_url="http://platform-services:8007",
                    action="users/create-profile",
                    payload={
                        "user_id": "${previous_step.user_id}",
                        "profile_data": user_data.get("profile", {})
                    },
                    compensation_action="users/delete-profile",
                    compensation_payload={"user_id": "${previous_step.user_id}"},
                    timeout=45
                ),
                SagaStepRequest(
                    step_id="send_welcome_email",
                    service_url="http://automation-services:8006",
                    action="notifications/send-welcome",
                    payload={
                        "user_id": "${step_result.user_id}",
                        "email": user_data.get("email"),
                        "name": user_data.get("name")
                    },
                    compensation_action="notifications/send-cancellation",
                    compensation_payload={
                        "user_id": "${step_result.user_id}",
                        "email": user_data.get("email")
                    },
                    timeout=30
                )
            ]
        }
    
    @staticmethod
    def workspace_creation_workflow(workspace_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Workspace creation with Airtable base setup
        Steps: Create Workspace -> Setup Airtable Base -> Configure Permissions -> Notify Team
        """
        return {
            "pattern": SagaPattern.ORCHESTRATION,
            "timeout": 900,  # 15 minutes
            "metadata": {
                "workflow_type": "workspace_creation",
                "workspace_name": workspace_data.get("name"),
                "owner_id": workspace_data.get("owner_id")
            },
            "steps": [
                SagaStepRequest(
                    step_id="create_workspace",
                    service_url="http://workspace-service:8003",
                    action="workspaces/create",
                    payload=workspace_data,
                    compensation_action="workspaces/delete",
                    compensation_payload={"workspace_id": "${step_result.workspace_id}"},
                    timeout=60
                ),
                SagaStepRequest(
                    step_id="setup_airtable_base",
                    service_url="http://airtable-gateway:8002",
                    action="bases/create",
                    payload={
                        "workspace_id": "${previous_step.workspace_id}",
                        "base_name": workspace_data.get("name"),
                        "template": workspace_data.get("template", "blank")
                    },
                    compensation_action="bases/delete",
                    compensation_payload={"base_id": "${step_result.base_id}"},
                    timeout=120
                ),
                SagaStepRequest(
                    step_id="configure_permissions",
                    service_url="http://platform-services:8007",
                    action="permissions/setup-workspace",
                    payload={
                        "workspace_id": "${step_result.workspace_id}",
                        "owner_id": workspace_data.get("owner_id"),
                        "team_members": workspace_data.get("team_members", [])
                    },
                    compensation_action="permissions/revoke-workspace",
                    compensation_payload={"workspace_id": "${step_result.workspace_id}"},
                    timeout=45
                ),
                SagaStepRequest(
                    step_id="notify_team",
                    service_url="http://automation-services:8006",
                    action="notifications/workspace-created",
                    payload={
                        "workspace_id": "${step_result.workspace_id}",
                        "workspace_name": workspace_data.get("name"),
                        "team_members": workspace_data.get("team_members", [])
                    },
                    # No compensation needed for notifications
                    timeout=30
                )
            ]
        }
    
    @staticmethod
    def data_sync_workflow(sync_config: Dict[str, Any]) -> Dict[str, Any]:
        """
        Data synchronization between Airtable and external systems
        Steps: Validate Config -> Extract Data -> Transform Data -> Load Data -> Verify Sync
        """
        return {
            "pattern": SagaPattern.ORCHESTRATION,
            "timeout": 1800,  # 30 minutes
            "metadata": {
                "workflow_type": "data_sync",
                "source": sync_config.get("source"),
                "destination": sync_config.get("destination")
            },
            "steps": [
                SagaStepRequest(
                    step_id="validate_sync_config",
                    service_url="http://automation-services:8006",
                    action="sync/validate-config",
                    payload=sync_config,
                    timeout=30
                ),
                SagaStepRequest(
                    step_id="extract_source_data",
                    service_url="http://airtable-gateway:8002",
                    action="data/extract",
                    payload={
                        "base_id": sync_config.get("source_base_id"),
                        "table_id": sync_config.get("source_table_id"),
                        "filters": sync_config.get("filters", {})
                    },
                    timeout=300
                ),
                SagaStepRequest(
                    step_id="transform_data",
                    service_url="http://ai-processing-service:8001",
                    action="transform/process",
                    payload={
                        "data": "${previous_step.extracted_data}",
                        "transformation_rules": sync_config.get("transformations", {})
                    },
                    timeout=600
                ),
                SagaStepRequest(
                    step_id="load_destination_data",
                    service_url="http://airtable-gateway:8002",
                    action="data/load",
                    payload={
                        "base_id": sync_config.get("destination_base_id"),
                        "table_id": sync_config.get("destination_table_id"),
                        "data": "${previous_step.transformed_data}",
                        "mode": sync_config.get("load_mode", "insert")
                    },
                    compensation_action="data/rollback",
                    compensation_payload={
                        "base_id": sync_config.get("destination_base_id"),
                        "table_id": sync_config.get("destination_table_id"),
                        "transaction_id": "${step_result.transaction_id}"
                    },
                    timeout=300
                ),
                SagaStepRequest(
                    step_id="verify_sync",
                    service_url="http://automation-services:8006",
                    action="sync/verify",
                    payload={
                        "source_count": "${step_result.source_count}",
                        "destination_count": "${step_result.destination_count}",
                        "transaction_id": "${previous_step.transaction_id}"
                    },
                    timeout=60
                )
            ]
        }
    
    @staticmethod
    def ai_analysis_workflow(analysis_request: Dict[str, Any]) -> Dict[str, Any]:
        """
        AI-powered data analysis workflow
        Steps: Prepare Data -> Run Analysis -> Generate Report -> Store Results -> Notify User
        """
        return {
            "pattern": SagaPattern.ORCHESTRATION,
            "timeout": 3600,  # 1 hour
            "metadata": {
                "workflow_type": "ai_analysis",
                "analysis_type": analysis_request.get("type"),
                "user_id": analysis_request.get("user_id")
            },
            "steps": [
                SagaStepRequest(
                    step_id="prepare_analysis_data",
                    service_url="http://airtable-gateway:8002",
                    action="data/prepare-for-analysis",
                    payload={
                        "base_id": analysis_request.get("base_id"),
                        "table_ids": analysis_request.get("table_ids", []),
                        "analysis_type": analysis_request.get("type")
                    },
                    timeout=180
                ),
                SagaStepRequest(
                    step_id="run_ai_analysis",
                    service_url="http://ai-processing-service:8001",
                    action="analysis/run",
                    payload={
                        "data": "${previous_step.prepared_data}",
                        "analysis_config": analysis_request.get("config", {}),
                        "type": analysis_request.get("type")
                    },
                    timeout=1800  # 30 minutes for AI processing
                ),
                SagaStepRequest(
                    step_id="generate_report",
                    service_url="http://ai-processing-service:8001",
                    action="reports/generate",
                    payload={
                        "analysis_results": "${previous_step.analysis_results}",
                        "format": analysis_request.get("report_format", "pdf"),
                        "template": analysis_request.get("report_template", "default")
                    },
                    timeout=300
                ),
                SagaStepRequest(
                    step_id="store_results",
                    service_url="http://automation-services:8006",
                    action="storage/save-analysis",
                    payload={
                        "user_id": analysis_request.get("user_id"),
                        "analysis_id": "${step_result.analysis_id}",
                        "results": "${previous_step.analysis_results}",
                        "report_url": "${previous_step.report_url}"
                    },
                    compensation_action="storage/cleanup-analysis",
                    compensation_payload={"analysis_id": "${step_result.analysis_id}"},
                    timeout=60
                ),
                SagaStepRequest(
                    step_id="notify_user",
                    service_url="http://automation-services:8006",
                    action="notifications/analysis-complete",
                    payload={
                        "user_id": analysis_request.get("user_id"),
                        "analysis_id": "${previous_step.analysis_id}",
                        "report_url": "${previous_step.report_url}"
                    },
                    timeout=30
                )
            ]
        }
    
    @staticmethod
    def webhook_processing_workflow(webhook_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Webhook event processing with choreography pattern
        Steps: Validate Webhook -> Process Event -> Update Records -> Trigger Automations
        """
        return {
            "pattern": SagaPattern.CHOREOGRAPHY,
            "timeout": 300,  # 5 minutes
            "metadata": {
                "workflow_type": "webhook_processing",
                "webhook_source": webhook_data.get("source"),
                "event_type": webhook_data.get("event_type")
            },
            "steps": [
                SagaStepRequest(
                    step_id="validate_webhook",
                    service_url="http://automation-services:8006",
                    action="webhooks/validate",
                    payload=webhook_data,
                    timeout=30
                ),
                SagaStepRequest(
                    step_id="process_webhook_event",
                    service_url="http://automation-services:8006",
                    action="webhooks/process",
                    payload={
                        "event_data": webhook_data.get("data", {}),
                        "event_type": webhook_data.get("event_type"),
                        "source": webhook_data.get("source")
                    },
                    timeout=60
                ),
                SagaStepRequest(
                    step_id="update_airtable_records",
                    service_url="http://airtable-gateway:8002",
                    action="records/update-from-webhook",
                    payload={
                        "base_id": webhook_data.get("base_id"),
                        "updates": "${previous_step.record_updates}"
                    },
                    compensation_action="records/revert-webhook-updates",
                    compensation_payload={
                        "base_id": webhook_data.get("base_id"),
                        "transaction_id": "${step_result.transaction_id}"
                    },
                    timeout=90
                ),
                SagaStepRequest(
                    step_id="trigger_automations",
                    service_url="http://automation-services:8006",
                    action="automations/trigger-from-webhook",
                    payload={
                        "event_type": webhook_data.get("event_type"),
                        "affected_records": "${previous_step.affected_records}",
                        "workspace_id": webhook_data.get("workspace_id")
                    },
                    timeout=120
                )
            ]
        }


def get_workflow_template(workflow_type: str, **kwargs) -> Dict[str, Any]:
    """
    Get a workflow template by type
    
    Args:
        workflow_type: Type of workflow (user_registration, workspace_creation, etc.)
        **kwargs: Workflow-specific parameters
    
    Returns:
        Workflow configuration dictionary
    """
    templates = {
        "user_registration": WorkflowTemplates.user_registration_workflow,
        "workspace_creation": WorkflowTemplates.workspace_creation_workflow,
        "data_sync": WorkflowTemplates.data_sync_workflow,
        "ai_analysis": WorkflowTemplates.ai_analysis_workflow,
        "webhook_processing": WorkflowTemplates.webhook_processing_workflow
    }
    
    if workflow_type not in templates:
        raise ValueError(f"Unknown workflow type: {workflow_type}")
    
    return templates[workflow_type](kwargs)


# Common compensation patterns
class CompensationPatterns:
    """Common compensation strategies for different types of operations"""
    
    @staticmethod
    def database_rollback_pattern(transaction_id: str, service_url: str) -> Dict[str, Any]:
        """Standard database transaction rollback"""
        return {
            "action": "database/rollback",
            "payload": {"transaction_id": transaction_id},
            "service_url": service_url
        }
    
    @staticmethod
    def file_cleanup_pattern(file_paths: List[str], service_url: str) -> Dict[str, Any]:
        """Clean up files created during operation"""
        return {
            "action": "files/cleanup",
            "payload": {"file_paths": file_paths},
            "service_url": service_url
        }
    
    @staticmethod
    def notification_cancellation_pattern(notification_id: str, service_url: str) -> Dict[str, Any]:
        """Cancel or retract notifications"""
        return {
            "action": "notifications/cancel",
            "payload": {"notification_id": notification_id},
            "service_url": service_url
        }
    
    @staticmethod
    def cache_invalidation_pattern(cache_keys: List[str], service_url: str) -> Dict[str, Any]:
        """Invalidate cache entries"""
        return {
            "action": "cache/invalidate",
            "payload": {"cache_keys": cache_keys},
            "service_url": service_url
        }