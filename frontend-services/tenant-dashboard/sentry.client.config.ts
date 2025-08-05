import * as Sentry from "@sentry/nextjs"

Sentry.init({
  dsn: process.env.NEXT_PUBLIC_SENTRY_DSN,
  
  // Performance Monitoring
  tracesSampleRate: process.env.NODE_ENV === "production" ? 0.1 : 1.0,
  
  // Profiling
  profilesSampleRate: process.env.NODE_ENV === "production" ? 0.1 : 1.0,
  
  // Environment
  environment: process.env.NEXT_PUBLIC_APP_ENV || process.env.NODE_ENV,
  
  // Release tracking
  release: process.env.NEXT_PUBLIC_APP_VERSION || "unknown",
  
  // Error filtering
  beforeSend(event) {
    // Filter out development errors in production
    if (process.env.NODE_ENV === "production") {
      // Don't send chunk load errors (common in development)
      if (
        event.exception?.values?.[0]?.value?.includes("Loading chunk") ||
        event.exception?.values?.[0]?.value?.includes("ChunkLoadError")
      ) {
        return null
      }
      
      // Don't send network errors that are outside our control
      if (
        event.exception?.values?.[0]?.value?.includes("NetworkError") ||
        event.exception?.values?.[0]?.value?.includes("Failed to fetch")
      ) {
        return null
      }
    }
    
    return event
  },
  
  // User context integration
  initialScope: {
    tags: {
      component: "tenant-dashboard",
    },
  },
  
  // Integrations
  integrations: [
    new Sentry.Replay({
      // Mask all text content, but capture network requests and DOM interactions
      maskAllText: true,
      blockAllMedia: true,
      // Only record sessions with errors in production
      sessionSampleRate: process.env.NODE_ENV === "production" ? 0 : 0.1,
      errorSampleRate: process.env.NODE_ENV === "production" ? 1.0 : 1.0,
    }),
    new Sentry.BrowserTracing({
      // Performance monitoring disabled for Next.js
      // routingInstrumentation: Sentry.reactRouterV6Instrumentation(
      //   React.useEffect,
      //   useLocation,
      //   useNavigationType,
      //   createRoutesFromChildren,
      //   matchRoutes
      // ),
    }),
  ],
  
  // Privacy settings
  sendDefaultPii: false,
  
  // Debug settings
  debug: process.env.NODE_ENV === "development",
})

// Import React Router dependencies
import React, { useEffect } from "react"
// import { useLocation, useNavigationType, createRoutesFromChildren, matchRoutes } from "react-router-dom"