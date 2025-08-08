import { NextRequest, NextResponse } from 'next/server'

interface AirtableBasesRequest {
  personalAccessToken: string
}

export async function POST(request: NextRequest) {
  try {
    const { personalAccessToken }: AirtableBasesRequest = await request.json()

    if (!personalAccessToken) {
      return NextResponse.json(
        { error: 'Personal Access Token is required' },
        { status: 400 }
      )
    }

    // Fetch bases from Airtable
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
            { error: 'Invalid Personal Access Token' },
            { status: 401 }
          )
        }
        
        if (response.status === 403) {
          return NextResponse.json(
            { error: 'Insufficient permissions to access bases' },
            { status: 403 }
          )
        }

        throw new Error(`Airtable API error: ${response.status}`)
      }

      const data = await response.json()
      
      // Transform the data to our expected format
      const bases = data.bases?.map((base: any) => ({
        id: base.id,
        name: base.name,
        permissionLevel: base.permissionLevel || 'read',
        tableCount: base.tables?.length || 0,
        recordCount: null, // We'll need separate API calls to get record counts
        createdTime: new Date().toISOString(), // Airtable doesn't provide this in the bases endpoint
        description: base.description || null
      })) || []

      // For demonstration purposes, let's add some mock data if no bases found
      if (bases.length === 0) {
        return NextResponse.json({
          bases: [
            {
              id: 'demo_base_1',
              name: 'Demo Customer Database',
              permissionLevel: 'read',
              tableCount: 3,
              recordCount: 1234,
              createdTime: new Date().toISOString(),
              description: 'A sample customer database for demonstration'
            },
            {
              id: 'demo_base_2',
              name: 'Demo Sales Tracker',
              permissionLevel: 'write',
              tableCount: 2,
              recordCount: 892,
              createdTime: new Date().toISOString(),
              description: 'Track sales performance and metrics'
            }
          ]
        })
      }

      return NextResponse.json({ bases })

    } catch (fetchError) {
      console.error('Airtable API bases error:', fetchError)
      
      return NextResponse.json(
        { error: 'Unable to fetch bases from Airtable. Please try again.' },
        { status: 503 }
      )
    }

  } catch (error) {
    console.error('Bases fetch error:', error)
    
    return NextResponse.json(
      { error: 'Failed to fetch bases. Please try again.' },
      { status: 500 }
    )
  }
}