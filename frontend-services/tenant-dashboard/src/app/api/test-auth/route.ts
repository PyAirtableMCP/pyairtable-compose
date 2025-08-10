import { NextRequest, NextResponse } from 'next/server'

export async function GET(req: NextRequest) {
  try {
    console.log('Testing connection to mock auth service...')
    
    const response = await fetch('http://localhost:8009/health', {
      method: 'GET',
      headers: {
        'Content-Type': 'application/json',
      },
    })

    if (!response.ok) {
      return NextResponse.json({ 
        error: 'Mock service not reachable',
        status: response.status 
      }, { status: 500 })
    }

    const data = await response.json()
    console.log('Mock service response:', data)
    
    return NextResponse.json({ 
      success: true, 
      mockService: data,
      message: 'Mock auth service is reachable from Next.js server'
    })
  } catch (error) {
    console.error('Error connecting to mock service:', error)
    return NextResponse.json({ 
      error: 'Failed to connect to mock service',
      details: error instanceof Error ? error.message : 'Unknown error'
    }, { status: 500 })
  }
}

export async function POST(req: NextRequest) {
  try {
    const body = await req.json()
    console.log('Testing login to mock auth service...')
    
    const response = await fetch('http://localhost:8009/auth/login', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body)
    })

    const data = await response.json()
    
    return NextResponse.json({ 
      success: response.ok, 
      status: response.status,
      data: data
    })
  } catch (error) {
    console.error('Error testing login:', error)
    return NextResponse.json({ 
      error: 'Failed to test login',
      details: error instanceof Error ? error.message : 'Unknown error'
    }, { status: 500 })
  }
}