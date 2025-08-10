"use client"

import React, { useState, useEffect } from "react"
import Link from "next/link"
import { useRouter, useSearchParams } from "next/navigation"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Loader2, CheckCircle, AlertCircle, Mail, RefreshCw } from "lucide-react"
import toast from "react-hot-toast"

type VerificationStatus = 'loading' | 'success' | 'error' | 'expired'

export default function VerifyEmailPage() {
  const [status, setStatus] = useState<VerificationStatus>('loading')
  const [error, setError] = useState<string | null>(null)
  const [isResending, setIsResending] = useState(false)
  
  const router = useRouter()
  const searchParams = useSearchParams()
  const token = searchParams.get('token')
  const email = searchParams.get('email')

  useEffect(() => {
    if (!token) {
      setStatus('error')
      setError('Invalid verification link')
      return
    }

    const verifyEmail = async () => {
      try {
        const response = await fetch(`${process.env.NEXT_PUBLIC_AUTH_SERVICE_URL || 'http://localhost:8009'}/auth/verify-email`, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
          },
          body: JSON.stringify({ token }),
        })

        const result = await response.json()

        if (response.ok) {
          setStatus('success')
          toast.success("Email verified successfully!")
        } else {
          if (result.error?.includes('expired')) {
            setStatus('expired')
          } else {
            setStatus('error')
            setError(result.error || 'Verification failed')
          }
        }
      } catch (error) {
        console.error("Email verification error:", error)
        setStatus('error')
        setError('An unexpected error occurred')
      }
    }

    verifyEmail()
  }, [token])

  const handleResendVerification = async () => {
    if (!email) {
      toast.error("No email address provided")
      return
    }

    try {
      setIsResending(true)
      
      const response = await fetch(`${process.env.NEXT_PUBLIC_AUTH_SERVICE_URL || 'http://localhost:8009'}/auth/resend-verification`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ email }),
      })

      const result = await response.json()

      if (response.ok) {
        toast.success("Verification email sent!")
        setStatus('loading') // Reset to loading state
      } else {
        toast.error(result.error || "Failed to resend verification email")
      }
    } catch (error) {
      console.error("Resend verification error:", error)
      toast.error("An unexpected error occurred")
    } finally {
      setIsResending(false)
    }
  }

  const handleContinueToLogin = () => {
    router.push('/auth/login')
  }

  // Loading state
  if (status === 'loading') {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-blue-50 to-indigo-100 p-4">
        <Card className="w-full max-w-md">
          <CardContent className="p-8 text-center">
            <Loader2 className="h-8 w-8 animate-spin mx-auto mb-4 text-primary" />
            <CardTitle className="text-xl mb-2">Verifying your email</CardTitle>
            <CardDescription>
              Please wait while we verify your email address...
            </CardDescription>
          </CardContent>
        </Card>
      </div>
    )
  }

  // Success state
  if (status === 'success') {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-blue-50 to-indigo-100 p-4">
        <Card className="w-full max-w-md">
          <CardHeader className="space-y-1 text-center">
            <div className="mx-auto mb-4 h-12 w-12 bg-green-100 rounded-full flex items-center justify-center">
              <CheckCircle className="h-6 w-6 text-green-600" />
            </div>
            <CardTitle className="text-2xl font-bold">
              Email verified!
            </CardTitle>
            <CardDescription>
              Your email address has been successfully verified. You can now sign in to your account.
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <Button onClick={handleContinueToLogin} className="w-full">
              Continue to sign in
            </Button>
            
            <div className="text-center text-sm text-muted-foreground">
              <p>Welcome to PyAirtable! 🎉</p>
            </div>
          </CardContent>
        </Card>
      </div>
    )
  }

  // Expired token state
  if (status === 'expired') {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-blue-50 to-indigo-100 p-4">
        <Card className="w-full max-w-md">
          <CardHeader className="space-y-1 text-center">
            <div className="mx-auto mb-4 h-12 w-12 bg-yellow-100 rounded-full flex items-center justify-center">
              <Mail className="h-6 w-6 text-yellow-600" />
            </div>
            <CardTitle className="text-2xl font-bold">
              Verification link expired
            </CardTitle>
            <CardDescription>
              This email verification link has expired. We can send you a new one.
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            {email && (
              <>
                <div className="bg-muted rounded-lg p-4 text-sm">
                  <p className="text-center">
                    We'll send a new verification link to:
                  </p>
                  <p className="text-center font-medium mt-1">
                    {email}
                  </p>
                </div>

                <Button 
                  onClick={handleResendVerification}
                  disabled={isResending}
                  className="w-full"
                >
                  {isResending && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                  {isResending ? (
                    <>
                      <RefreshCw className="mr-2 h-4 w-4 animate-spin" />
                      Sending...
                    </>
                  ) : (
                    'Send new verification email'
                  )}
                </Button>
              </>
            )}

            <div className="space-y-2">
              <Button variant="ghost" asChild className="w-full">
                <Link href="/auth/login">
                  Back to sign in
                </Link>
              </Button>
              
              {!email && (
                <Button variant="ghost" asChild className="w-full">
                  <Link href="/auth/register">
                    Create new account
                  </Link>
                </Button>
              )}
            </div>
          </CardContent>
        </Card>
      </div>
    )
  }

  // Error state
  return (
    <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-blue-50 to-indigo-100 p-4">
      <Card className="w-full max-w-md">
        <CardHeader className="space-y-1 text-center">
          <div className="mx-auto mb-4 h-12 w-12 bg-red-100 rounded-full flex items-center justify-center">
            <AlertCircle className="h-6 w-6 text-red-600" />
          </div>
          <CardTitle className="text-2xl font-bold">
            Verification failed
          </CardTitle>
          <CardDescription>
            We couldn't verify your email address with this link.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          {error && (
            <Alert variant="destructive">
              <AlertDescription>{error}</AlertDescription>
            </Alert>
          )}

          <div className="space-y-2">
            {email && (
              <Button 
                onClick={handleResendVerification}
                disabled={isResending}
                className="w-full"
              >
                {isResending && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                Send new verification email
              </Button>
            )}
            
            <Button variant="ghost" asChild className="w-full">
              <Link href="/auth/login">
                Back to sign in
              </Link>
            </Button>
            
            <Button variant="ghost" asChild className="w-full">
              <Link href="/auth/register">
                Create new account
              </Link>
            </Button>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}