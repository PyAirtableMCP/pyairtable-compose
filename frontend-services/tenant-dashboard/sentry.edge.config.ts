import * as Sentry from "@sentry/nextjs"

Sentry.init({
  dsn: process.env.NEXT_PUBLIC_SENTRY_DSN,
  
  // Performance Monitoring (lighter for edge runtime)
  tracesSampleRate: process.env.NODE_ENV === "production" ? 0.05 : 1.0,
  
  // Environment
  environment: process.env.NEXT_PUBLIC_APP_ENV || process.env.NODE_ENV,
  
  // Release tracking
  release: process.env.NEXT_PUBLIC_APP_VERSION || "unknown",
  
  // Edge-specific settings
  beforeSend(event) {
    // Minimal filtering for edge runtime to avoid performance impact
    if (process.env.NODE_ENV === "production") {
      // Only filter critical errors that could spam
      if (event.exception?.values?.[0]?.value?.includes("AbortError")) {
        return null
      }
    }
    
    return event
  },
  
  // Edge context
  initialScope: {
    tags: {
      component: "tenant-dashboard-edge",
      runtime: "edge",
    },
  },
  
  // Privacy settings
  sendDefaultPii: false,
  
  // Debug settings
  debug: false, // Keep disabled for edge runtime performance
})