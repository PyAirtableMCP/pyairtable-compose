import { useState, useEffect } from "react"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Separator } from "@/components/ui/separator"
import { useAuth } from "@/contexts/AuthContext"
import { useToast } from "@/components/ui/toast"

interface LoginPageProps {
  onNavigateToRegister?: () => void
  onLoginSuccess?: () => void
}

export default function LoginPage({ onNavigateToRegister, onLoginSuccess }: LoginPageProps) {
  const [email, setEmail] = useState("")
  const [password, setPassword] = useState("")
  const [localLoading, setLocalLoading] = useState(false)
  const [validationErrors, setValidationErrors] = useState<Record<string, string>>({})
  
  const { login, error, isLoading, clearError, isAuthenticated } = useAuth()
  const { addToast } = useToast()

  useEffect(() => {
    if (isAuthenticated && onLoginSuccess) {
      onLoginSuccess()
    }
  }, [isAuthenticated, onLoginSuccess])

  useEffect(() => {
    if (error) {
      addToast({
        type: 'error',
        title: 'Login Failed',
        description: error
      })
    }
  }, [error, addToast])

  const validateForm = (): boolean => {
    const errors: Record<string, string> = {}
    
    if (!email.trim()) {
      errors.email = 'Email is required'
    } else if (!/\S+@\S+\.\S+/.test(email)) {
      errors.email = 'Please enter a valid email address'
    }
    
    if (!password) {
      errors.password = 'Password is required'
    } else if (password.length < 6) {
      errors.password = 'Password must be at least 6 characters'
    }
    
    setValidationErrors(errors)
    return Object.keys(errors).length === 0
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    
    // Clear previous errors
    clearError()
    setValidationErrors({})
    
    // Validate form
    if (!validateForm()) {
      return
    }
    
    setLocalLoading(true)
    
    try {
      const success = await login(email, password)
      
      if (success) {
        addToast({
          type: 'success',
          title: 'Welcome back!',
          description: 'You have been successfully logged in.'
        })
        
        // Clear form
        setEmail('')
        setPassword('')
        
        if (onLoginSuccess) {
          onLoginSuccess()
        }
      }
    } catch (err) {
      console.error('Login error:', err)
      addToast({
        type: 'error',
        title: 'Login Failed',
        description: 'An unexpected error occurred. Please try again.'
      })
    } finally {
      setLocalLoading(false)
    }
  }

  const handleInputChange = (field: string, value: string) => {
    if (field === 'email') {
      setEmail(value)
    } else if (field === 'password') {
      setPassword(value)
    }
    
    // Clear validation error for this field
    if (validationErrors[field]) {
      setValidationErrors(prev => ({ ...prev, [field]: '' }))
    }
    
    // Clear auth error when user starts typing
    if (error) {
      clearError()
    }
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-background p-4">
      <Card className="w-full max-w-md">
        <CardHeader className="text-center">
          <CardTitle className="text-2xl font-bold">Welcome back</CardTitle>
          <CardDescription>
            Sign in to your PyAirtable Chat account
          </CardDescription>
        </CardHeader>
        
        <CardContent>
          <form onSubmit={handleSubmit} className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="email">Email</Label>
              <Input
                id="email"
                type="email"
                placeholder="Enter your email"
                value={email}
                onChange={(e) => handleInputChange('email', e.target.value)}
                disabled={isLoading || localLoading}
                required
                className={validationErrors.email ? 'border-red-500 focus:ring-red-500' : ''}
              />
              {validationErrors.email && (
                <p className="text-sm text-red-600">{validationErrors.email}</p>
              )}
            </div>
            
            <div className="space-y-2">
              <Label htmlFor="password">Password</Label>
              <Input
                id="password"
                type="password"
                placeholder="Enter your password"
                value={password}
                onChange={(e) => handleInputChange('password', e.target.value)}
                disabled={isLoading || localLoading}
                required
                className={validationErrors.password ? 'border-red-500 focus:ring-red-500' : ''}
              />
              {validationErrors.password && (
                <p className="text-sm text-red-600">{validationErrors.password}</p>
              )}
            </div>
            
            <Button 
              type="submit" 
              className="w-full" 
              disabled={isLoading || localLoading}
            >
              {isLoading || localLoading ? "Signing in..." : "Sign in"}
            </Button>
          </form>
          
          <div className="mt-4 text-center">
            <button 
              type="button"
              className="text-sm text-muted-foreground hover:text-foreground"
            >
              Forgot your password?
            </button>
          </div>
        </CardContent>
        
        <Separator className="my-4" />
        
        <CardFooter className="text-center">
          <p className="text-sm text-muted-foreground">
            Don't have an account?{" "}
            <button 
              type="button"
              className="text-primary hover:underline font-medium"
              onClick={onNavigateToRegister}
              disabled={isLoading || localLoading}
            >
              Sign up
            </button>
          </p>
        </CardFooter>
      </Card>
    </div>
  )
}