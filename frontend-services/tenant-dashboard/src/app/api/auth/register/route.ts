import { NextRequest, NextResponse } from "next/server"
import { z } from "zod"

// Auth service base URL
const AUTH_SERVICE_URL = process.env.AUTH_SERVICE_URL || "http://localhost:8007"

const registerSchema = z.object({
  name: z.string().min(2, "Name must be at least 2 characters"),
  email: z.string().email("Please enter a valid email address"),
  password: z.string()
    .min(8, "Password must be at least 8 characters")
    .regex(/^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)/, 
      "Password must contain at least one uppercase letter, one lowercase letter, and one number"),
})

export async function POST(request: NextRequest) {
  try {
    const body = await request.json()
    
    // Validate input
    const validatedData = registerSchema.parse(body)
    const { name, email, password } = validatedData

    // Split name into first and last name
    const nameParts = name.split(' ')
    const firstName = nameParts[0] || name
    const lastName = nameParts.slice(1).join(' ') || 'User'

    // Call auth service to register user
    const response = await fetch(`${AUTH_SERVICE_URL}/auth/register`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        email,
        password,
        first_name: firstName,
        last_name: lastName,
        tenant_id: "550e8400-e29b-41d4-a716-446655440000", // Default tenant ID
      }),
    })

    if (!response.ok) {
      const errorData = await response.json().catch(() => ({ error: "Registration failed" }))
      return NextResponse.json(
        { error: errorData.error || "Registration failed" },
        { status: response.status }
      )
    }

    const user = await response.json()

    return NextResponse.json(
      { 
        message: "User created successfully",
        user: {
          id: user.id,
          name: `${user.first_name} ${user.last_name}`,
          email: user.email,
        }
      },
      { status: 201 }
    )
  } catch (error) {
    console.error("Registration error:", error)

    // Handle validation errors
    if (error instanceof z.ZodError) {
      return NextResponse.json(
        { error: error.errors[0].message },
        { status: 400 }
      )
    }

    return NextResponse.json(
      { error: "Internal server error" },
      { status: 500 }
    )
  }
}