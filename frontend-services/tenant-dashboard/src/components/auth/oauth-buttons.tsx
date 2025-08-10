"use client"

import React from 'react'
import { signIn } from 'next-auth/react'
import { Button } from '@/components/ui/button'
import { Separator } from '@/components/ui/separator'
import { Chrome, Github, Loader2 } from 'lucide-react'
import toast from 'react-hot-toast'

interface OAuthButtonsProps {
  isLoading?: boolean
  callbackUrl?: string
  className?: string
}

export function OAuthButtons({
  isLoading = false,
  callbackUrl = "/dashboard",
  className = "",
}: OAuthButtonsProps) {
  const [loadingProvider, setLoadingProvider] = React.useState<string | null>(null)

  const handleOAuthSignIn = async (provider: "google" | "github") => {
    try {
      setLoadingProvider(provider)
      
      const result = await signIn(provider, {
        callbackUrl,
        redirect: false,
      })

      if (result?.error) {
        toast.error(`Failed to sign in with ${provider}`)
        console.error(`${provider} OAuth error:`, result.error)
      }
    } catch (error) {
      console.error(`${provider} OAuth error:`, error)
      toast.error(`Failed to sign in with ${provider}`)
    } finally {
      setLoadingProvider(null)
    }
  }

  return (
    <div className={className}>
      {/* OAuth Buttons */}
      <div className="grid grid-cols-2 gap-3">
        <Button
          variant="outline"
          onClick={() => handleOAuthSignIn("google")}
          disabled={isLoading || loadingProvider !== null}
          className="w-full"
        >
          {loadingProvider === "google" ? (
            <Loader2 className="mr-2 h-4 w-4 animate-spin" />
          ) : (
            <Chrome className="mr-2 h-4 w-4" />
          )}
          Google
        </Button>
        <Button
          variant="outline"
          onClick={() => handleOAuthSignIn("github")}
          disabled={isLoading || loadingProvider !== null}
          className="w-full"
        >
          {loadingProvider === "github" ? (
            <Loader2 className="mr-2 h-4 w-4 animate-spin" />
          ) : (
            <Github className="mr-2 h-4 w-4" />
          )}
          GitHub
        </Button>
      </div>

      {/* Divider */}
      <div className="relative my-4">
        <div className="absolute inset-0 flex items-center">
          <Separator className="w-full" />
        </div>
        <div className="relative flex justify-center text-xs uppercase">
          <span className="bg-background px-2 text-muted-foreground">
            Or continue with email
          </span>
        </div>
      </div>
    </div>
  )
}

// Single OAuth button component
interface SingleOAuthButtonProps {
  provider: "google" | "github"
  isLoading?: boolean
  callbackUrl?: string
  className?: string
  children?: React.ReactNode
}

export function SingleOAuthButton({
  provider,
  isLoading = false,
  callbackUrl = "/dashboard",
  className = "w-full",
  children,
}: SingleOAuthButtonProps) {
  const [isSigningIn, setIsSigningIn] = React.useState(false)

  const handleSignIn = async () => {
    try {
      setIsSigningIn(true)
      
      const result = await signIn(provider, {
        callbackUrl,
        redirect: false,
      })

      if (result?.error) {
        toast.error(`Failed to sign in with ${provider}`)
        console.error(`${provider} OAuth error:`, result.error)
      }
    } catch (error) {
      console.error(`${provider} OAuth error:`, error)
      toast.error(`Failed to sign in with ${provider}`)
    } finally {
      setIsSigningIn(false)
    }
  }

  const Icon = provider === "google" ? Chrome : Github
  const isDisabled = isLoading || isSigningIn

  return (
    <Button
      variant="outline"
      onClick={handleSignIn}
      disabled={isDisabled}
      className={className}
    >
      {isSigningIn ? (
        <Loader2 className="mr-2 h-4 w-4 animate-spin" />
      ) : (
        <Icon className="mr-2 h-4 w-4" />
      )}
      {children || `Continue with ${provider === "google" ? "Google" : "GitHub"}`}
    </Button>
  )
}