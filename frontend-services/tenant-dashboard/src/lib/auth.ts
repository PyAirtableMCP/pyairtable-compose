import NextAuth from "next-auth"
import { PrismaAdapter } from "@auth/prisma-adapter"
import { PrismaClient } from "@prisma/client"
import GoogleProvider from "next-auth/providers/google"
import GitHubProvider from "next-auth/providers/github"
import CredentialsProvider from "next-auth/providers/credentials"
import bcrypt from "bcryptjs"
import { z } from "zod"

const prisma = new PrismaClient()

// Validation schemas
const loginSchema = z.object({
  email: z.string().email(),
  password: z.string().min(8),
})

export const { handlers, auth, signIn, signOut } = NextAuth({
  adapter: PrismaAdapter(prisma),
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

          // Find user in database
          const user = await prisma.user.findUnique({
            where: { email },
            select: {
              id: true,
              email: true,
              name: true,
              image: true,
              password: true,
              emailVerified: true,
            },
          })

          if (!user || !user.password) {
            return null
          }

          // Verify password
          const isValid = await bcrypt.compare(password, user.password)
          if (!isValid) {
            return null
          }

          // Return user object (password excluded)
          return {
            id: user.id,
            email: user.email,
            name: user.name,
            image: user.image,
            emailVerified: user.emailVerified,
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
        token.emailVerified = user.emailVerified
      }
      
      if (account) {
        token.accessToken = account.access_token
        token.provider = account.provider
      }

      return token
    },
    async session({ session, token }) {
      // Send properties to the client
      if (token) {
        session.user.id = token.id as string
        session.user.emailVerified = token.emailVerified as Date | null
        session.accessToken = token.accessToken as string
        session.provider = token.provider as string
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
    provider?: string
    user: {
      id: string
      email: string
      name?: string | null
      image?: string | null
      emailVerified?: Date | null
    }
  }

  interface User {
    emailVerified?: Date | null
  }
}

declare module "next-auth/jwt" {
  interface JWT {
    id?: string
    accessToken?: string
    provider?: string
    emailVerified?: Date | null
  }
}