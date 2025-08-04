import * as Sentry from "@sentry/nextjs"

Sentry.init({
  dsn: process.env.NEXT_PUBLIC_SENTRY_DSN,
  
  // Performance Monitoring
  tracesSampleRate: process.env.NODE_ENV === "production" ? 0.1 : 1.0,
  
  // Profiling (server-side)
  profilesSampleRate: process.env.NODE_ENV === "production" ? 0.1 : 1.0,
  
  // Environment
  environment: process.env.NEXT_PUBLIC_APP_ENV || process.env.NODE_ENV,
  
  // Release tracking
  release: process.env.NEXT_PUBLIC_APP_VERSION || "unknown",
  
  // Server-specific settings
  beforeSend(event) {
    // Filter out development/build-time errors in production
    if (process.env.NODE_ENV === "production") {
      // Don't send Next.js build errors
      if (
        event.exception?.values?.[0]?.value?.includes("Module not found") ||
        event.exception?.values?.[0]?.value?.includes("Cannot resolve module")
      ) {
        return null
      }
    }
    
    return event
  },
  
  // Server context
  initialScope: {
    tags: {
      component: "tenant-dashboard-server",
      nodejs: process.version,
    },
  },
  
  // Privacy settings
  sendDefaultPii: false,
  
  // Server-side integrations
  integrations: [
    new Sentry.ProfilingIntegration(),
  ],
  
  // Debug settings
  debug: process.env.NODE_ENV === "development",
})