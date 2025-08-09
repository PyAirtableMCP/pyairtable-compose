import { useState } from "react"
import { AuthProvider } from "@/contexts/AuthContext"
import { ToastProvider } from "@/components/ui/toast"
import { ProtectedRoute } from "@/components/ProtectedRoute"
import { ChatInterface } from "@/components/chat/ChatInterface"
import LoginPage from "@/pages/LoginPage"
import RegisterPage from "@/pages/RegisterPage"
import { useAuth } from "@/contexts/AuthContext"

type AppState = 'login' | 'register' | 'chat'

// Main app component wrapped with providers
function App() {
  return (
    <ToastProvider>
      <AuthProvider>
        <AppRouter />
      </AuthProvider>
    </ToastProvider>
  )
}

// Router component that uses authentication context
function AppRouter() {
  const [appState, setAppState] = useState<AppState>('login')
  const { isAuthenticated, isLoading } = useAuth()

  // If user is authenticated, automatically show chat
  // Otherwise, respect the current app state for login/register
  const currentView = isAuthenticated ? 'chat' : appState

  const handleLoginSuccess = () => {
    setAppState('chat')
  }

  const handleNavigateToRegister = () => {
    setAppState('register')
  }

  const handleNavigateToLogin = () => {
    setAppState('login')
  }

  const handleRegistrationSuccess = () => {
    // After successful registration, show login page
    setAppState('login')
  }

  // Show loading screen while checking authentication
  if (isLoading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-background">
        <div className="flex flex-col items-center space-y-4">
          <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-primary"></div>
          <p className="text-muted-foreground">Loading PyAirtable Chat...</p>
        </div>
      </div>
    )
  }

  switch (currentView) {
    case 'login':
      return (
        <LoginPage 
          onNavigateToRegister={handleNavigateToRegister}
          onLoginSuccess={handleLoginSuccess}
        />
      )
    case 'register':
      return (
        <RegisterPage 
          onNavigateToLogin={handleNavigateToLogin}
          onRegistrationSuccess={handleRegistrationSuccess}
        />
      )
    case 'chat':
      return (
        <ProtectedRoute fallback={
          <LoginPage 
            onNavigateToRegister={handleNavigateToRegister}
            onLoginSuccess={handleLoginSuccess}
          />
        }>
          <ChatInterface />
        </ProtectedRoute>
      )
    default:
      return (
        <LoginPage 
          onNavigateToRegister={handleNavigateToRegister}
          onLoginSuccess={handleLoginSuccess}
        />
      )
  }
}

export default App
