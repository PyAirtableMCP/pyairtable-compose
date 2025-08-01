#!/bin/bash

# Update Kubernetes secrets with real values
echo "Updating PyAirtable Kubernetes secrets..."

# Delete existing secret
kubectl delete secret pyairtable-stack-secrets -n pyairtable --ignore-not-found

# Create new secret with real values
kubectl create secret generic pyairtable-stack-secrets \
  --namespace=pyairtable \
  --from-literal=AIRTABLE_TOKEN="patYH31WYtE9fnm3M.3d628ed8162ab4f8ec0ec9d23784234ce1af0a054daa8d8318a2b8cd11256e5a" \
  --from-literal=AIRTABLE_BASE="appVLUAubH5cFWhMV" \
  --from-literal=GEMINI_API_KEY="AIzaSyCcz0SOl1Om-EIKJaDx9kVW1OapsWwfBOc" \
  --from-literal=API_KEY="$(openssl rand -base64 32)" \
  --from-literal=JWT_SECRET="$(openssl rand -base64 32)" \
  --from-literal=NEXTAUTH_SECRET="$(openssl rand -base64 32)" \
  --from-literal=POSTGRES_DB="pyairtable" \
  --from-literal=POSTGRES_USER="postgres" \
  --from-literal=POSTGRES_PASSWORD="SuperSecurePassword123!" \
  --from-literal=REDIS_PASSWORD="$(openssl rand -base64 32)"

echo "Secrets updated successfully!"

# Restart all deployments to pick up new secrets
echo "Restarting deployments..."
kubectl rollout restart deployment -n pyairtable

echo "Done! Waiting for pods to restart..."
sleep 10
kubectl get pods -n pyairtable