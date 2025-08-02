#!/bin/bash

# Generate TypeScript types and API client from OpenAPI specs
# Assumes frontend is at ../frontend

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

FRONTEND_DIR="../frontend"
API_BASE_URL="http://localhost:8000"

print_status() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

if [ ! -d "$FRONTEND_DIR" ]; then
    echo "Frontend directory not found. Create it first with:"
    echo "npm run setup:frontend"
    exit 1
fi

print_info "Generating TypeScript types from API..."

# Wait for API to be available
print_info "Checking if API is running..."
if ! curl -s "$API_BASE_URL/api/health" > /dev/null; then
    echo "API is not running. Start it with: ./start.sh"
    exit 1
fi

cd "$FRONTEND_DIR"

# Install openapi-typescript if not present
if ! npx --yes openapi-typescript --version > /dev/null 2>&1; then
    print_info "Installing openapi-typescript..."
    npm install -D openapi-typescript
fi

# Generate types from API Gateway OpenAPI spec
print_info "Generating API types..."
npx openapi-typescript "$API_BASE_URL/openapi.json" --output src/types/api.ts

# Create API client helper
print_info "Creating API client..."
mkdir -p src/services

cat > src/services/api.ts << 'EOF'
import { paths } from '../types/api'

export type ApiClient = {
  chat: (data: paths['/api/chat']['post']['requestBody']['content']['application/json']) => Promise<paths['/api/chat']['post']['responses']['200']['content']['application/json']>
  health: () => Promise<paths['/api/health']['get']['responses']['200']['content']['application/json']>
  tools: () => Promise<paths['/api/tools']['get']['responses']['200']['content']['application/json']>
  airtable: {
    get: (path: string, params?: Record<string, any>) => Promise<any>
    post: (path: string, data: any) => Promise<any>
    patch: (path: string, data: any) => Promise<any>
    delete: (path: string) => Promise<any>
  }
}

const API_BASE_URL = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8000'
const API_KEY = process.env.NEXT_PUBLIC_API_KEY || process.env.PYAIRTABLE_API_KEY || 'REPLACE_WITH_SECURE_API_KEY'

class PyAirtableApiClient implements ApiClient {
  private async request(endpoint: string, options: RequestInit = {}) {
    const response = await fetch(`${API_BASE_URL}${endpoint}`, {
      headers: {
        'Content-Type': 'application/json',
        'X-API-Key': API_KEY,
        ...options.headers,
      },
      ...options,
    })

    if (!response.ok) {
      throw new Error(`HTTP error! status: ${response.status}`)
    }

    return response.json()
  }

  async chat(data: any) {
    return this.request('/api/chat', {
      method: 'POST',
      body: JSON.stringify(data),
    })
  }

  async health() {
    return this.request('/api/health')
  }

  async tools() {
    return this.request('/api/tools')
  }

  airtable = {
    get: (path: string, params?: Record<string, any>) => {
      const url = new URL(`${API_BASE_URL}/api/airtable/${path}`)
      if (params) {
        Object.entries(params).forEach(([key, value]) => {
          url.searchParams.append(key, String(value))
        })
      }
      return this.request(url.pathname + url.search)
    },

    post: (path: string, data: any) =>
      this.request(`/api/airtable/${path}`, {
        method: 'POST',
        body: JSON.stringify(data),
      }),

    patch: (path: string, data: any) =>
      this.request(`/api/airtable/${path}`, {
        method: 'PATCH',
        body: JSON.stringify(data),
      }),

    delete: (path: string) =>
      this.request(`/api/airtable/${path}`, {
        method: 'DELETE',
      }),
  }
}

export const apiClient = new PyAirtableApiClient()
export default apiClient
EOF

# Create React hooks for API
print_info "Creating React hooks..."
cat > src/hooks/useApi.ts << 'EOF'
import { useState, useEffect } from 'react'
import { apiClient } from '../services/api'

export function useHealth() {
  const [health, setHealth] = useState<any>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    const checkHealth = async () => {
      try {
        setLoading(true)
        const result = await apiClient.health()
        setHealth(result)
        setError(null)
      } catch (err) {
        setError(err instanceof Error ? err.message : 'Unknown error')
      } finally {
        setLoading(false)
      }
    }

    checkHealth()
    const interval = setInterval(checkHealth, 30000) // Check every 30s

    return () => clearInterval(interval)
  }, [])

  return { health, loading, error, refetch: () => checkHealth() }
}

export function useChat() {
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const sendMessage = async (message: string, sessionId: string, baseId?: string) => {
    try {
      setLoading(true)
      setError(null)
      
      const result = await apiClient.chat({
        message,
        session_id: sessionId,
        base_id: baseId
      })
      
      return result
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Unknown error')
      throw err
    } finally {
      setLoading(false)
    }
  }

  return { sendMessage, loading, error }
}

export function useAirtableData(basePath: string, params?: Record<string, any>) {
  const [data, setData] = useState<any>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    const fetchData = async () => {
      try {
        setLoading(true)
        const result = await apiClient.airtable.get(basePath, params)
        setData(result)
        setError(null)
      } catch (err) {
        setError(err instanceof Error ? err.message : 'Unknown error')
      } finally {
        setLoading(false)
      }
    }

    fetchData()
  }, [basePath, JSON.stringify(params)])

  return { data, loading, error, refetch: () => fetchData() }
}
EOF

print_status "TypeScript types and API client generated successfully!"
print_info "Generated files:"
print_info "  • src/types/api.ts - TypeScript API types"
print_info "  • src/services/api.ts - API client"  
print_info "  • src/hooks/useApi.ts - React hooks"

cd - > /dev/null