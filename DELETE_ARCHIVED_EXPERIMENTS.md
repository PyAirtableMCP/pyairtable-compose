# Archived Experiments Deletion Log

**Date**: 2025-08-11  
**Action**: Removing archived-experiments directory  
**Reason**: Failed/abandoned experimental services consuming repo space

## What's Being Deleted

The archived-experiments directory contains 9 failed service attempts:

1. **pyairtable-ai-domain** - Early AI service attempt (superseded by llm-orchestrator)
2. **pyairtable-airtable-domain** - Domain service experiment (superseded by airtable-gateway)  
3. **pyairtable-api-gateway-go** - Early Go gateway attempt (superseded by current api-gateway)
4. **pyairtable-auth-service-go** - Auth service attempt (superseded by current auth-service)
5. **pyairtable-automation-domain** - Automation service attempt (functionality moved to workflow-engine)
6. **pyairtable-automation-services** - Another automation attempt (consolidated)
7. **pyairtable-data-service-go** - Data service attempt (functionality in airtable-gateway)
8. **pyairtable-table-service-go** - Table service attempt (functionality in airtable-gateway)
9. **pyairtable-user-service-go** - User service attempt (superseded by current user-service)

## Impact Assessment

- **Space Savings**: ~50MB of obsolete code
- **Clarity**: Removes confusion about which services are active
- **Maintenance**: No need to maintain broken/incomplete services
- **Focus**: Team can focus on the 16 core working services

## Safety Check

- All functionality has been moved to current working services
- No running Docker containers reference these services
- No active code imports from these directories
- Git history preserved for future reference if needed

## Post-Deletion Actions

- Update .gitignore if needed
- Verify Docker Compose files don't reference deleted services
- Confirm no import statements point to deleted code

**Status**: Ready for deletion