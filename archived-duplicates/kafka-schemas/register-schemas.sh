#!/bin/bash

# Script to register Avro schemas with Confluent Schema Registry
# This ensures schema evolution and compatibility for PyAirtable events

set -e

SCHEMA_REGISTRY_URL="http://localhost:8081"
SCHEMA_DIR="/kafka-schemas"

echo "Registering Avro schemas with Schema Registry at $SCHEMA_REGISTRY_URL"

# Function to register a schema
register_schema() {
    local subject="$1"
    local schema_file="$2"
    local compatibility="${3:-BACKWARD}"
    
    echo "Registering schema for subject: $subject"
    
    # Set compatibility level
    curl -X PUT -H "Content-Type: application/vnd.schemaregistry.v1+json" \
        --data "{\"compatibility\": \"$compatibility\"}" \
        "$SCHEMA_REGISTRY_URL/config/$subject" || echo "Failed to set compatibility for $subject"
    
    # Register schema
    local schema_content=$(cat "$schema_file" | jq -c .)
    local payload=$(jq -n --arg schema "$schema_content" '{schema: $schema}')
    
    curl -X POST -H "Content-Type: application/vnd.schemaregistry.v1+json" \
        --data "$payload" \
        "$SCHEMA_REGISTRY_URL/subjects/$subject/versions"
    
    echo "Schema registered for subject: $subject"
    echo "---"
}

# Wait for Schema Registry to be ready
echo "Waiting for Schema Registry to be ready..."
until curl -f -s "$SCHEMA_REGISTRY_URL/subjects" > /dev/null; do
    echo "Waiting for Schema Registry..."
    sleep 5
done
echo "Schema Registry is ready!"

# Register base event schema
register_schema "pyairtable-base-event-value" "$SCHEMA_DIR/event-base.avsc" "FULL"

# Register authentication event schemas
echo "Registering authentication event schemas..."
register_schema "pyairtable.auth.events-value" "$SCHEMA_DIR/auth-events.avsc" "BACKWARD"

# Register Airtable event schemas
echo "Registering Airtable event schemas..."
register_schema "pyairtable.airtable.events-value" "$SCHEMA_DIR/airtable-events.avsc" "BACKWARD"

# Register workflow event schemas
echo "Registering workflow event schemas..."
register_schema "pyairtable.workflows.events-value" "$SCHEMA_DIR/workflow-events.avsc" "BACKWARD"

# Register SAGA event schemas
echo "Registering SAGA event schemas..."
register_schema "pyairtable.saga.events-value" "$SCHEMA_DIR/saga-events.avsc" "BACKWARD"

# Register command schemas (for CQRS)
echo "Registering command schemas..."
cat > "$SCHEMA_DIR/commands.avsc" << 'EOF'
{
  "type": "record",
  "name": "BaseCommand",
  "namespace": "io.pyairtable.commands",
  "doc": "Base schema for all PyAirtable commands",
  "fields": [
    {
      "name": "command_id",
      "type": "string",
      "doc": "Unique identifier for this command"
    },
    {
      "name": "command_type",
      "type": "string",
      "doc": "Type of the command"
    },
    {
      "name": "aggregate_id",
      "type": "string",
      "doc": "Target aggregate identifier"
    },
    {
      "name": "aggregate_type",
      "type": "string",
      "doc": "Type of the target aggregate"
    },
    {
      "name": "timestamp",
      "type": "long",
      "logicalType": "timestamp-millis",
      "doc": "When the command was issued"
    },
    {
      "name": "issued_by",
      "type": "string",
      "doc": "ID of the user or system that issued the command"
    },
    {
      "name": "tenant_id",
      "type": ["null", "string"],
      "default": null,
      "doc": "Tenant identifier"
    },
    {
      "name": "correlation_id",
      "type": ["null", "string"],
      "default": null,
      "doc": "Correlation identifier"
    },
    {
      "name": "payload",
      "type": "string",
      "doc": "Command payload (JSON string)"
    },
    {
      "name": "expected_version",
      "type": ["null", "long"],
      "default": null,
      "doc": "Expected version of the aggregate for optimistic concurrency"
    },
    {
      "name": "metadata",
      "type": {
        "type": "map",
        "values": "string"
      },
      "default": {},
      "doc": "Additional command metadata"
    }
  ]
}
EOF

register_schema "pyairtable.commands-value" "$SCHEMA_DIR/commands.avsc" "BACKWARD"

# Register dead letter queue schema
echo "Registering dead letter queue schema..."
cat > "$SCHEMA_DIR/dlq-events.avsc" << 'EOF'
{
  "type": "record",
  "name": "DeadLetterEvent",
  "namespace": "io.pyairtable.events.dlq",
  "doc": "Schema for events that failed processing and ended up in the dead letter queue",
  "fields": [
    {
      "name": "dlq_id",
      "type": "string",
      "doc": "Unique identifier for this DLQ entry"
    },
    {
      "name": "original_topic",
      "type": "string",
      "doc": "Original topic where the message was published"
    },
    {
      "name": "original_partition",
      "type": ["null", "int"],
      "default": null,
      "doc": "Original partition number"
    },
    {
      "name": "original_offset",
      "type": ["null", "long"],
      "default": null,
      "doc": "Original offset in the partition"
    },
    {
      "name": "original_key",
      "type": ["null", "string"],
      "default": null,
      "doc": "Original message key"
    },
    {
      "name": "original_payload",
      "type": "string",
      "doc": "Original message payload"
    },
    {
      "name": "original_headers",
      "type": {
        "type": "map",
        "values": "string"
      },
      "default": {},
      "doc": "Original message headers"
    },
    {
      "name": "failure_timestamp",
      "type": "long",
      "logicalType": "timestamp-millis",
      "doc": "When the message failed processing"
    },
    {
      "name": "failure_reason",
      "type": "string",
      "doc": "Reason for the failure"
    },
    {
      "name": "error_message",
      "type": ["null", "string"],
      "default": null,
      "doc": "Detailed error message"
    },
    {
      "name": "retry_count",
      "type": "int",
      "default": 0,
      "doc": "Number of times processing was retried"
    },
    {
      "name": "processing_service",
      "type": ["null", "string"],
      "default": null,
      "doc": "Service that was processing the message"
    },
    {
      "name": "stack_trace",
      "type": ["null", "string"],
      "default": null,
      "doc": "Stack trace of the error (if available)"
    }
  ]
}
EOF

register_schema "pyairtable.dlq.events-value" "$SCHEMA_DIR/dlq-events.avsc" "BACKWARD"

# Register analytics event schema
echo "Registering analytics event schema..."
cat > "$SCHEMA_DIR/analytics-events.avsc" << 'EOF'
{
  "type": "record",
  "name": "AnalyticsEvent",
  "namespace": "io.pyairtable.events.analytics",
  "doc": "Schema for analytics and metrics events",
  "fields": [
    {
      "name": "event_id",
      "type": "string",
      "doc": "Unique identifier for this analytics event"
    },
    {
      "name": "event_type",
      "type": "string",
      "doc": "Type of analytics event (page_view, action, metric, etc.)"
    },
    {
      "name": "timestamp",
      "type": "long",
      "logicalType": "timestamp-millis",
      "doc": "When the event occurred"
    },
    {
      "name": "user_id",
      "type": ["null", "string"],
      "default": null,
      "doc": "ID of the user who triggered the event"
    },
    {
      "name": "session_id",
      "type": ["null", "string"],
      "default": null,
      "doc": "Session identifier"
    },
    {
      "name": "tenant_id",
      "type": ["null", "string"],
      "default": null,
      "doc": "Tenant identifier"
    },
    {
      "name": "source",
      "type": "string",
      "doc": "Source of the event (web, mobile, api)"
    },
    {
      "name": "properties",
      "type": {
        "type": "map",
        "values": "string"
      },
      "default": {},
      "doc": "Event properties and dimensions"
    },
    {
      "name": "metrics",
      "type": {
        "type": "map",
        "values": "double"
      },
      "default": {},
      "doc": "Numeric metrics associated with the event"
    },
    {
      "name": "context",
      "type": {
        "type": "map",
        "values": "string"
      },
      "default": {},
      "doc": "Contextual information (device, location, etc.)"
    }
  ]
}
EOF

register_schema "pyairtable.analytics.events-value" "$SCHEMA_DIR/analytics-events.avsc" "BACKWARD"

echo "All schemas registered successfully!"

# List all registered subjects
echo "Registered subjects:"
curl -s "$SCHEMA_REGISTRY_URL/subjects" | jq -r '.[]' | sort

echo "Schema registration completed!"
echo ""
echo "To verify schema compatibility when evolving schemas, use:"
echo "curl -X POST -H 'Content-Type: application/vnd.schemaregistry.v1+json' \\"
echo "  --data '{\"schema\": \"...\"}' \\"
echo "  '$SCHEMA_REGISTRY_URL/compatibility/subjects/{subject}/versions/latest'"