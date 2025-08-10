"use client"

import React from "react"
import Link from "next/link"
import { useSearchParams } from "next/navigation"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { AlertCircle, RefreshCw, Home, ArrowLeft } from "lucide-react"

// Error codes and messages mapping
const ERROR_MESSAGES = {
  Configuration: {
    title: "Server Configuration Error",
    description: "There's a problem with the server configuration. Please contact support if this persists.",
  },
  AccessDenied: {
    title: "Access Denied",
    description: "You don't have permission to access this resource. Please contact support if you believe this is an error.",
  },
  Verification: {
    title: "Email Verification Required",
    description: "Please check your email and click the verification link before signing in.",
  },
  Default: {
    title: "Authentication Error",
    description: "An error occurred during authentication. Please try again.",
  },
  OAuthSignin: {
    title: "OAuth Sign-in Error",
    description: "There was a problem signing in with your OAuth provider. Please try again or use a different method.",
  },
  OAuthCallback: {
    title: "OAuth Callback Error", 
    description: "There was a problem processing your OAuth sign-in. Please try again.",
  },
  OAuthCreateAccount: {
    title: "Account Creation Failed",
    description: "We couldn't create your account using OAuth. Please try signing up manually or contact support.",
  },
  EmailCreateAccount: {
    title: "Email Account Creation Failed",
    description: "We couldn't create your account with that email address. Please try a different email or contact support.",
  },
  Callback: {
    title: "Callback Error",
    description: "There was a problem during the sign-in callback. Please try signing in again.",
  },
  OAuthAccountNotLinked: {
    title: "Account Not Linked",
    description: "To confirm your identity, sign in with the same account you used originally.",
  },
  EmailSignin: {
    title: "Email Sign-in Failed",
    description: "We couldn't send you a sign-in email. Please try again or use a different sign-in method.",
  },
  CredentialsSignin: {
    title: "Invalid Credentials",
    description: "The email or password you entered is incorrect. Please check your credentials and try again.",
  },
  SessionRequired: {
    title: "Session Required",
    description: "You need to be signed in to access this page. Please sign in and try again.",
  },
}

export default function AuthErrorPage() {
  const searchParams = useSearchParams()
  const error = searchParams.get("error") as keyof typeof ERROR_MESSAGES || "Default"
  
  const errorInfo = ERROR_MESSAGES[error] || ERROR_MESSAGES.Default

  const getErrorAction = (errorType: string) => {
    switch (errorType) {
      case "Verification":
        return (
          <div className="space-y-2">
            <Button asChild className="w-full">
              <Link href="/auth/resend-verification">
                Resend verification email
              </Link>
            </Button>
            <Button variant="outline" asChild className="w-full">
              <Link href="/auth/login">
                <ArrowLeft className="mr-2 h-4 w-4" />
                Back to sign in
              </Link>
            </Button>
          </div>
        )
      case "AccessDenied":
        return (
          <div className="space-y-2">
            <Button asChild className="w-full">
              <Link href="/">
                <Home className="mr-2 h-4 w-4" />
                Go to homepage
              </Link>
            </Button>
            <Button variant="outline" asChild className="w-full">
              <Link href="/contact">
                Contact support
              </Link>
            </Button>
          </div>
        )
      case "OAuthAccountNotLinked":
        return (
          <div className="space-y-2">
            <Button asChild className="w-full">
              <Link href="/auth/login">
                Sign in with original account
              </Link>
            </Button>
            <Button variant="outline" asChild className="w-full">
              <Link href="/auth/register">
                Create new account
              </Link>
            </Button>
          </div>
        )
      case "CredentialsSignin":
        return (
          <div className="space-y-2">
            <Button asChild className="w-full">
              <Link href="/auth/login">
                <ArrowLeft className="mr-2 h-4 w-4" />
                Try signing in again
              </Link>
            </Button>
            <Button variant="outline" asChild className="w-full">
              <Link href="/auth/forgot-password">
                Forgot your password?
              </Link>
            </Button>
          </div>
        )
      default:
        return (
          <div className="space-y-2">
            <Button onClick={() => window.location.reload()} className="w-full">
              <RefreshCw className="mr-2 h-4 w-4" />
              Try again
            </Button>
            <Button variant="outline" asChild className="w-full">
              <Link href="/auth/login">
                <ArrowLeft className="mr-2 h-4 w-4" />
                Back to sign in
              </Link>
            </Button>
          </div>
        )
    }
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-blue-50 to-indigo-100 p-4">
      <Card className="w-full max-w-md">
        <CardHeader className="space-y-1 text-center">
          <div className="mx-auto mb-4 h-12 w-12 bg-red-100 rounded-full flex items-center justify-center">
            <AlertCircle className="h-6 w-6 text-red-600" />
          </div>
          <CardTitle className="text-2xl font-bold">
            {errorInfo.title}
          </CardTitle>
          <CardDescription>
            {errorInfo.description}
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <Alert variant="destructive">
            <AlertCircle className="h-4 w-4" />
            <AlertDescription>
              Error code: {error}
            </AlertDescription>
          </Alert>

          {getErrorAction(error)}

          <div className="pt-4 border-t">
            <div className="text-center text-sm text-muted-foreground">
              <p>
                If this problem persists, please{" "}
                <Link 
                  href="/contact" 
                  className="text-primary hover:underline"
                >
                  contact our support team
                </Link>{" "}
                for assistance.
              </p>
            </div>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}