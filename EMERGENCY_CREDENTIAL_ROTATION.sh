#!/bin/bash

# EMERGENCY CREDENTIAL ROTATION SCRIPT
# ====================================
# This script contains instructions for rotating all compromised credentials
# Run this script IMMEDIATELY after the security breach has been patched

set -euo pipefail

echo "🚨 EMERGENCY CREDENTIAL ROTATION REQUIRED 🚨"
echo "=============================================="
echo ""

echo "EXPOSED CREDENTIALS THAT MUST BE ROTATED IMMEDIATELY:"
echo ""

echo "1. AIRTABLE CREDENTIALS:"
echo "   - Token: pat[EXPOSED_TOKEN_STARTING_WITH_ewow2o]"
echo "   - Base ID: app[EXPOSED_BASE_ID_STARTING_WITH_VLU]"
echo "   ACTION: Generate new Personal Access Token in Airtable Account Settings"
echo ""

echo "2. GOOGLE GEMINI API KEY:"
echo "   - Key: AIzaSyC[EXPOSED_KEY_ENDING_WITH_b-OxU]"
echo "   ACTION: Disable this key in Google Cloud Console and create new one"
echo ""

echo "3. DATABASE CREDENTIALS:"
echo "   - Password: YyeLlj9TN35HMVVPkjNIubPBm2gH06rD"
echo "   - Redis Password: lqm5n0vctfHu2QeHhMefwVmELHMnXsJI"
echo "   ACTION: Change all database passwords immediately"
echo ""

echo "4. JWT SECRETS:"
echo "   - JWT Secret: bCbuhBNhJM+L2ssclpqgEVVFAu5IcUHjD9+8hbeEmdJu3v88rXUc/5u08uQCLg0JVl5eMx7NwpIypRd78i2ZIw=="
echo "   - Refresh Secret: OR6hln0K4SmJZ0slNVjR7uqz7gocl2SSU79IxrdtAlKJ4+YQqmgB7f2ACQyYFSNzBWtkUA7S/hQKBqU/yRokjQ=="
echo "   ACTION: Generate new 256-bit JWT secrets and invalidate all existing tokens"
echo ""

echo "5. API KEYS:"
echo "   - API Key: pya_6c6666906ed799b6eefdd95f591481ac6248db89f1c03fd8e4a240f5e98620d0"
echo "   - Session Secret: eQcmGcAV0c2D2hSGB9GhGgRyJMDvHQBbzK+W/3Br4II="
echo "   ACTION: Generate new API keys and session secrets"
echo ""

echo "IMMEDIATE ACTIONS REQUIRED:"
echo "=========================="
echo ""

echo "Step 1: Disable Airtable Token"
echo "curl -X DELETE https://airtable.com/v0/meta/whoami \\"
echo "  -H 'Authorization: Bearer [REPLACE_WITH_EXPOSED_AIRTABLE_TOKEN]'"
echo ""

echo "Step 2: Disable Google Gemini API Key"
echo "gcloud services api-keys delete [REPLACE_WITH_EXPOSED_GEMINI_KEY] --project=YOUR_PROJECT_ID"
echo ""

echo "Step 3: Generate New Secure Credentials"
echo "openssl rand -base64 32  # For JWT secrets"
echo "openssl rand -base64 32  # For database passwords"
echo "openssl rand -hex 32     # For API keys"
echo ""

echo "Step 4: Update Production Systems"
echo "- Update all environment variables in production"
echo "- Restart all services to pick up new credentials"
echo "- Invalidate all existing user sessions"
echo ""

echo "Step 5: Security Audit"
echo "- Check access logs for unauthorized usage"
echo "- Monitor for suspicious activity"
echo "- Notify stakeholders of the security incident"
echo ""

echo "SECURITY MONITORING:"
echo "==================="
echo "Monitor these indicators for potential abuse:"
echo "- Unusual API usage patterns"
echo "- Unexpected data access or modifications"
echo "- Failed authentication attempts"
echo "- New or unauthorized integrations"
echo ""

echo "For immediate assistance, contact:"
echo "- Security Team: security@yourcompany.com"
echo "- On-call Engineer: +1-XXX-XXX-XXXX"
echo ""

echo "This script completed at: $(date)"