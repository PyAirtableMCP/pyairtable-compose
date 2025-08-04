"use client"

import React, { useEffect } from "react"
import { useSession } from "next-auth/react"
import posthog from "posthog-js"
import { PostHogProvider as PHProvider } from "posthog-js/react"

// Initialize PostHog
if (typeof window !== "undefined" && process.env.NEXT_PUBLIC_POSTHOG_KEY) {
  posthog.init(process.env.NEXT_PUBLIC_POSTHOG_KEY!, {
    api_host: process.env.NEXT_PUBLIC_POSTHOG_HOST || "https://app.posthog.com",
    person_profiles: "identified_only",
    loaded: (posthog) => {
      if (process.env.NODE_ENV === "development") {
        console.log("PostHog loaded")
      }
    },
    capture_pageview: false, // We'll handle this manually
    capture_pageleave: true,
    autocapture: false, // Disable automatic event capture for privacy
  })
}

interface PostHogProviderProps {
  children: React.ReactNode
}

export function PostHogProvider({ children }: PostHogProviderProps) {
  const { data: session, status } = useSession()

  useEffect(() => {
    if (typeof window === "undefined" || !process.env.NEXT_PUBLIC_POSTHOG_KEY) {
      return
    }

    // Identify user when session is available
    if (status === "authenticated" && session?.user) {
      posthog.identify(session.user.id, {
        email: session.user.email,
        name: session.user.name,
        provider: session.provider,
      })
    }

    // Reset user when session ends
    if (status === "unauthenticated") {
      posthog.reset()
    }
  }, [session, status])

  // Manual pageview tracking for better privacy control
  useEffect(() => {
    if (typeof window === "undefined" || !process.env.NEXT_PUBLIC_POSTHOG_KEY) {
      return
    }

    const handleRouteChange = () => {
      posthog?.capture("$pageview")
    }

    // Capture initial pageview
    handleRouteChange()

    // Listen for route changes (for app router)
    const observer = new MutationObserver(() => {
      if (window.location.href !== (window as any).__lastPostHogUrl) {
        ;(window as any).__lastPostHogUrl = window.location.href
        handleRouteChange()
      }
    })

    observer.observe(document, { subtree: true, childList: true })

    return () => observer.disconnect()
  }, [])

  if (typeof window === "undefined" || !process.env.NEXT_PUBLIC_POSTHOG_KEY) {
    return <>{children}</>
  }

  return <PHProvider client={posthog}>{children}</PHProvider>
}

// Export utility functions for feature flags
export const useFeatureFlag = (flagKey: string, fallback: boolean = false): boolean => {
  const [isEnabled, setIsEnabled] = React.useState(fallback)

  useEffect(() => {
    if (typeof window === "undefined" || !process.env.NEXT_PUBLIC_POSTHOG_KEY) {
      return
    }

    const checkFlag = () => {
      const flagValue = posthog.isFeatureEnabled(flagKey)
      if (typeof flagValue === "boolean") {
        setIsEnabled(flagValue)
      }
    }

    // Check flag value on mount
    checkFlag()

    // Listen for feature flag updates
    posthog.onFeatureFlags(checkFlag)

    return () => {
      // PostHog doesn't provide a way to remove listeners, so we'll rely on component unmount
    }
  }, [flagKey])

  return isEnabled
}

// Track custom events
export const trackEvent = (eventName: string, properties?: Record<string, any>) => {
  if (typeof window === "undefined" || !process.env.NEXT_PUBLIC_POSTHOG_KEY) {
    return
  }

  posthog.capture(eventName, properties)
}

// Get feature flag value (can be string, number, boolean, or object)
export const getFeatureFlag = (flagKey: string, fallback?: any) => {
  if (typeof window === "undefined" || !process.env.NEXT_PUBLIC_POSTHOG_KEY) {
    return fallback
  }

  return posthog.getFeatureFlag(flagKey) ?? fallback
}

// Custom hook for A/B testing
export const useABTest = (flagKey: string, variants: string[], fallback: string = "control") => {
  const [variant, setVariant] = React.useState(fallback)

  useEffect(() => {
    if (typeof window === "undefined" || !process.env.NEXT_PUBLIC_POSTHOG_KEY) {
      return
    }

    const checkVariant = () => {
      const flagValue = posthog.getFeatureFlag(flagKey)
      if (typeof flagValue === "string" && variants.includes(flagValue)) {
        setVariant(flagValue)
      } else {
        setVariant(fallback)
      }
    }

    checkVariant()
    posthog.onFeatureFlags(checkVariant)
  }, [flagKey, variants, fallback])

  return variant
}

// Export PostHog instance for direct access
export { posthog }

// Type declarations for global PostHog
declare global {
  interface Window {
    posthog: typeof posthog
    __lastPostHogUrl: string
  }
}