import { NextRequest, NextResponse } from 'next/server'

interface AirtableValidationRequest {
  personalAccessToken: string
}

export async function POST(request: NextRequest) {
  try {
    const { personalAccessToken }: AirtableValidationRequest = await request.json()

    if (!personalAccessToken) {
      return NextResponse.json(
        { error: 'Personal Access Token is required' },
        { status: 400 }
      )
    }

    // Validate token format
    if (!personalAccessToken.startsWith('pat') && !personalAccessToken.startsWith('key')) {
      return NextResponse.json(
        { error: 'Invalid token format. Token should start with "pat" for Personal Access Tokens.' },
        { status: 400 }
      )
    }

    if (personalAccessToken.length < 17) {
      return NextResponse.json(
        { error: 'Token appears to be too short. Please check your token.' },
        { status: 400 }
      )
    }

    // Test connection to Airtable API
    try {
      const response = await fetch('https://api.airtable.com/v0/meta/bases', {
        headers: {
          'Authorization': `Bearer ${personalAccessToken}`,
          'Content-Type': 'application/json'
        }
      })

      if (!response.ok) {
        if (response.status === 401) {
          return NextResponse.json(
            { error: 'Invalid Personal Access Token. Please check your token and try again.' },
            { status: 401 }
          )
        }
        
        if (response.status === 403) {
          return NextResponse.json(
            { error: 'Token does not have sufficient permissions. Please ensure it has access to bases.' },
            { status: 403 }
          )
        }

        throw new Error(`Airtable API error: ${response.status}`)
      }

      const data = await response.json()
      
      return NextResponse.json({
        success: true,
        message: 'Token validated successfully',
        userInfo: {
          hasAccess: true,
          baseCount: data.bases?.length || 0
        }
      })

    } catch (fetchError) {
      console.error('Airtable API validation error:', fetchError)
      
      return NextResponse.json(
        { error: 'Unable to connect to Airtable. Please check your internet connection and try again.' },
        { status: 503 }
      )
    }

  } catch (error) {
    console.error('Token validation error:', error)
    
    return NextResponse.json(
      { error: 'Failed to validate token. Please try again.' },
      { status: 500 }
    )
  }
}