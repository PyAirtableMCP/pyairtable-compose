import { withAuth } from "next-auth/middleware"
import { NextResponse } from "next/server"

export default withAuth(
  function middleware(req) {
    // Get the pathname of the request
    const { pathname } = req.nextUrl

    // Check if user has completed onboarding
    const hasCompletedOnboarding = req.nextauth.token?.onboardingCompleted

    // Redirect to onboarding if not completed (except for auth routes and onboarding itself)
    if (
      req.nextauth.token &&
      !hasCompletedOnboarding &&
      !pathname.startsWith("/auth") &&
      pathname !== "/auth/onboarding"
    ) {
      return NextResponse.redirect(new URL("/auth/onboarding", req.url))
    }

    // If user has completed onboarding but is trying to access onboarding, redirect to dashboard
    if (
      req.nextauth.token &&
      hasCompletedOnboarding &&
      pathname === "/auth/onboarding"
    ) {
      return NextResponse.redirect(new URL("/", req.url))
    }

    return NextResponse.next()
  },
  {
    callbacks: {
      authorized: ({ token, req }) => {
        const { pathname } = req.nextUrl

        // Allow access to public routes
        if (
          pathname.startsWith("/auth") ||
          pathname.startsWith("/api/auth") ||
          pathname === "/terms" ||
          pathname === "/privacy" ||
          pathname.startsWith("/_next") ||
          pathname.startsWith("/favicon") ||
          pathname === "/manifest.json"
        ) {
          return true
        }

        // Require authentication for all other routes
        return !!token
      },
    },
  }
)

export const config = {
  matcher: [
    /*
     * Match all request paths except for the ones starting with:
     * - _next/static (static files)
     * - _next/image (image optimization files)
     * - favicon.ico (favicon file)
     * - public assets
     */
    "/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)",
  ],
}