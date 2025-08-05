import NextAuth from "next-auth"
import GoogleProvider from "next-auth/providers/google"
import GitHubProvider from "next-auth/providers/github"
import CredentialsProvider from "next-auth/providers/credentials"
import { z } from "zod"

// Validation schemas
const loginSchema = z.object({
  email: z.string().email(),
  password: z.string().min(8),
})

// Auth service base URL
const AUTH_SERVICE_URL = process.env.AUTH_SERVICE_URL || "http://localhost:8007"

export const { handlers, auth, signIn, signOut } = NextAuth({
  session: {
    strategy: "jwt",
    maxAge: 30 * 24 * 60 * 60, // 30 days
  },
  pages: {
    signIn: "/auth/login",
    signUp: "/auth/register",
    error: "/auth/error",
    verifyRequest: "/auth/verify-request",
  },
  providers: [
    GoogleProvider({
      clientId: process.env.GOOGLE_CLIENT_ID!,
      clientSecret: process.env.GOOGLE_CLIENT_SECRET!,
      allowDangerousEmailAccountLinking: true,
    }),
    GitHubProvider({
      clientId: process.env.GITHUB_CLIENT_ID!,
      clientSecret: process.env.GITHUB_CLIENT_SECRET!,
      allowDangerousEmailAccountLinking: true,
    }),
    CredentialsProvider({
      name: "credentials",
      credentials: {
        email: { label: "Email", type: "email" },
        password: { label: "Password", type: "password" },
      },
      async authorize(credentials) {
        try {
          // Validate input
          const { email, password } = loginSchema.parse(credentials)

          // Call our auth service
          const response = await fetch(`${AUTH_SERVICE_URL}/auth/login`, {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
            },
            body: JSON.stringify({ email, password }),
          })

          if (!response.ok) {
            console.error("Auth service login failed:", response.status)
            return null
          }

          const authResult = await response.json()

          // Decode JWT to get user info
          const jwtPayload = JSON.parse(Buffer.from(authResult.access_token.split('.')[1], 'base64').toString())

          // Return user object with tokens
          return {
            id: jwtPayload.user_id,
            email: jwtPayload.email,
            name: jwtPayload.email.split('@')[0], // Fallback name
            accessToken: authResult.access_token,
            refreshToken: authResult.refresh_token,
            role: jwtPayload.role,
            tenantId: jwtPayload.tenant_id,
          }
        } catch (error) {
          console.error("Auth error:", error)
          return null
        }
      },
    }),
  ],
  callbacks: {
    async jwt({ token, user, account }) {
      // Persist the OAuth account info and user info to the token right after signin
      if (user) {
        token.id = user.id
        token.email = user.email
        token.name = user.name
        token.role = user.role
        token.tenantId = user.tenantId
        token.accessToken = user.accessToken
        token.refreshToken = user.refreshToken
      }
      
      if (account) {
        token.provider = account.provider
      }

      return token
    },
    async session({ session, token }) {
      // Send properties to the client
      if (token) {
        session.user.id = token.id as string
        session.user.email = token.email as string
        session.user.name = token.name as string
        session.accessToken = token.accessToken as string
        session.refreshToken = token.refreshToken as string
        session.provider = token.provider as string
        session.user.role = token.role as string
        session.user.tenantId = token.tenantId as string
      }

      return session
    },
    async signIn({ user, account, profile, email, credentials }) {
      // Allow OAuth sign ins
      if (account?.provider === "google" || account?.provider === "github") {
        return true
      }

      // Allow credentials sign in (handled in authorize callback)
      if (account?.provider === "credentials") {
        return true
      }

      return false
    },
    async redirect({ url, baseUrl }) {
      // Allows relative callback URLs
      if (url.startsWith("/")) return `${baseUrl}${url}`
      // Allows callback URLs on the same origin
      else if (new URL(url).origin === baseUrl) return url
      return baseUrl
    },
  },
  events: {
    async signIn({ user, account, isNewUser }) {
      console.log(`User ${user.email} signed in with ${account?.provider}`)
      
      // Track sign in event with PostHog
      if (typeof window !== 'undefined' && window.posthog) {
        window.posthog.identify(user.id, {
          email: user.email,
          name: user.name,
          provider: account?.provider,
        })
        window.posthog.capture('user_signed_in', {
          provider: account?.provider,
          is_new_user: isNewUser,
        })
      }
    },
    async signOut({ session, token }) {
      console.log(`User signed out`)
      
      // Track sign out event
      if (typeof window !== 'undefined' && window.posthog) {
        window.posthog.capture('user_signed_out')
        window.posthog.reset()
      }
    },
  },
  debug: process.env.NODE_ENV === "development",
})

// Helper function to get server-side session
export async function getServerSession() {
  return await auth()
}

// Types for better TypeScript support
declare module "next-auth" {
  interface Session {
    accessToken?: string
    refreshToken?: string
    provider?: string
    user: {
      id: string
      email: string
      name?: string | null
      image?: string | null
      role?: string
      tenantId?: string
    }
  }

  interface User {
    accessToken?: string
    refreshToken?: string  
    role?: string
    tenantId?: string
  }
}

declare module "next-auth/jwt" {
  interface JWT {
    id?: string
    email?: string
    name?: string
    accessToken?: string
    refreshToken?: string
    provider?: string
    role?: string
    tenantId?: string
  }
}