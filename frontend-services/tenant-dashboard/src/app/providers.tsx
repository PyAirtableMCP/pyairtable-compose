"use client";

import React from "react";
import { SessionProvider } from "next-auth/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
// import { ReactQueryDevtools } from "@tanstack/react-query-devtools";
import { Toaster } from "react-hot-toast";
// Temporarily disabled: import { PostHogProvider } from "./posthog-provider";
import { ErrorBoundary } from "@/components/error-boundary";
import { handleAsyncError } from "@/components/error-boundary";
import { PWAPrompts, ConnectionStatus } from "@/components/pwa/PWAPrompts";

interface ProvidersProps {
  children: React.ReactNode;
}

export function Providers({ children }: ProvidersProps) {
  const [queryClient] = React.useState(
    () =>
      new QueryClient({
        defaultOptions: {
          queries: {
            staleTime: 60 * 1000, // 1 minute
            gcTime: 5 * 60 * 1000, // 5 minutes (formerly cacheTime)
            retry: (failureCount, error) => {
              // Don't retry on 4xx errors (except 408, 409, 429)
              if (error && typeof error === "object" && "status" in error) {
                const status = (error as any).status;
                if (status >= 400 && status < 500 && ![408, 409, 429].includes(status)) {
                  return false;
                }
              }
              return failureCount < 3;
            },
            refetchOnWindowFocus: false,
            refetchOnReconnect: true,
            onError: (error) => {
              // Automatically report React Query errors to Sentry
              handleAsyncError(error as Error, "react-query");
            },
          },
          mutations: {
            retry: 1,
            onError: (error) => {
              // Automatically report mutation errors to Sentry
              handleAsyncError(error as Error, "react-query-mutation");
            },
          },
        },
      })
  );

  return (
    <ErrorBoundary
      showDetails={process.env.NODE_ENV === "development"}
      onError={(error, errorInfo) => {
        // Additional error handling if needed
        console.error("Root error boundary triggered:", error, errorInfo);
      }}
    >
      <SessionProvider>
        {/* Temporarily disabled: <PostHogProvider> */}
          <QueryClientProvider client={queryClient}>
            {children}
            <Toaster
              position="top-right"
              toastOptions={{
                duration: 4000,
                style: {
                  background: "hsl(var(--background))",
                  color: "hsl(var(--foreground))",
                  border: "1px solid hsl(var(--border))",
                },
                success: {
                  iconTheme: {
                    primary: "hsl(var(--primary))",
                    secondary: "hsl(var(--primary-foreground))",
                  },
                },
                error: {
                  iconTheme: {
                    primary: "hsl(var(--destructive))",
                    secondary: "hsl(var(--destructive-foreground))",
                  },
                },
              }}
            />
            {/* Development tools disabled */}
            {/* process.env.NODE_ENV === "development" && (
              <ReactQueryDevtools initialIsOpen={false} />
            ) */}
            
            {/* PWA Components */}
            <ConnectionStatus />
            <PWAPrompts showInstallBanner={true} autoShowInstallDialog={false} />
          </QueryClientProvider>
        {/* Temporarily disabled: </PostHogProvider> */}
      </SessionProvider>
    </ErrorBoundary>
  );
}