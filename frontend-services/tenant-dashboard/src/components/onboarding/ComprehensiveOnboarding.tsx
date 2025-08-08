"use client"

import React, { useState, useEffect } from "react"
import { useSession } from "next-auth/react"
import { useRouter } from "next/navigation"
import { useForm } from "react-hook-form"
import { zodResolver } from "@hookform/resolvers/zod"
import { z } from "zod"
import { motion, AnimatePresence } from "framer-motion"
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
  Globe,
  Play,
  Pause,
  Volume2,
  VolumeX,
  ChevronRight,
  Target,
  Lightbulb,
  Rocket,
  Award,
  HelpCircle,
  Star,
  MessageSquare,
  BarChart3,
  Shield,
  Clock,
  Cpu,
  TrendingUp,
  FileText,
  Link,
  Settings,
  Eye,
  CheckCheck,
  AlertTriangle,
  Info,
  BookOpen,
  Wand2,
  Brain,
  Github
} from "lucide-react"
import toast from "react-hot-toast"

// Enhanced validation schemas
const airtableConfigSchema = z.object({
  personalAccessToken: z.string().min(1, "Personal Access Token is required"),
  baseId: z.string().optional(),
})

const organizationSchema = z.object({
  organizationName: z.string().min(2, "Organization name must be at least 2 characters"),
  role: z.enum(["founder", "developer", "manager", "analyst", "other"]),
  teamSize: z.enum(["1", "2-10", "11-50", "51-200", "200+"]),
  industry: z.string().optional(),
  useCase: z.string().optional(),
})

type AirtableConfigForm = z.infer<typeof airtableConfigSchema>
type OrganizationForm = z.infer<typeof organizationSchema>

interface OnboardingState {
  step: number
  airtableConfig: Partial<AirtableConfigForm>
  organization: Partial<OrganizationForm>
  selectedFeatures: string[]
  completedMilestones: string[]
  skipTutorial: boolean
  userType: 'beginner' | 'intermediate' | 'advanced'
  selectedBases: AirtableBase[]
  firstQueryCompleted: boolean
  tourProgress: number
  preferences: UserPreferences
}

interface AirtableBase {
  id: string
  name: string
  tableCount: number
  recordCount: number
  permissions: string[]
  selected?: boolean
  tableStructure?: AirtableTable[]
}

interface AirtableTable {
  id: string
  name: string
  primaryField: string
  fields: AirtableField[]
  recordCount: number
}

interface AirtableField {
  id: string
  name: string
  type: string
  options?: any
}

interface UserPreferences {
  theme: 'light' | 'dark' | 'system'
  emailNotifications: boolean
  tourTooltips: boolean
  advancedMode: boolean
}

interface OnboardingMilestone {
  id: string
  title: string
  description: string
  completed: boolean
  icon: React.ReactNode
  points: number
  category: 'setup' | 'learning' | 'engagement' | 'mastery'
}

const TOTAL_STEPS = 7

const MILESTONES: OnboardingMilestone[] = [
  {
    id: 'profile_setup',
    title: 'Complete Profile Setup',
    description: 'Fill in your organization details and preferences',
    completed: false,
    icon: <Users className="h-4 w-4" />,
    points: 100,
    category: 'setup'
  },
  {
    id: 'airtable_connected',
    title: 'Connect Airtable',
    description: 'Successfully link your Airtable account and select bases',
    completed: false,
    icon: <Database className="h-4 w-4" />,
    points: 200,
    category: 'setup'
  },
  {
    id: 'first_query',
    title: 'First AI Query',
    description: 'Ask your first question to the AI assistant',
    completed: false,
    icon: <MessageSquare className="h-4 w-4" />,
    points: 150,
    category: 'learning'
  },
  {
    id: 'tour_completed',
    title: 'Complete Product Tour',
    description: 'Finish the interactive product walkthrough',
    completed: false,
    icon: <BookOpen className="h-4 w-4" />,
    points: 100,
    category: 'learning'
  },
  {
    id: 'automation_created',
    title: 'Create First Automation',
    description: 'Set up your first workflow or automation',
    completed: false,
    icon: <Zap className="h-4 w-4" />,
    points: 300,
    category: 'mastery'
  },
  {
    id: 'team_invited',
    title: 'Invite Team Members',
    description: 'Add colleagues to your workspace',
    completed: false,
    icon: <Users className="h-4 w-4" />,
    points: 250,
    category: 'engagement'
  },
  {
    id: 'advanced_feature',
    title: 'Use Advanced Feature',
    description: 'Try formula creation or advanced querying',
    completed: false,
    icon: <Brain className="h-4 w-4" />,
    points: 400,
    category: 'mastery'
  }
]

const AVAILABLE_FEATURES = [
  {
    id: "chat",
    name: "Natural Language Queries",
    description: "Ask questions about your data in plain English",
    icon: <MessageSquare className="h-5 w-5" />,
    category: "core",
    difficulty: "beginner"
  },
  {
    id: "formulas",
    name: "Advanced Formulas",
    description: "Create complex calculations and transformations",
    icon: <Cpu className="h-5 w-5" />,
    category: "core",
    difficulty: "intermediate"
  },
  {
    id: "webhooks",
    name: "Real-time Webhooks",
    description: "Get notified when your data changes",
    icon: <Globe className="h-5 w-5" />,
    category: "integration",
    difficulty: "advanced"
  },
  {
    id: "collaboration",
    name: "Team Collaboration",
    description: "Share insights and work together on data",
    icon: <Users className="h-5 w-5" />,
    category: "team",
    difficulty: "beginner"
  },
  {
    id: "automation",
    name: "Workflow Automation",
    description: "Automate repetitive tasks and processes",
    icon: <Zap className="h-5 w-5" />,
    category: "productivity",
    difficulty: "intermediate"
  },
  {
    id: "analytics",
    name: "Advanced Analytics",
    description: "Generate insights and reports from your data",
    icon: <BarChart3 className="h-5 w-5" />,
    category: "analytics",
    difficulty: "intermediate"
  },
  {
    id: "api",
    name: "API Integration",
    description: "Connect with external services and tools",
    icon: <Link className="h-5 w-5" />,
    category: "integration",
    difficulty: "advanced"
  },
  {
    id: "ai_insights",
    name: "AI-Powered Insights",
    description: "Get intelligent recommendations and predictions",
    icon: <Brain className="h-5 w-5" />,
    category: "ai",
    difficulty: "intermediate"
  }
]

const PRODUCT_TOUR_STEPS = [
  {
    id: "overview",
    title: "Platform Overview",
    description: "Welcome to PyAirtable! Let's explore the key features that will transform how you work with your data.",
    content: "PyAirtable combines the power of AI with the flexibility of Airtable to create a seamless data management experience.",
    media: "/onboarding/overview-demo.mp4",
    duration: 60
  },
  {
    id: "chat_interface",
    title: "Natural Language Queries",
    description: "Ask questions about your data using natural language - no SQL required!",
    content: "Simply type questions like 'Show me sales from last month' or 'Which customers haven't ordered recently?'",
    media: "/onboarding/chat-demo.mp4",
    duration: 45
  },
  {
    id: "data_insights",
    title: "AI-Powered Insights",
    description: "Get intelligent recommendations and automated insights from your data.",
    content: "Our AI analyzes your data patterns and suggests optimizations, identifies trends, and highlights anomalies.",
    media: "/onboarding/insights-demo.mp4",
    duration: 50
  },
  {
    id: "automation",
    title: "Workflow Automation",
    description: "Automate repetitive tasks and create powerful workflows.",
    content: "Set up triggers, actions, and conditions to automate your business processes without writing code.",
    media: "/onboarding/automation-demo.mp4",
    duration: 55
  },
  {
    id: "collaboration",
    title: "Team Collaboration",
    description: "Work together with your team on shared insights and analyses.",
    content: "Share queries, collaborate on reports, and maintain a single source of truth for your team.",
    media: "/onboarding/collaboration-demo.mp4",
    duration: 40
  }
]

export default function ComprehensiveOnboarding() {
  const { data: session, status } = useSession()
  const router = useRouter()
  
  const [state, setState] = useState<OnboardingState>({
    step: 1,
    airtableConfig: {},
    organization: {},
    selectedFeatures: ["chat", "formulas"], // Pre-select core features
    completedMilestones: [],
    skipTutorial: false,
    userType: 'beginner',
    selectedBases: [],
    firstQueryCompleted: false,
    tourProgress: 0,
    preferences: {
      theme: 'system',
      emailNotifications: true,
      tourTooltips: true,
      advancedMode: false
    }
  })
  
  const [isLoading, setIsLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [availableBases, setAvailableBases] = useState<AirtableBase[]>([])
  const [isVideoPlaying, setIsVideoPlaying] = useState(false)
  const [currentTourStep, setCurrentTourStep] = useState(0)
  const [showTooltip, setShowTooltip] = useState<string | null>(null)
  const [milestones, setMilestones] = useState<OnboardingMilestone[]>(MILESTONES)
  const [feedbackData, setFeedbackData] = useState({
    rating: 0,
    comments: '',
    suggestions: ''
  })

  // Redirect if not authenticated
  if (status === "loading") {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <motion.div
          animate={{ rotate: 360 }}
          transition={{ duration: 1, repeat: Infinity, ease: "linear" }}
        >
          <Loader2 className="h-8 w-8 text-primary" />
        </motion.div>
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

  const completeMilestone = (milestoneId: string) => {
    if (!state.completedMilestones.includes(milestoneId)) {
      const milestone = milestones.find(m => m.id === milestoneId)
      if (milestone) {
        setState(prev => ({
          ...prev,
          completedMilestones: [...prev.completedMilestones, milestoneId]
        }))
        
        setMilestones(prev => 
          prev.map(m => 
            m.id === milestoneId ? { ...m, completed: true } : m
          )
        )
        
        toast.success(
          `🎉 Achievement unlocked: ${milestone.title}! (+${milestone.points} points)`,
          { duration: 4000 }
        )
      }
    }
  }

  const getTotalPoints = () => {
    return milestones
      .filter(m => state.completedMilestones.includes(m.id))
      .reduce((sum, m) => sum + m.points, 0)
  }

  const getCompletionPercentage = () => {
    return Math.round((state.completedMilestones.length / milestones.length) * 100)
  }

  const completeOnboarding = async () => {
    try {
      setIsLoading(true)
      setError(null)

      const completedMilestonePoints = getTotalPoints()

      // Save comprehensive onboarding data
      const response = await fetch("/api/onboarding/complete", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          airtableConfig: state.airtableConfig,
          organization: state.organization,
          selectedFeatures: state.selectedFeatures,
          completedMilestones: state.completedMilestones,
          userType: state.userType,
          selectedBases: state.selectedBases,
          skipTutorial: state.skipTutorial,
          preferences: state.preferences,
          completionScore: completedMilestonePoints,
          completionPercentage: getCompletionPercentage(),
          onboardingDuration: Date.now(),
          feedback: feedbackData
        }),
      })

      if (!response.ok) {
        const result = await response.json()
        throw new Error(result.error || "Failed to complete onboarding")
      }

      // Celebration animation and success message
      toast.success(
        `🎊 Welcome to PyAirtable! You've earned ${completedMilestonePoints} points and completed ${getCompletionPercentage()}% of the setup!`,
        { duration: 6000 }
      )
      
      // Redirect to dashboard with onboarding completion flag
      router.push("/?onboarding_completed=true")
      router.refresh()
    } catch (error) {
      console.error("Onboarding completion error:", error)
      setError(error instanceof Error ? error.message : "An unexpected error occurred")
    } finally {
      setIsLoading(false)
    }
  }

  // Auto-save onboarding progress
  useEffect(() => {
    const saveProgress = async () => {
      try {
        await fetch('/api/onboarding/progress', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(state)
        })
      } catch (error) {
        console.error('Failed to save onboarding progress:', error)
      }
    }

    const debounceTimer = setTimeout(saveProgress, 1000)
    return () => clearTimeout(debounceTimer)
  }, [state])

  // Load saved progress on mount
  useEffect(() => {
    const loadProgress = async () => {
      try {
        const response = await fetch('/api/onboarding/progress')
        if (response.ok) {
          const savedState = await response.json()
          setState(prev => ({ ...prev, ...savedState }))
        }
      } catch (error) {
        console.error('Failed to load onboarding progress:', error)
      }
    }

    loadProgress()
  }, [])

  const renderStep = () => {
    const stepProps = {
      onNext: nextStep,
      onPrev: prevStep,
      onComplete: completeOnboarding,
      onCompleteMilestone: completeMilestone,
      isLoading,
      error,
      setError,
      showTooltip,
      setShowTooltip,
      state,
      updateState
    }

    switch (state.step) {
      case 1:
        return (
          <EnhancedWelcomeStep 
            user={session?.user} 
            {...stepProps}
            isVideoPlaying={isVideoPlaying}
            setIsVideoPlaying={setIsVideoPlaying}
          />
        )
      
      case 2:
        return (
          <AirtableConnectionWizard
            data={state.airtableConfig}
            onUpdate={(data) => updateState({ airtableConfig: data })}
            availableBases={availableBases}
            setAvailableBases={setAvailableBases}
            onMilestoneComplete={() => completeMilestone('airtable_connected')}
            {...stepProps}
          />
        )
      
      case 3:
        return (
          <BaseConfigurationStep
            availableBases={availableBases}
            selectedBases={state.selectedBases}
            onUpdate={(bases) => updateState({ selectedBases: bases })}
            {...stepProps}
          />
        )
      
      case 4:
        return (
          <EnhancedOrganizationStep
            data={state.organization}
            onUpdate={(data) => {
              updateState({ organization: data })
              completeMilestone('profile_setup')
            }}
            {...stepProps}
          />
        )
      
      case 5:
        return (
          <SmartFeatureSelection
            selectedFeatures={state.selectedFeatures}
            onUpdate={(features) => updateState({ selectedFeatures: features })}
            userType={state.userType}
            organization={state.organization}
            {...stepProps}
          />
        )
      
      case 6:
        return (
          <InteractiveProductTour
            currentStep={currentTourStep}
            onStepChange={setCurrentTourStep}
            skipTutorial={state.skipTutorial}
            userType={state.userType}
            onTourComplete={() => completeMilestone('tour_completed')}
            {...stepProps}
          />
        )
      
      case 7:
        return (
          <FirstAIInteractionDemo
            selectedBases={state.selectedBases}
            onQueryComplete={() => {
              updateState({ firstQueryCompleted: true })
              completeMilestone('first_query')
            }}
            onFeedbackSubmit={(feedback) => setFeedbackData(feedback)}
            {...stepProps}
          />
        )
      
      default:
        return null
    }
  }

  return (
    <div className="min-h-screen bg-gradient-to-br from-blue-50 via-indigo-50 to-purple-50 p-4">
      <div className="max-w-4xl mx-auto">
        {/* Enhanced Progress Header */}
        <motion.div 
          className="mb-8"
          initial={{ opacity: 0, y: -20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.5 }}
        >
          <div className="flex items-center justify-between mb-4">
            <div>
              <h1 className="text-3xl font-bold bg-gradient-to-r from-blue-600 to-purple-600 bg-clip-text text-transparent">
                Welcome to PyAirtable
              </h1>
              <p className="text-sm text-muted-foreground mt-1">
                Progress: {state.completedMilestones.length}/{milestones.length} milestones completed • 
                {getTotalPoints()} points earned • {getCompletionPercentage()}% complete
              </p>
            </div>
            <div className="flex items-center gap-3">
              <Badge variant="secondary" className="text-sm">
                Step {state.step} of {TOTAL_STEPS}
              </Badge>
              <Badge variant="outline" className="flex items-center gap-1">
                <Star className="h-3 w-3 fill-yellow-400 text-yellow-400" />
                {getTotalPoints()}
              </Badge>
              <Badge variant={getCompletionPercentage() > 80 ? "default" : "secondary"}>
                {getCompletionPercentage()}% Complete
              </Badge>
            </div>
          </div>
          
          <Progress value={(state.step / TOTAL_STEPS) * 100} className="h-3 mb-4" />
          
          {/* Milestone Progress Grid */}
          <div className="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-7 gap-2">
            {milestones.map((milestone) => {
              const isCompleted = state.completedMilestones.includes(milestone.id)
              return (
                <motion.div
                  key={milestone.id}
                  className={`flex items-center gap-2 p-3 rounded-lg text-xs transition-all cursor-pointer group ${
                    isCompleted
                      ? 'bg-gradient-to-r from-green-100 to-emerald-100 text-green-700 border border-green-200'
                      : 'bg-white/60 text-gray-600 border border-gray-200 hover:bg-white/80'
                  }`}
                  whileHover={{ scale: 1.02 }}
                  whileTap={{ scale: 0.98 }}
                  title={milestone.description}
                >
                  <div className={`flex-shrink-0 ${isCompleted ? 'text-green-600' : 'text-gray-400'}`}>
                    {isCompleted ? (
                      <CheckCircle className="h-4 w-4" />
                    ) : (
                      milestone.icon
                    )}
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="truncate font-medium">{milestone.title}</div>
                    {isCompleted && (
                      <div className="text-xs text-green-600">+{milestone.points} pts</div>
                    )}
                  </div>
                </motion.div>
              )
            })}
          </div>
        </motion.div>

        {/* Step Content with Enhanced Animation */}
        <AnimatePresence mode="wait">
          <motion.div
            key={state.step}
            initial={{ opacity: 0, x: 20, scale: 0.98 }}
            animate={{ opacity: 1, x: 0, scale: 1 }}
            exit={{ opacity: 0, x: -20, scale: 0.98 }}
            transition={{ duration: 0.4, ease: "easeInOut" }}
          >
            {renderStep()}
          </motion.div>
        </AnimatePresence>

        {/* Help & Support Button */}
        <motion.div
          className="fixed bottom-6 right-6 z-50"
          initial={{ opacity: 0, scale: 0.8 }}
          animate={{ opacity: 1, scale: 1 }}
          transition={{ delay: 1 }}
        >
          <Button
            size="lg"
            className="rounded-full shadow-lg bg-gradient-to-r from-blue-600 to-purple-600 hover:from-blue-700 hover:to-purple-700"
            onClick={() => setShowTooltip(showTooltip ? null : 'help')}
          >
            <HelpCircle className="h-5 w-5" />
            <span className="ml-2 hidden md:block">Need Help?</span>
          </Button>
        </motion.div>

        {/* Help Tooltip */}
        <AnimatePresence>
          {showTooltip === 'help' && (
            <motion.div
              className="fixed bottom-20 right-6 bg-white rounded-lg shadow-xl border p-4 max-w-sm z-50"
              initial={{ opacity: 0, y: 10 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: 10 }}
            >
              <h3 className="font-semibold mb-2">Need assistance?</h3>
              <p className="text-sm text-gray-600 mb-3">
                We're here to help you get started! You can:
              </p>
              <div className="space-y-2 text-sm">
                <div className="flex items-center gap-2">
                  <MessageSquare className="h-4 w-4 text-blue-500" />
                  <span>Join our Discord community</span>
                </div>
                <div className="flex items-center gap-2">
                  <BookOpen className="h-4 w-4 text-green-500" />
                  <span>Browse the documentation</span>
                </div>
                <div className="flex items-center gap-2">
                  <HelpCircle className="h-4 w-4 text-purple-500" />
                  <span>Contact support</span>
                </div>
              </div>
              <Button 
                variant="outline" 
                size="sm" 
                className="w-full mt-3"
                onClick={() => setShowTooltip(null)}
              >
                Close
              </Button>
            </motion.div>
          )}
        </AnimatePresence>
      </div>
    </div>
  )
}

// Component implementations will follow...
// These are placeholder components that would need to be fully implemented

function EnhancedWelcomeStep({ 
  user, 
  onNext, 
  isVideoPlaying, 
  setIsVideoPlaying,
  updateState 
}: any) {
  const [selectedUserType, setSelectedUserType] = useState<'beginner' | 'intermediate' | 'advanced'>('beginner')

  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      className="space-y-6"
    >
      <Card className="overflow-hidden">
        <CardHeader className="text-center bg-gradient-to-r from-blue-600 to-purple-600 text-white">
          <CardTitle className="text-4xl">Welcome to PyAirtable! 🚀</CardTitle>
          <CardDescription className="text-blue-100 text-lg">
            Hi {user?.name || user?.email}! Let's get you set up to unlock the power of AI-driven data management.
          </CardDescription>
        </CardHeader>
        <CardContent className="p-8">
          {/* Platform Overview Video */}
          <div className="relative mb-8 rounded-lg overflow-hidden bg-gray-100 aspect-video">
            <div className="absolute inset-0 flex items-center justify-center">
              <Button
                size="lg"
                className="rounded-full"
                onClick={() => setIsVideoPlaying(!isVideoPlaying)}
              >
                {isVideoPlaying ? <Pause className="h-6 w-6" /> : <Play className="h-6 w-6" />}
                <span className="ml-2">
                  {isVideoPlaying ? 'Pause' : 'Watch'} Platform Overview
                </span>
              </Button>
            </div>
          </div>

          {/* User Type Selection */}
          <div className="mb-8">
            <h3 className="text-lg font-semibold mb-4">What's your experience level?</h3>
            <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
              {[
                { type: 'beginner', title: 'New to Data Analysis', desc: 'I want guided help and tutorials', icon: <Lightbulb /> },
                { type: 'intermediate', title: 'Some Experience', desc: 'I know the basics, show me advanced features', icon: <Target /> },
                { type: 'advanced', title: 'Expert User', desc: 'I want full control and minimal guidance', icon: <Rocket /> }
              ].map((option) => (
                <Card
                  key={option.type}
                  className={`cursor-pointer transition-all ${
                    selectedUserType === option.type 
                      ? 'border-primary ring-2 ring-primary/20' 
                      : 'hover:border-primary/50'
                  }`}
                  onClick={() => setSelectedUserType(option.type as any)}
                >
                  <CardContent className="p-4 text-center">
                    <div className="mb-3 text-primary">{option.icon}</div>
                    <h4 className="font-medium">{option.title}</h4>
                    <p className="text-sm text-muted-foreground mt-1">{option.desc}</p>
                  </CardContent>
                </Card>
              ))}
            </div>
          </div>

          {/* Key Benefits */}
          <div className="grid grid-cols-1 md:grid-cols-3 gap-6 mb-8">
            {[
              { 
                icon: <MessageSquare className="h-8 w-8 text-blue-600" />, 
                title: "Natural Language Queries", 
                desc: "Ask questions about your data in plain English" 
              },
              { 
                icon: <Brain className="h-8 w-8 text-purple-600" />, 
                title: "AI-Powered Insights", 
                desc: "Get intelligent recommendations and predictions" 
              },
              { 
                icon: <Zap className="h-8 w-8 text-yellow-600" />, 
                title: "Automated Workflows", 
                desc: "Set up powerful automations without code" 
              }
            ].map((benefit, index) => (
              <div key={index} className="text-center p-6 rounded-lg bg-white/50">
                <div className="mb-4 flex justify-center">{benefit.icon}</div>
                <h3 className="font-semibold text-lg mb-2">{benefit.title}</h3>
                <p className="text-muted-foreground">{benefit.desc}</p>
              </div>
            ))}
          </div>
          
          <div className="flex gap-4">
            <Button 
              onClick={() => {
                updateState({ userType: selectedUserType })
                onNext()
              }} 
              className="flex-1" 
              size="lg"
            >
              Let's Get Started
              <ArrowRight className="ml-2 h-5 w-5" />
            </Button>
            <Button 
              variant="outline"
              onClick={() => {
                updateState({ skipTutorial: true, userType: 'advanced' })
                onNext()
              }}
            >
              Skip Tutorial
            </Button>
          </div>
        </CardContent>
      </Card>
    </motion.div>
  )
}

// Placeholder components - these would need full implementation
function AirtableConnectionWizard(props: any) {
  return <div>Airtable Connection Wizard - Component needs full implementation</div>
}

function BaseConfigurationStep(props: any) {
  return <div>Base Configuration Step - Component needs full implementation</div>
}

function EnhancedOrganizationStep(props: any) {
  return <div>Enhanced Organization Step - Component needs full implementation</div>
}

function SmartFeatureSelection(props: any) {
  return <div>Smart Feature Selection - Component needs full implementation</div>
}

function InteractiveProductTour(props: any) {
  return <div>Interactive Product Tour - Component needs full implementation</div>
}

function FirstAIInteractionDemo(props: any) {
  return <div>First AI Interaction Demo - Component needs full implementation</div>
}