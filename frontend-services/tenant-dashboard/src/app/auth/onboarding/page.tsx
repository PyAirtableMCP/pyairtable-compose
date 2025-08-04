"use client"

import React, { useState } from "react"
import { useSession } from "next-auth/react"
import { useRouter } from "next/navigation"
import { useForm } from "react-hook-form"
import { zodResolver } from "@hookform/resolvers/zod"
import { z } from "zod"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Progress } from "@/components/ui/progress"
import { Badge } from "@/components/ui/badge"
import { Separator } from "@/components/ui/separator"
import { 
  Loader2, 
  Key, 
  Database, 
  CheckCircle, 
  ArrowRight, 
  ArrowLeft,
  Zap,
  Users,
  Globe
} from "lucide-react"
import toast from "react-hot-toast"

// Validation schemas for each step
const airtableConfigSchema = z.object({
  personalAccessToken: z.string().min(1, "Personal Access Token is required"),
  baseId: z.string().optional(),
})

const organizationSchema = z.object({
  organizationName: z.string().min(2, "Organization name must be at least 2 characters"),
  role: z.enum(["founder", "developer", "manager", "analyst", "other"]),
  teamSize: z.enum(["1", "2-10", "11-50", "51-200", "200+"]),
})

type AirtableConfigForm = z.infer<typeof airtableConfigSchema>
type OrganizationForm = z.infer<typeof organizationSchema>

interface OnboardingState {
  step: number
  airtableConfig: Partial<AirtableConfigForm>
  organization: Partial<OrganizationForm>
  selectedFeatures: string[]
}

const TOTAL_STEPS = 4

const AVAILABLE_FEATURES = [
  {
    id: "chat",
    name: "Natural Language Queries",
    description: "Ask questions about your data in plain English",
    icon: <Zap className="h-5 w-5" />,
    category: "core"
  },
  {
    id: "formulas",
    name: "Advanced Formulas",
    description: "Create complex calculations and transformations",
    icon: <Database className="h-5 w-5" />,
    category: "core"
  },
  {
    id: "webhooks",
    name: "Real-time Webhooks",
    description: "Get notified when your data changes",
    icon: <Globe className="h-5 w-5" />,
    category: "integration"
  },
  {
    id: "collaboration",
    name: "Team Collaboration",
    description: "Share insights and work together on data",
    icon: <Users className="h-5 w-5" />,
    category: "team"
  },
]

export default function OnboardingPage() {
  const { data: session, status } = useSession()
  const router = useRouter()
  
  const [state, setState] = useState<OnboardingState>({
    step: 1,
    airtableConfig: {},
    organization: {},
    selectedFeatures: ["chat", "formulas"], // Pre-select core features
  })
  
  const [isLoading, setIsLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  // Redirect if not authenticated
  if (status === "loading") {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <Loader2 className="h-8 w-8 animate-spin" />
      </div>
    )
  }

  if (status === "unauthenticated") {
    router.push("/auth/login")
    return null
  }

  const nextStep = () => {
    setState(prev => ({ ...prev, step: Math.min(prev.step + 1, TOTAL_STEPS) }))
    setError(null)
  }

  const prevStep = () => {
    setState(prev => ({ ...prev, step: Math.max(prev.step - 1, 1) }))
    setError(null)
  }

  const updateState = (updates: Partial<OnboardingState>) => {
    setState(prev => ({ ...prev, ...updates }))
  }

  const completeOnboarding = async () => {
    try {
      setIsLoading(true)
      setError(null)

      // Save onboarding data
      const response = await fetch("/api/onboarding/complete", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          airtableConfig: state.airtableConfig,
          organization: state.organization,
          selectedFeatures: state.selectedFeatures,
        }),
      })

      if (!response.ok) {
        const result = await response.json()
        throw new Error(result.error || "Failed to complete onboarding")
      }

      toast.success("Welcome to PyAirtable! 🎉")
      router.push("/")
      router.refresh()
    } catch (error) {
      console.error("Onboarding completion error:", error)
      setError(error instanceof Error ? error.message : "An unexpected error occurred")
    } finally {
      setIsLoading(false)
    }
  }

  const renderStep = () => {
    switch (state.step) {
      case 1:
        return <WelcomeStep user={session?.user} onNext={nextStep} />
      
      case 2:
        return (
          <AirtableConfigStep
            data={state.airtableConfig}
            onUpdate={(data) => updateState({ airtableConfig: data })}
            onNext={nextStep}
            onPrev={prevStep}
            error={error}
            setError={setError}
          />
        )
      
      case 3:
        return (
          <OrganizationStep
            data={state.organization}
            onUpdate={(data) => updateState({ organization: data })}
            onNext={nextStep}
            onPrev={prevStep}
          />
        )
      
      case 4:
        return (
          <FeatureSelectionStep
            selectedFeatures={state.selectedFeatures}
            onUpdate={(features) => updateState({ selectedFeatures: features })}
            onComplete={completeOnboarding}
            onPrev={prevStep}
            isLoading={isLoading}
            error={error}
          />
        )
      
      default:
        return null
    }
  }

  return (
    <div className="min-h-screen bg-gradient-to-br from-blue-50 to-indigo-100 p-4">
      <div className="max-w-2xl mx-auto">
        {/* Progress Header */}
        <div className="mb-8">
          <div className="flex items-center justify-between mb-4">
            <h1 className="text-2xl font-bold">Getting Started</h1>
            <Badge variant="secondary">Step {state.step} of {TOTAL_STEPS}</Badge>
          </div>
          <Progress value={(state.step / TOTAL_STEPS) * 100} className="h-2" />
        </div>

        {/* Step Content */}
        {renderStep()}
      </div>
    </div>
  )
}

// Welcome Step Component
function WelcomeStep({ user, onNext }: { user: any; onNext: () => void }) {
  return (
    <Card>
      <CardHeader className="text-center">
        <CardTitle className="text-3xl">Welcome to PyAirtable! 👋</CardTitle>
        <CardDescription className="text-lg">
          Hi {user?.name || user?.email}, let&apos;s get you set up in just a few steps.
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-6">
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          <div className="text-center p-4 rounded-lg bg-blue-50">
            <Key className="h-8 w-8 mx-auto mb-2 text-blue-600" />
            <h3 className="font-medium">Connect Airtable</h3>
            <p className="text-sm text-muted-foreground">
              Link your Airtable account
            </p>
          </div>
          <div className="text-center p-4 rounded-lg bg-green-50">
            <Users className="h-8 w-8 mx-auto mb-2 text-green-600" />
            <h3 className="font-medium">Set Up Organization</h3>
            <p className="text-sm text-muted-foreground">
              Tell us about your team
            </p>
          </div>
          <div className="text-center p-4 rounded-lg bg-purple-50">
            <Zap className="h-8 w-8 mx-auto mb-2 text-purple-600" />
            <h3 className="font-medium">Choose Features</h3>
            <p className="text-sm text-muted-foreground">
              Pick what you need most
            </p>
          </div>
        </div>
        
        <Button onClick={onNext} className="w-full" size="lg">
          Let&apos;s Get Started
          <ArrowRight className="ml-2 h-4 w-4" />
        </Button>
      </CardContent>
    </Card>
  )
}

// Airtable Configuration Step
function AirtableConfigStep({ 
  data, 
  onUpdate, 
  onNext, 
  onPrev, 
  error, 
  setError 
}: {
  data: Partial<AirtableConfigForm>
  onUpdate: (data: Partial<AirtableConfigForm>) => void
  onNext: () => void
  onPrev: () => void
  error: string | null
  setError: (error: string | null) => void
}) {
  const [isValidating, setIsValidating] = useState(false)
  
  const { register, handleSubmit, formState: { errors } } = useForm<AirtableConfigForm>({
    resolver: zodResolver(airtableConfigSchema),
    defaultValues: data,
  })

  const onSubmit = async (formData: AirtableConfigForm) => {
    try {
      setIsValidating(true)
      setError(null)

      // Validate the PAT by making a test request
      const response = await fetch("/api/airtable/validate", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ personalAccessToken: formData.personalAccessToken }),
      })

      const result = await response.json()

      if (!response.ok) {
        setError(result.error || "Invalid Personal Access Token")
        return
      }

      onUpdate(formData)
      toast.success("Airtable connection verified!")
      onNext()
    } catch (error) {
      setError("Failed to validate Airtable connection")
    } finally {
      setIsValidating(false)
    }
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <Key className="h-6 w-6" />
          Connect Your Airtable Account
        </CardTitle>
        <CardDescription>
          We need your Personal Access Token to securely connect to your Airtable bases.
        </CardDescription>
      </CardHeader>
      <CardContent>
        <form onSubmit={handleSubmit(onSubmit)} className="space-y-4">
          {error && (
            <Alert variant="destructive">
              <AlertDescription>{error}</AlertDescription>
            </Alert>
          )}

          <div className="space-y-2">
            <label className="text-sm font-medium">
              Personal Access Token *
            </label>
            <Input
              {...register("personalAccessToken")}
              type="password"
              placeholder="pat123456789abcdef..."
              className="font-mono"
            />
            {errors.personalAccessToken && (
              <p className="text-sm text-destructive">
                {errors.personalAccessToken.message}
              </p>
            )}
            <p className="text-xs text-muted-foreground">
              <a 
                href="https://airtable.com/create/tokens" 
                target="_blank" 
                rel="noopener noreferrer"
                className="text-primary hover:underline"
              >
                Create a Personal Access Token
              </a> in your Airtable account settings.
            </p>
          </div>

          <div className="flex gap-3">
            <Button type="button" variant="outline" onClick={onPrev}>
              <ArrowLeft className="mr-2 h-4 w-4" />
              Back
            </Button>
            <Button type="submit" disabled={isValidating} className="flex-1">
              {isValidating && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
              Verify & Continue
              <ArrowRight className="ml-2 h-4 w-4" />
            </Button>
          </div>
        </form>
      </CardContent>
    </Card>
  )
}

// Organization Setup Step  
function OrganizationStep({ 
  data, 
  onUpdate, 
  onNext, 
  onPrev 
}: {
  data: Partial<OrganizationForm>
  onUpdate: (data: Partial<OrganizationForm>) => void
  onNext: () => void
  onPrev: () => void
}) {
  const { register, handleSubmit, formState: { errors } } = useForm<OrganizationForm>({
    resolver: zodResolver(organizationSchema),
    defaultValues: data,
  })

  const onSubmit = (formData: OrganizationForm) => {
    onUpdate(formData)
    onNext()
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <Users className="h-6 w-6" />
          Tell Us About Your Organization
        </CardTitle>
        <CardDescription>
          This helps us customize your experience and provide relevant features.
        </CardDescription>
      </CardHeader>
      <CardContent>
        <form onSubmit={handleSubmit(onSubmit)} className="space-y-4">
          <div className="space-y-2">
            <label className="text-sm font-medium">
              Organization Name *
            </label>
            <Input
              {...register("organizationName")}
              placeholder="Your company or team name"
            />
            {errors.organizationName && (
              <p className="text-sm text-destructive">
                {errors.organizationName.message}
              </p>
            )}
          </div>

          <div className="space-y-2">
            <label className="text-sm font-medium">
              Your Role *
            </label>
            <select 
              {...register("role")} 
              className="w-full p-2 border rounded-md"
            >
              <option value="">Select your role</option>
              <option value="founder">Founder/CEO</option>
              <option value="developer">Developer</option>
              <option value="manager">Manager</option>
              <option value="analyst">Data Analyst</option>
              <option value="other">Other</option>
            </select>
            {errors.role && (
              <p className="text-sm text-destructive">
                {errors.role.message}
              </p>
            )}
          </div>

          <div className="space-y-2">
            <label className="text-sm font-medium">
              Team Size *
            </label>
            <select 
              {...register("teamSize")} 
              className="w-full p-2 border rounded-md"
            >
              <option value="">Select team size</option>
              <option value="1">Just me</option>
              <option value="2-10">2-10 people</option>
              <option value="11-50">11-50 people</option>
              <option value="51-200">51-200 people</option>
              <option value="200+">200+ people</option>
            </select>
            {errors.teamSize && (
              <p className="text-sm text-destructive">
                {errors.teamSize.message}
              </p>
            )}
          </div>

          <div className="flex gap-3">
            <Button type="button" variant="outline" onClick={onPrev}>
              <ArrowLeft className="mr-2 h-4 w-4" />
              Back
            </Button>
            <Button type="submit" className="flex-1">
              Continue
              <ArrowRight className="ml-2 h-4 w-4" />
            </Button>
          </div>
        </form>
      </CardContent>
    </Card>
  )
}

// Feature Selection Step
function FeatureSelectionStep({ 
  selectedFeatures, 
  onUpdate, 
  onComplete, 
  onPrev, 
  isLoading, 
  error 
}: {
  selectedFeatures: string[]
  onUpdate: (features: string[]) => void
  onComplete: () => void
  onPrev: () => void
  isLoading: boolean
  error: string | null
}) {
  const toggleFeature = (featureId: string) => {
    const newFeatures = selectedFeatures.includes(featureId)
      ? selectedFeatures.filter(id => id !== featureId)
      : [...selectedFeatures, featureId]
    onUpdate(newFeatures)
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <Zap className="h-6 w-6" />
          Choose Your Features
        </CardTitle>
        <CardDescription>
          Select the features you&apos;d like to start with. You can always enable more later.
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-6">
        {error && (
          <Alert variant="destructive">
            <AlertDescription>{error}</AlertDescription>
          </Alert>
        )}

        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          {AVAILABLE_FEATURES.map((feature) => (
            <div
              key={feature.id}
              className={`p-4 border rounded-lg cursor-pointer transition-colors ${
                selectedFeatures.includes(feature.id)
                  ? "border-primary bg-primary/5"
                  : "border-muted hover:border-primary/50"
              }`}
              onClick={() => toggleFeature(feature.id)}
            >
              <div className="flex items-start gap-3">
                {selectedFeatures.includes(feature.id) && (
                  <CheckCircle className="h-5 w-5 text-primary mt-0.5" />
                )}
                {feature.icon}
                <div className="flex-1">
                  <h3 className="font-medium">{feature.name}</h3>
                  <p className="text-sm text-muted-foreground">
                    {feature.description}
                  </p>
                </div>
              </div>
            </div>
          ))}
        </div>

        <Separator />

        <div className="flex gap-3">
          <Button type="button" variant="outline" onClick={onPrev}>
            <ArrowLeft className="mr-2 h-4 w-4" />
            Back
          </Button>
          <Button 
            onClick={onComplete} 
            disabled={isLoading || selectedFeatures.length === 0}
            className="flex-1"
          >
            {isLoading && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
            Complete Setup
            <CheckCircle className="ml-2 h-4 w-4" />
          </Button>
        </div>
      </CardContent>
    </Card>
  )
}