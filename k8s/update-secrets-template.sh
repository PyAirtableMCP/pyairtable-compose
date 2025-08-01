#!/bin/bash

# Template for updating Kubernetes secrets - DO NOT COMMIT ACTUAL VALUES
echo "Updating PyAirtable Kubernetes secrets..."

# Check for required environment variables
if [ -z "$AIRTABLE_TOKEN" ] || [ -z "$AIRTABLE_BASE" ] || [ -z "$GEMINI_API_KEY" ]; then
    echo "Error: Required environment variables not set"
    echo "Please set: AIRTABLE_TOKEN, AIRTABLE_BASE, GEMINI_API_KEY"
    exit 1
fi

# Delete existing secret
kubectl delete secret pyairtable-stack-secrets -n pyairtable --ignore-not-found

# Create new secret with values from environment
kubectl create secret generic pyairtable-stack-secrets \
  --namespace=pyairtable \
  --from-literal=AIRTABLE_TOKEN="${AIRTABLE_TOKEN}" \
  --from-literal=AIRTABLE_PAT="${AIRTABLE_PAT:-$AIRTABLE_TOKEN}" \
  --from-literal=AIRTABLE_BASE="${AIRTABLE_BASE}" \
  --from-literal=GEMINI_API_KEY="${GEMINI_API_KEY}" \
  --from-literal=API_KEY="$(openssl rand -base64 32)" \
  --from-literal=JWT_SECRET="$(openssl rand -base64 32)" \
  --from-literal=NEXTAUTH_SECRET="$(openssl rand -base64 32)" \
  --from-literal=POSTGRES_DB="pyairtable" \
  --from-literal=POSTGRES_USER="postgres" \
  --from-literal=POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-$(openssl rand -base64 32)}" \
  --from-literal=REDIS_PASSWORD="${REDIS_PASSWORD:-$(openssl rand -base64 32)}"

echo "Secrets updated successfully!"

# Restart all deployments to pick up new secrets
echo "Restarting deployments..."
kubectl rollout restart deployment -n pyairtable

echo "Done! Waiting for pods to restart..."
sleep 10
kubectl get pods -n pyairtable