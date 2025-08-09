import { useState, useEffect } from "react"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Separator } from "@/components/ui/separator"
import { useAuth } from "@/contexts/AuthContext"
import { useToast } from "@/components/ui/toast"

interface RegisterPageProps {
  onNavigateToLogin?: () => void
  onRegistrationSuccess?: () => void
}

export default function RegisterPage({ onNavigateToLogin, onRegistrationSuccess }: RegisterPageProps) {
  const [formData, setFormData] = useState({
    name: "",
    email: "",
    password: "",
    confirmPassword: ""
  })
  const [localLoading, setLocalLoading] = useState(false)
  const [errors, setErrors] = useState<Record<string, string>>({})
  
  const { register, error, isLoading, clearError } = useAuth()
  const { addToast } = useToast()

  const handleChange = (field: string, value: string) => {
    setFormData(prev => ({ ...prev, [field]: value }))
    
    // Clear validation error for this field
    if (errors[field]) {
      setErrors(prev => ({ ...prev, [field]: "" }))
    }
    
    // Clear auth error when user starts typing
    if (error) {
      clearError()
    }
  }

  useEffect(() => {
    if (error) {
      addToast({
        type: 'error',
        title: 'Registration Failed',
        description: error
      })
    }
  }, [error, addToast])

  const validateForm = () => {
    const newErrors: Record<string, string> = {}
    
    if (!formData.name.trim()) {
      newErrors.name = "Full name is required"
    } else if (formData.name.trim().length < 2) {
      newErrors.name = "Name must be at least 2 characters"
    }
    
    if (!formData.email.trim()) {
      newErrors.email = "Email is required"
    } else if (!/\S+@\S+\.\S+/.test(formData.email)) {
      newErrors.email = "Please enter a valid email address"
    }
    
    if (!formData.password) {
      newErrors.password = "Password is required"
    } else if (formData.password.length < 8) {
      newErrors.password = "Password must be at least 8 characters"
    } else if (!/(?=.*[a-z])(?=.*[A-Z])(?=.*\d)/.test(formData.password)) {
      newErrors.password = "Password must contain uppercase, lowercase, and number"
    }
    
    if (!formData.confirmPassword) {
      newErrors.confirmPassword = "Please confirm your password"
    } else if (formData.password !== formData.confirmPassword) {
      newErrors.confirmPassword = "Passwords do not match"
    }
    
    setErrors(newErrors)
    return Object.keys(newErrors).length === 0
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    
    // Clear previous errors
    clearError()
    
    if (!validateForm()) {
      return
    }
    
    setLocalLoading(true)
    
    try {
      const success = await register(formData.name, formData.email, formData.password)
      
      if (success) {
        addToast({
          type: 'success',
          title: 'Account Created!',
          description: 'Your account has been created successfully. Please log in to continue.'
        })
        
        // Clear form
        setFormData({
          name: "",
          email: "",
          password: "",
          confirmPassword: ""
        })
        
        // Navigate to login page after successful registration
        if (onNavigateToLogin) {
          setTimeout(() => {
            onNavigateToLogin()
          }, 1000) // Give user time to see success message
        }
        
        if (onRegistrationSuccess) {
          onRegistrationSuccess()
        }
      }
    } catch (err) {
      console.error('Registration error:', err)
      addToast({
        type: 'error',
        title: 'Registration Failed',
        description: 'An unexpected error occurred. Please try again.'
      })
    } finally {
      setLocalLoading(false)
    }
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-background p-4">
      <Card className="w-full max-w-md">
        <CardHeader className="text-center">
          <CardTitle className="text-2xl font-bold">Create Account</CardTitle>
          <CardDescription>
            Join PyAirtable Chat to get started
          </CardDescription>
        </CardHeader>
        
        <CardContent>
          <form onSubmit={handleSubmit} className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="name">Full Name</Label>
              <Input
                id="name"
                type="text"
                placeholder="Enter your full name"
                value={formData.name}
                onChange={(e) => handleChange("name", e.target.value)}
                disabled={isLoading || localLoading}
                required
                className={errors.name ? 'border-red-500 focus:ring-red-500' : ''}
              />
              {errors.name && (
                <p className="text-sm text-destructive">{errors.name}</p>
              )}
            </div>
            
            <div className="space-y-2">
              <Label htmlFor="email">Email</Label>
              <Input
                id="email"
                type="email"
                placeholder="Enter your email"
                value={formData.email}
                onChange={(e) => handleChange("email", e.target.value)}
                disabled={isLoading || localLoading}
                required
                className={errors.email ? 'border-red-500 focus:ring-red-500' : ''}
              />
              {errors.email && (
                <p className="text-sm text-destructive">{errors.email}</p>
              )}
            </div>
            
            <div className="space-y-2">
              <Label htmlFor="password">Password</Label>
              <Input
                id="password"
                type="password"
                placeholder="Create a password (min 8 chars)"
                value={formData.password}
                onChange={(e) => handleChange("password", e.target.value)}
                disabled={isLoading || localLoading}
                required
                className={errors.password ? 'border-red-500 focus:ring-red-500' : ''}
              />
              {errors.password && (
                <p className="text-sm text-destructive">{errors.password}</p>
              )}
            </div>
            
            <div className="space-y-2">
              <Label htmlFor="confirmPassword">Confirm Password</Label>
              <Input
                id="confirmPassword"
                type="password"
                placeholder="Confirm your password"
                value={formData.confirmPassword}
                onChange={(e) => handleChange("confirmPassword", e.target.value)}
                disabled={isLoading || localLoading}
                required
                className={errors.confirmPassword ? 'border-red-500 focus:ring-red-500' : ''}
              />
              {errors.confirmPassword && (
                <p className="text-sm text-destructive">{errors.confirmPassword}</p>
              )}
            </div>
            
            <Button 
              type="submit" 
              className="w-full" 
              disabled={isLoading || localLoading}
            >
              {isLoading || localLoading ? "Creating account..." : "Create account"}
            </Button>
          </form>
        </CardContent>
        
        <Separator className="my-4" />
        
        <CardFooter className="text-center">
          <p className="text-sm text-muted-foreground">
            Already have an account?{" "}
            <button 
              type="button"
              className="text-primary hover:underline font-medium"
              onClick={onNavigateToLogin}
              disabled={isLoading || localLoading}
            >
              Sign in
            </button>
          </p>
        </CardFooter>
      </Card>
    </div>
  )
}