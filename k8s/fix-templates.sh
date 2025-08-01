#!/bin/bash

# Fix Helm template selector label issues

cd /Users/kg/IdeaProjects/pyairtable-compose/k8s/helm/pyairtable-stack/templates

# Define service mappings
declare -A services
services[api-gateway]="api-gateway"
services[llm-orchestrator]="llm-orchestrator"
services[mcp-server]="mcp-server"
services[airtable-gateway]="airtable-gateway"
services[platform-services]="platform-services"
services[automation-services]="automation-services"
services[frontend]="frontend"
services[postgres]="postgres"

for template in "${!services[@]}"; do
    component="${services[$template]}"
    file="${template}.yaml"
    
    if [[ -f "$file" ]]; then
        echo "Fixing $file..."
        
        # Fix selector matchLabels
        sed -i '' "s/{{- include \"pyairtable-stack.serviceSelectorLabels\" \\.Values\\.services\\.$template\\.name | nindent 6 }}/{{- include \"pyairtable-stack.selectorLabels\" . | nindent 6 }}\n      app.kubernetes.io\/component: $component/g" "$file"
        
        # Fix template labels  
        sed -i '' "s/{{- include \"pyairtable-stack.serviceSelectorLabels\" \\.Values\\.services\\.$template\\.name | nindent 8 }}/{{- include \"pyairtable-stack.selectorLabels\" . | nindent 8 }}\n        app.kubernetes.io\/component: $component/g" "$file"
        
        # Fix service selector
        sed -i '' "s/{{- include \"pyairtable-stack.serviceSelectorLabels\" \\.Values\\.services\\.$template\\.name | nindent 4 }}/{{- include \"pyairtable-stack.selectorLabels\" . | nindent 4 }}\n    app.kubernetes.io\/component: $component/g" "$file"
        
        # Also fix any remaining old patterns
        sed -i '' "s/serviceSelectorLabels.*${template}\"/selectorLabels\" ./g" "$file"
        sed -i '' "s/serviceSelectorLabels.*${component}\"/selectorLabels\" ./g" "$file"
    fi
done

# Fix postgres template separately since it's in databases not services
sed -i '' 's/serviceSelectorLabels.*postgres/selectorLabels\" ./g' postgres.yaml

echo "Template fixes completed!"