"use client"

import React, { useState, useEffect } from "react"
import { motion, AnimatePresence } from "framer-motion"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Badge } from "@/components/ui/badge"
import { Progress } from "@/components/ui/progress"
import { 
  Play,
  Pause,
  SkipForward,
  Volume2,
  VolumeX,
  ArrowRight, 
  ArrowLeft,
  BookOpen,
  MessageSquare,
  Brain,
  Zap,
  Users,
  BarChart3,
  Settings,
  Target,
  CheckCircle,
  Eye,
  Lightbulb,
  Rocket,
  Wand2,
  Database,
  TrendingUp,
  FileText,
  Globe,
  Shield,
  Clock,
  Star,
  ThumbsUp,
  ThumbsDown,
  HelpCircle,
  RefreshCw,
  Download,
  Share2,
  Filter,
  Search,
  Cpu
} from "lucide-react"
import toast from "react-hot-toast"

interface TourStep {
  id: string
  title: string
  description: string
  content: string
  media?: {
    type: 'video' | 'image' | 'interactive'
    url: string
    thumbnail?: string
  }
  duration: number
  category: 'overview' | 'features' | 'advanced' | 'tips'
  difficulty: 'beginner' | 'intermediate' | 'advanced'
  interactiveElements?: {
    type: 'demo' | 'quiz' | 'tryit'
    data: any
  }
  keyPoints: string[]
  nextSteps: string[]
}

interface InteractiveProductTourProps {
  currentStep: number
  onStepChange: (step: number) => void
  skipTutorial: boolean
  userType: 'beginner' | 'intermediate' | 'advanced'
  onTourComplete: () => void
  onNext: () => void
  onPrev: () => void
  error: string | null
  setError: (error: string | null) => void
}

const TOUR_STEPS: TourStep[] = [
  {
    id: "platform_overview",
    title: "Welcome to PyAirtable",
    description: "Your AI-powered data management platform",
    content: "PyAirtable transforms how you interact with your Airtable data by adding the power of AI. Instead of complex queries and manual analysis, simply ask questions in natural language and get instant insights.",
    media: {
      type: 'video',
      url: '/onboarding/platform-overview.mp4',
      thumbnail: '/onboarding/platform-overview-thumb.jpg'
    },
    duration: 90,
    category: 'overview',
    difficulty: 'beginner',
    keyPoints: [
      "Natural language querying with AI",
      "Automated insights and recommendations", 
      "Seamless integration with your existing Airtable workflow",
      "Advanced analytics without complex setup"
    ],
    nextSteps: [
      "Connect your Airtable bases",
      "Try your first AI query",
      "Explore automation opportunities"
    ]
  },
  {
    id: "natural_language_queries",
    title: "Ask Questions in Plain English",
    description: "No SQL, no complex formulas - just natural conversation",
    content: "The heart of PyAirtable is our AI chat interface. Ask questions about your data like you would ask a colleague: 'Show me sales trends from last quarter' or 'Which customers haven't ordered recently?'",
    media: {
      type: 'interactive',
      url: '/onboarding/chat-demo'
    },
    duration: 120,
    category: 'features',
    difficulty: 'beginner',
    interactiveElements: {
      type: 'demo',
      data: {
        sampleQueries: [
          "Show me top performing products this month",
          "Which customers have the highest lifetime value?",
          "What are the trends in customer satisfaction?",
          "Find records with missing email addresses"
        ]
      }
    },
    keyPoints: [
      "Type questions in natural language",
      "Get instant visualizations and insights",
      "AI understands context from your data structure",
      "Follow-up questions for deeper analysis"
    ],
    nextSteps: [
      "Try the sample queries",
      "Ask questions about your specific data",
      "Learn advanced query techniques"
    ]
  },
  {
    id: "ai_insights",
    title: "AI-Powered Insights & Recommendations",
    description: "Let AI discover patterns and opportunities in your data",
    content: "Our AI continuously analyzes your data to identify trends, anomalies, and opportunities. Get proactive insights about your business without having to know what to look for.",
    media: {
      type: 'video',
      url: '/onboarding/insights-demo.mp4'
    },
    duration: 100,
    category: 'features', 
    difficulty: 'intermediate',
    keyPoints: [
      "Automatic pattern detection",
      "Anomaly identification and alerts",
      "Predictive analytics and forecasting",
      "Personalized business recommendations"
    ],
    nextSteps: [
      "Review AI-generated insights",
      "Set up automated alerts",
      "Configure insight preferences"
    ]
  },
  {
    id: "workflow_automation",
    title: "Powerful Automation Without Code",
    description: "Create sophisticated workflows with simple drag-and-drop",
    content: "Transform your manual processes into automated workflows. Set triggers, conditions, and actions to handle routine tasks while you focus on strategic decisions.",
    media: {
      type: 'interactive',
      url: '/onboarding/automation-builder'
    },
    duration: 150,
    category: 'features',
    difficulty: 'intermediate',
    interactiveElements: {
      type: 'tryit',
      data: {
        workflowTemplates: [
          "New customer welcome sequence",
          "Inventory low stock alerts",
          "Lead scoring and assignment",
          "Invoice follow-up automation"
        ]
      }
    },
    keyPoints: [
      "Drag-and-drop workflow builder",
      "Smart triggers based on data changes",
      "Integration with external services",
      "Advanced conditional logic"
    ],
    nextSteps: [
      "Create your first automation",
      "Explore workflow templates",
      "Set up monitoring and alerts"
    ]
  },
  {
    id: "collaboration_features",
    title: "Team Collaboration & Sharing",
    description: "Work together on data insights and decisions",
    content: "Share insights, collaborate on analyses, and ensure your team is aligned with shared dashboards, comments, and real-time collaboration features.",
    media: {
      type: 'video',
      url: '/onboarding/collaboration-demo.mp4'
    },
    duration: 80,
    category: 'features',
    difficulty: 'beginner',
    keyPoints: [
      "Share queries and insights with teammates",
      "Real-time collaborative analysis",
      "Comment and annotation system",
      "Role-based access control"
    ],
    nextSteps: [
      "Invite team members",
      "Create shared dashboards",
      "Set up collaboration preferences"
    ]
  },
  {
    id: "advanced_analytics",
    title: "Advanced Analytics & Visualizations",
    description: "Deep dive into your data with powerful analytical tools",
    content: "Go beyond basic charts with advanced statistical analysis, custom visualizations, and sophisticated reporting capabilities tailored to your business needs.",
    media: {
      type: 'interactive',
      url: '/onboarding/analytics-playground'
    },
    duration: 120,
    category: 'advanced',
    difficulty: 'advanced',
    keyPoints: [
      "Statistical analysis and modeling",
      "Custom visualization builder",
      "Advanced filtering and segmentation",
      "Export and reporting capabilities"
    ],
    nextSteps: [
      "Explore advanced chart types",
      "Build custom dashboards",
      "Set up automated reports"
    ]
  },
  {
    id: "tips_and_tricks",
    title: "Pro Tips & Best Practices",
    description: "Maximize your productivity with expert techniques",
    content: "Learn insider tips and best practices from data experts to get the most out of PyAirtable. Discover shortcuts, advanced techniques, and optimization strategies.",
    duration: 60,
    category: 'tips',
    difficulty: 'intermediate',
    keyPoints: [
      "Keyboard shortcuts for power users",
      "Query optimization techniques",
      "Data organization best practices",
      "Performance monitoring and tuning"
    ],
    nextSteps: [
      "Practice keyboard shortcuts",
      "Organize your workspace",
      "Set up performance monitoring"
    ]
  }
]

export default function InteractiveProductTour({
  currentStep,
  onStepChange,
  skipTutorial,
  userType,
  onTourComplete,
  onNext,
  onPrev,
  error,
  setError
}: InteractiveProductTourProps) {
  const [isPlaying, setIsPlaying] = useState(false)
  const [isMuted, setIsMuted] = useState(false)
  const [progress, setProgress] = useState(0)
  const [showTranscript, setShowTranscript] = useState(false)
  const [userRating, setUserRating] = useState<{ [stepId: string]: 'up' | 'down' | null }>({})
  const [notes, setNotes] = useState<{ [stepId: string]: string }>({})
  const [completedSteps, setCompletedSteps] = useState<Set<string>>(new Set())
  const [showQuiz, setShowQuiz] = useState(false)
  const [quizAnswers, setQuizAnswers] = useState<{ [key: string]: string }>({})

  // Filter steps based on user type and preferences
  const filteredSteps = TOUR_STEPS.filter(step => {
    if (skipTutorial) return false
    
    switch (userType) {
      case 'beginner':
        return step.difficulty === 'beginner' || step.category === 'overview'
      case 'intermediate': 
        return step.difficulty !== 'advanced'
      case 'advanced':
        return step.difficulty === 'advanced' || step.category === 'tips'
      default:
        return true
    }
  })

  const currentTourStep = filteredSteps[currentStep] || filteredSteps[0]
  const isLastStep = currentStep >= filteredSteps.length - 1

  useEffect(() => {
    let interval: NodeJS.Timeout
    if (isPlaying && currentTourStep) {
      interval = setInterval(() => {
        setProgress(prev => {
          const newProgress = prev + (100 / currentTourStep.duration)
          if (newProgress >= 100) {
            setIsPlaying(false)
            handleStepComplete()
            return 100
          }
          return newProgress
        })
      }, 1000)
    }
    return () => clearInterval(interval)
  }, [isPlaying, currentTourStep])

  const handleStepComplete = () => {
    if (currentTourStep) {
      setCompletedSteps(prev => new Set([...prev, currentTourStep.id]))
      
      if (isLastStep) {
        onTourComplete()
        toast.success("🎉 Product tour completed! You're ready to explore PyAirtable.")
        setTimeout(() => onNext(), 2000)
      }
    }
  }

  const handleNext = () => {
    if (currentStep < filteredSteps.length - 1) {
      onStepChange(currentStep + 1)
      setProgress(0)
      setIsPlaying(false)
    } else {
      handleStepComplete()
    }
  }

  const handlePrevious = () => {
    if (currentStep > 0) {
      onStepChange(currentStep - 1)
      setProgress(0)
      setIsPlaying(false)
    }
  }

  const handleRating = (stepId: string, rating: 'up' | 'down') => {
    setUserRating(prev => ({
      ...prev,
      [stepId]: prev[stepId] === rating ? null : rating
    }))
  }

  const renderMediaPlayer = () => {
    if (!currentTourStep?.media) return null

    return (
      <div className="relative bg-gray-900 rounded-lg overflow-hidden aspect-video">
        {currentTourStep.media.type === 'video' && (
          <>
            {/* Video placeholder with play button */}
            <div className="absolute inset-0 flex items-center justify-center bg-gradient-to-br from-blue-600 to-purple-600">
              <Button
                size="lg"
                variant="secondary"
                className="rounded-full"
                onClick={() => setIsPlaying(!isPlaying)}
              >
                {isPlaying ? <Pause className="h-8 w-8" /> : <Play className="h-8 w-8" />}
              </Button>
            </div>
            
            {/* Video controls */}
            <div className="absolute bottom-0 left-0 right-0 bg-gradient-to-t from-black/70 to-transparent p-4">
              <div className="flex items-center gap-4 text-white">
                <Button
                  size="sm"
                  variant="ghost"
                  className="text-white hover:bg-white/20"
                  onClick={() => setIsPlaying(!isPlaying)}
                >
                  {isPlaying ? <Pause className="h-4 w-4" /> : <Play className="h-4 w-4" />}
                </Button>
                
                <div className="flex-1">
                  <Progress value={progress} className="h-1" />
                </div>
                
                <Button
                  size="sm"
                  variant="ghost"
                  className="text-white hover:bg-white/20"
                  onClick={() => setIsMuted(!isMuted)}
                >
                  {isMuted ? <VolumeX className="h-4 w-4" /> : <Volume2 className="h-4 w-4" />}
                </Button>

                <Button
                  size="sm"
                  variant="ghost"
                  className="text-white hover:bg-white/20"
                  onClick={() => setShowTranscript(!showTranscript)}
                >
                  <FileText className="h-4 w-4" />
                </Button>
              </div>
            </div>
          </>
        )}

        {currentTourStep.media.type === 'interactive' && (
          <div className="absolute inset-0 flex items-center justify-center bg-gradient-to-br from-green-600 to-blue-600">
            <div className="text-center text-white">
              <Wand2 className="h-16 w-16 mx-auto mb-4" />
              <h3 className="text-xl font-semibold mb-2">Interactive Demo</h3>
              <Button variant="secondary" onClick={() => setIsPlaying(true)}>
                Start Interactive Experience
              </Button>
            </div>
          </div>
        )}
      </div>
    )
  }

  const renderInteractiveElements = () => {
    if (!currentTourStep?.interactiveElements) return null

    const { type, data } = currentTourStep.interactiveElements

    if (type === 'demo' && data.sampleQueries) {
      return (
        <div className="mt-6 p-4 bg-blue-50 rounded-lg">
          <h4 className="font-semibold mb-3 flex items-center gap-2">
            <MessageSquare className="h-4 w-4" />
            Try These Sample Queries
          </h4>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
            {data.sampleQueries.map((query: string, idx: number) => (
              <Button
                key={idx}
                variant="outline"
                className="justify-start h-auto p-3 text-left"
                onClick={() => toast.success(`Query: "${query}" - Try this in the main chat interface!`)}
              >
                <Search className="h-4 w-4 mr-2 flex-shrink-0" />
                <span className="text-sm">{query}</span>
              </Button>
            ))}
          </div>
        </div>
      )
    }

    if (type === 'tryit' && data.workflowTemplates) {
      return (
        <div className="mt-6 p-4 bg-purple-50 rounded-lg">
          <h4 className="font-semibold mb-3 flex items-center gap-2">
            <Zap className="h-4 w-4" />
            Popular Workflow Templates
          </h4>
          <div className="space-y-2">
            {data.workflowTemplates.map((template: string, idx: number) => (
              <div key={idx} className="flex items-center gap-3 p-2 bg-white rounded border">
                <Cpu className="h-4 w-4 text-purple-500" />
                <span className="flex-1 text-sm">{template}</span>
                <Button size="sm" variant="ghost">
                  <Eye className="h-3 w-3 mr-1" />
                  Preview
                </Button>
              </div>
            ))}
          </div>
        </div>
      )
    }

    return null
  }

  const renderQuizSection = () => {
    if (!showQuiz) return null

    const quizQuestions = [
      {
        id: 'natural_language',
        question: 'How do you query data in PyAirtable?',
        options: [
          'Using SQL commands',
          'Writing complex formulas',
          'Asking questions in natural language',
          'Creating custom scripts'
        ],
        correct: 2
      },
      {
        id: 'ai_insights',
        question: 'What does PyAirtable AI help you discover?',
        options: [
          'Only basic statistics',
          'Patterns, trends, and business opportunities',
          'Database errors only',
          'User interface issues'
        ],
        correct: 1
      }
    ]

    return (
      <Card className="mt-6 border-orange-200 bg-orange-50">
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Target className="h-5 w-5 text-orange-600" />
            Quick Knowledge Check
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          {quizQuestions.map((q, idx) => (
            <div key={q.id} className="space-y-2">
              <p className="font-medium">{idx + 1}. {q.question}</p>
              <div className="space-y-1">
                {q.options.map((option, optIdx) => (
                  <label key={optIdx} className="flex items-center gap-2 cursor-pointer">
                    <input
                      type="radio"
                      name={q.id}
                      value={optIdx}
                      onChange={(e) => setQuizAnswers(prev => ({ ...prev, [q.id]: e.target.value }))}
                      className="text-primary"
                    />
                    <span className="text-sm">{option}</span>
                  </label>
                ))}
              </div>
            </div>
          ))}
          <Button 
            onClick={() => {
              setShowQuiz(false)
              toast.success("Great job! You're understanding PyAirtable well.")
            }}
            className="w-full"
          >
            Submit Answers
          </Button>
        </CardContent>
      </Card>
    )
  }

  if (skipTutorial) {
    return (
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Rocket className="h-6 w-6 text-primary" />
            Tutorial Skipped
          </CardTitle>
        </CardHeader>
        <CardContent>
          <p className="mb-4">You've chosen to skip the tutorial. You can always access it later from the help menu.</p>
          <Button onClick={onNext} className="w-full" size="lg">
            Continue to Setup
            <ArrowRight className="ml-2 h-5 w-5" />
          </Button>
        </CardContent>
      </Card>
    )
  }

  if (!currentTourStep) {
    return (
      <Card>
        <CardContent className="text-center py-8">
          <BookOpen className="h-12 w-12 mx-auto mb-4 text-muted-foreground" />
          <p className="text-muted-foreground">No tour steps available for your configuration.</p>
          <Button onClick={onNext} className="mt-4">Skip to Next Step</Button>
        </CardContent>
      </Card>
    )
  }

  return (
    <div className="space-y-6">
      {/* Tour Progress */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          <BookOpen className="h-5 w-5 text-primary" />
          <span className="font-medium">Product Tour</span>
          <Badge variant="outline">
            {currentStep + 1} of {filteredSteps.length}
          </Badge>
        </div>
        <div className="flex items-center gap-2">
          <span className="text-sm text-muted-foreground">
            {completedSteps.size}/{filteredSteps.length} completed
          </span>
          <div className="w-24">
            <Progress value={(completedSteps.size / filteredSteps.length) * 100} className="h-2" />
          </div>
        </div>
      </div>

      {/* Main Tour Card */}
      <Card>
        <CardHeader>
          <div className="flex items-start justify-between">
            <div className="flex-1">
              <CardTitle className="flex items-center gap-2 text-2xl">
                {currentTourStep.category === 'overview' && <Globe className="h-6 w-6" />}
                {currentTourStep.category === 'features' && <Star className="h-6 w-6" />}
                {currentTourStep.category === 'advanced' && <Brain className="h-6 w-6" />}
                {currentTourStep.category === 'tips' && <Lightbulb className="h-6 w-6" />}
                {currentTourStep.title}
              </CardTitle>
              <CardDescription className="text-lg mt-2">
                {currentTourStep.description}
              </CardDescription>
            </div>
            <div className="flex items-center gap-2">
              <Badge variant={
                currentTourStep.difficulty === 'beginner' ? 'default' :
                currentTourStep.difficulty === 'intermediate' ? 'secondary' : 'outline'
              }>
                {currentTourStep.difficulty}
              </Badge>
              <Badge variant="outline">
                {currentTourStep.duration}s
              </Badge>
            </div>
          </div>
        </CardHeader>

        <CardContent className="space-y-6">
          {/* Media Player */}
          {renderMediaPlayer()}

          {/* Content */}
          <div className="prose max-w-none">
            <p className="text-lg leading-relaxed">{currentTourStep.content}</p>
          </div>

          {/* Key Points */}
          <div className="bg-blue-50 p-4 rounded-lg">
            <h4 className="font-semibold mb-3 flex items-center gap-2">
              <CheckCircle className="h-4 w-4 text-blue-600" />
              Key Takeaways
            </h4>
            <ul className="space-y-2">
              {currentTourStep.keyPoints.map((point, idx) => (
                <li key={idx} className="flex items-start gap-2">
                  <div className="w-1.5 h-1.5 rounded-full bg-blue-600 mt-2 flex-shrink-0" />
                  <span className="text-sm">{point}</span>
                </li>
              ))}
            </ul>
          </div>

          {/* Interactive Elements */}
          {renderInteractiveElements()}

          {/* Next Steps */}
          <div className="bg-green-50 p-4 rounded-lg">
            <h4 className="font-semibold mb-3 flex items-center gap-2">
              <Target className="h-4 w-4 text-green-600" />
              What's Next?
            </h4>
            <div className="grid grid-cols-1 md:grid-cols-3 gap-2">
              {currentTourStep.nextSteps.map((step, idx) => (
                <div key={idx} className="flex items-center gap-2 text-sm">
                  <ArrowRight className="h-3 w-3 text-green-600" />
                  <span>{step}</span>
                </div>
              ))}
            </div>
          </div>

          {/* User Feedback */}
          <div className="flex items-center justify-between p-3 bg-gray-50 rounded-lg">
            <span className="text-sm font-medium">Was this step helpful?</span>
            <div className="flex items-center gap-2">
              <Button
                size="sm"
                variant={userRating[currentTourStep.id] === 'up' ? 'default' : 'outline'}
                onClick={() => handleRating(currentTourStep.id, 'up')}
              >
                <ThumbsUp className="h-3 w-3" />
              </Button>
              <Button
                size="sm"
                variant={userRating[currentTourStep.id] === 'down' ? 'default' : 'outline'}
                onClick={() => handleRating(currentTourStep.id, 'down')}
              >
                <ThumbsDown className="h-3 w-3" />
              </Button>
              <Button
                size="sm"
                variant="ghost"
                onClick={() => setShowQuiz(!showQuiz)}
              >
                <HelpCircle className="h-3 w-3 mr-1" />
                Quiz
              </Button>
            </div>
          </div>

          {/* Quiz Section */}
          {renderQuizSection()}

          {/* Navigation */}
          <div className="flex gap-3 pt-4">
            <Button
              type="button"
              variant="outline"
              onClick={currentStep === 0 ? onPrev : handlePrevious}
            >
              <ArrowLeft className="mr-2 h-4 w-4" />
              {currentStep === 0 ? 'Back to Features' : 'Previous Step'}
            </Button>
            
            <div className="flex-1 flex gap-2">
              {!isLastStep && (
                <Button variant="ghost" onClick={() => onNext()}>
                  Skip Tour
                </Button>
              )}
              
              <Button 
                onClick={handleNext} 
                className="flex-1"
                size="lg"
              >
                {isLastStep ? (
                  <>
                    Complete Tour & Continue
                    <CheckCircle className="ml-2 h-5 w-5" />
                  </>
                ) : (
                  <>
                    Next Step
                    <ArrowRight className="ml-2 h-4 w-4" />
                  </>
                )}
              </Button>
            </div>
          </div>
        </CardContent>
      </Card>

      {/* Step Navigation */}
      <div className="grid grid-cols-4 md:grid-cols-7 gap-2">
        {filteredSteps.map((step, idx) => (
          <Button
            key={step.id}
            variant={idx === currentStep ? 'default' : completedSteps.has(step.id) ? 'secondary' : 'outline'}
            size="sm"
            className="relative"
            onClick={() => onStepChange(idx)}
          >
            {completedSteps.has(step.id) && (
              <CheckCircle className="h-3 w-3 absolute -top-1 -right-1 text-green-600 bg-white rounded-full" />
            )}
            {idx + 1}
          </Button>
        ))}
      </div>
    </div>
  )
}