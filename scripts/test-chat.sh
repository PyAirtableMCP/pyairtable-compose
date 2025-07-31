#!/bin/bash
# Test chat functionality

echo "💬 Testing PyAirtable chat functionality..."
echo

# Check if BASE_ID is set
if [ -z "$AIRTABLE_BASE" ]; then
    echo "⚠️  AIRTABLE_BASE environment variable not set"
    echo "Please set it in your .env file or export it:"
    echo "export AIRTABLE_BASE=appXXXXXXXXXXXXXX"
    echo
    AIRTABLE_BASE="appXXXXXXXXXXXXXX"
fi

echo "🤖 Testing chat with base ID: $AIRTABLE_BASE"
echo

# Test chat endpoint
curl -X POST http://localhost:8000/api/chat \
  -H "Content-Type: application/json" \
  -H "X-API-Key: simple-api-key" \
  -d "{
    \"message\": \"List all tables in my Airtable base\",
    \"session_id\": \"test-user-$(date +%s)\",
    \"base_id\": \"$AIRTABLE_BASE\"
  }" | jq '.'

echo
echo "✅ Chat test complete!"
echo "Check the response above for any errors or results."