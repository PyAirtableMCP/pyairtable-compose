"use client"

import React, { useState, useEffect } from "react"
import { motion, AnimatePresence } from "framer-motion"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Badge } from "@/components/ui/badge"
import { Progress } from "@/components/ui/progress"
import { 
  AlertTriangle,
  RefreshCw,
  HelpCircle,
  CheckCircle,
  XCircle,
  Info,
  ArrowRight,
  ArrowLeft,
  ExternalLink,
  MessageCircle,
  Phone,
  Mail,
  Book,
  Search,
  Settings,
  Shield,
  Clock,
  Zap,
  Database,
  Wifi,
  Server,
  Key,
  Users,
  Bug,
  Lightbulb,
  Target,
  FileText,
  AlertCircle
} from "lucide-react"
import toast from "react-hot-toast"

export interface OnboardingError {
  id: string
  type: 'connection' | 'validation' | 'permission' | 'network' | 'server' | 'configuration' | 'user_input'
  severity: 'low' | 'medium' | 'high' | 'critical'
  title: string
  message: string
  details?: string
  timestamp: Date
  context?: {
    step?: string
    component?: string
    userAction?: string
    errorCode?: string
  }
  solutions: ErrorSolution[]
  autoRecoverable: boolean
}

interface ErrorSolution {
  id: string
  title: string
  description: string
  type: 'automatic' | 'guided' | 'manual' | 'contact_support'
  steps: string[]
  estimatedTime: number
  difficulty: 'easy' | 'medium' | 'hard'
  resources?: {
    documentation?: string[]
    videos?: string[]
    examples?: string[]
  }
}

interface ErrorHandlingProps {
  error: OnboardingError | null
  onRetry: () => void
  onSkip?: () => void
  onContactSupport: () => void
  onResolve: () => void
  context?: {
    step: number
    totalSteps: number
    userType: 'beginner' | 'intermediate' | 'advanced'
  }
}

// Predefined error templates for common onboarding issues
export const ERROR_TEMPLATES: { [key: string]: Partial<OnboardingError> } = {
  AIRTABLE_CONNECTION_FAILED: {
    type: 'connection',
    severity: 'high',
    title: 'Airtable Connection Failed',
    message: 'Unable to connect to your Airtable account. This usually indicates an issue with your Personal Access Token.',
    solutions: [
      {
        id: 'check_token',
        title: 'Verify Personal Access Token',
        description: 'Check that your token is correct and has the necessary permissions',
        type: 'guided',
        steps: [
          'Go to Airtable.com and log into your account',
          'Navigate to Account Settings → Personal access tokens',
          'Verify your token exists and is active',
          'Check that it has access to the bases you want to connect',
          'Copy the token again and paste it in PyAirtable'
        ],
        estimatedTime: 5,
        difficulty: 'easy',
        resources: {
          documentation: ['https://airtable.com/developers/web/guides/personal-access-tokens'],
          videos: ['Creating Personal Access Tokens in Airtable']
        }
      },
      {
        id: 'regenerate_token',
        title: 'Generate New Token',
        description: 'Create a fresh Personal Access Token with proper permissions',
        type: 'manual',
        steps: [
          'In Airtable, go to Personal access tokens',
          'Click "Create new token"',
          'Give it a descriptive name like "PyAirtable Integration"',
          'Select required scopes: data.records:read, data.records:write, schema.bases:read',
          'Choose the specific bases you want to connect',
          'Copy the new token to PyAirtable'
        ],
        estimatedTime: 3,
        difficulty: 'easy'
      }
    ],
    autoRecoverable: false
  },

  PERMISSION_DENIED: {
    type: 'permission',
    severity: 'medium',
    title: 'Permission Denied',
    message: 'Your Personal Access Token doesn\'t have sufficient permissions to access the requested data.',
    solutions: [
      {
        id: 'update_permissions',
        title: 'Update Token Permissions',
        description: 'Add the missing permissions to your existing token',
        type: 'guided',
        steps: [
          'Go to your Airtable Personal access tokens page',
          'Find your PyAirtable token',
          'Click "Edit" to modify permissions',
          'Ensure these scopes are enabled: data.records:read, schema.bases:read',
          'Add any missing bases to the access list',
          'Save changes and try connecting again'
        ],
        estimatedTime: 3,
        difficulty: 'easy'
      }
    ],
    autoRecoverable: false
  },

  NETWORK_ERROR: {
    type: 'network',
    severity: 'medium',
    title: 'Network Connection Issue',
    message: 'Unable to reach Airtable servers. This might be a temporary network issue.',
    solutions: [
      {
        id: 'auto_retry',
        title: 'Automatic Retry',
        description: 'We\'ll automatically retry the connection in a few moments',
        type: 'automatic',
        steps: ['Retrying connection...'],
        estimatedTime: 1,
        difficulty: 'easy'
      },
      {
        id: 'check_connection',
        title: 'Check Internet Connection',
        description: 'Verify your internet connection is working properly',
        type: 'manual',
        steps: [
          'Check if you can browse other websites',
          'Try accessing airtable.com directly',
          'If using VPN, try disconnecting temporarily',
          'Check if your firewall is blocking connections'
        ],
        estimatedTime: 2,
        difficulty: 'easy'
      }
    ],
    autoRecoverable: true
  },

  BASE_ANALYSIS_FAILED: {
    type: 'server',
    severity: 'medium',
    title: 'Base Analysis Failed',
    message: 'Unable to analyze your base structure. The base might be too large or have complex relationships.',
    solutions: [
      {
        id: 'retry_analysis',
        title: 'Retry Analysis',
        description: 'Try analyzing the base again',
        type: 'automatic',
        steps: ['Retrying base analysis with optimized settings...'],
        estimatedTime: 2,
        difficulty: 'easy'
      },
      {
        id: 'skip_analysis',
        title: 'Skip Analysis',
        description: 'Continue without detailed analysis - you can run it later',
        type: 'guided',
        steps: [
          'Click "Skip Analysis" to continue',
          'You can run base analysis later from Settings',
          'Basic functionality will still work without analysis'
        ],
        estimatedTime: 1,
        difficulty: 'easy'
      }
    ],
    autoRecoverable: true
  },

  INVALID_USER_INPUT: {
    type: 'user_input',
    severity: 'low',
    title: 'Invalid Input',
    message: 'The information provided doesn\'t meet the required format or criteria.',
    solutions: [
      {
        id: 'fix_input',
        title: 'Fix Input Format',
        description: 'Correct the input according to the requirements',
        type: 'guided',
        steps: [
          'Review the field requirements shown',
          'Check for typos or formatting issues',
          'Ensure all required fields are filled',
          'Follow any specific format requirements'
        ],
        estimatedTime: 1,
        difficulty: 'easy'
      }
    ],
    autoRecoverable: false
  },

  CONFIGURATION_ERROR: {
    type: 'configuration',
    severity: 'high',
    title: 'Configuration Error',
    message: 'There was an issue saving your configuration settings.',
    solutions: [
      {
        id: 'retry_save',
        title: 'Retry Save',
        description: 'Attempt to save the configuration again',
        type: 'automatic',
        steps: ['Retrying configuration save...'],
        estimatedTime: 1,
        difficulty: 'easy'
      },
      {
        id: 'reset_config',
        title: 'Reset Configuration',
        description: 'Reset to default settings and try again',
        type: 'guided',
        steps: [
          'Click "Reset to Defaults"',
          'Re-enter your configuration preferences',
          'Save the configuration again'
        ],
        estimatedTime: 3,
        difficulty: 'medium'
      }
    ],
    autoRecoverable: true
  }
}

export function createOnboardingError(
  templateKey: keyof typeof ERROR_TEMPLATES,
  context?: OnboardingError['context'],
  customMessage?: string
): OnboardingError {
  const template = ERROR_TEMPLATES[templateKey]
  if (!template) {
    throw new Error(`Unknown error template: ${templateKey}`)
  }

  return {
    id: Date.now().toString(),
    ...template,
    message: customMessage || template.message || '',
    timestamp: new Date(),
    context,
  } as OnboardingError
}

export default function ErrorHandling({
  error,
  onRetry,
  onSkip,
  onContactSupport,
  onResolve,
  context
}: ErrorHandlingProps) {
  const [selectedSolution, setSelectedSolution] = useState<ErrorSolution | null>(null)
  const [isRetrying, setIsRetrying] = useState(false)
  const [retryCount, setRetryCount] = useState(0)
  const [showDetails, setShowDetails] = useState(false)
  const [autoRetryTimer, setAutoRetryTimer] = useState<number | null>(null)
  const [recoveryProgress, setRecoveryProgress] = useState(0)

  useEffect(() => {
    if (error?.autoRecoverable && retryCount === 0) {
      // Start auto-recovery after 3 seconds
      const timer = setTimeout(() => {
        handleAutoRetry()
      }, 3000)
      
      setAutoRetryTimer(3)
      const countdownInterval = setInterval(() => {
        setAutoRetryTimer(prev => {
          if (prev && prev <= 1) {
            clearInterval(countdownInterval)
            return null
          }
          return prev ? prev - 1 : null
        })
      }, 1000)

      return () => {
        clearTimeout(timer)
        clearInterval(countdownInterval)
      }
    }
  }, [error, retryCount])

  const handleAutoRetry = async () => {
    setIsRetrying(true)
    setRecoveryProgress(0)
    
    // Simulate progress
    const progressInterval = setInterval(() => {
      setRecoveryProgress(prev => {
        if (prev >= 90) {
          clearInterval(progressInterval)
          return 90
        }
        return prev + 10
      })
    }, 200)

    try {
      await new Promise(resolve => setTimeout(resolve, 2000)) // Simulate retry delay
      setRetryCount(prev => prev + 1)
      onRetry()
      setRecoveryProgress(100)
      toast.success("Retry successful!")
    } catch (retryError) {
      toast.error("Automatic retry failed. Please try manual solutions.")
    } finally {
      clearInterval(progressInterval)
      setIsRetrying(false)
      setAutoRetryTimer(null)
    }
  }

  const handleManualRetry = async () => {
    setIsRetrying(true)
    setRetryCount(prev => prev + 1)
    
    try {
      await onRetry()
      toast.success("Retry successful!")
    } catch (retryError) {
      toast.error("Retry failed. Please try a different solution.")
    } finally {
      setIsRetrying(false)
    }
  }

  const getSeverityIcon = (severity: OnboardingError['severity']) => {
    switch (severity) {
      case 'low': return <Info className="h-5 w-5 text-blue-500" />
      case 'medium': return <AlertTriangle className="h-5 w-5 text-yellow-500" />
      case 'high': return <AlertCircle className="h-5 w-5 text-orange-500" />
      case 'critical': return <XCircle className="h-5 w-5 text-red-500" />
    }
  }

  const getSeverityColor = (severity: OnboardingError['severity']) => {
    switch (severity) {
      case 'low': return 'border-blue-200 bg-blue-50'
      case 'medium': return 'border-yellow-200 bg-yellow-50'
      case 'high': return 'border-orange-200 bg-orange-50'
      case 'critical': return 'border-red-200 bg-red-50'
    }
  }

  const getTypeIcon = (type: OnboardingError['type']) => {
    switch (type) {
      case 'connection': return <Database className="h-4 w-4" />
      case 'validation': return <CheckCircle className="h-4 w-4" />
      case 'permission': return <Shield className="h-4 w-4" />
      case 'network': return <Wifi className="h-4 w-4" />
      case 'server': return <Server className="h-4 w-4" />
      case 'configuration': return <Settings className="h-4 w-4" />
      case 'user_input': return <Users className="h-4 w-4" />
    }
  }

  const getDifficultyBadgeVariant = (difficulty: ErrorSolution['difficulty']) => {
    switch (difficulty) {
      case 'easy': return 'default'
      case 'medium': return 'secondary'
      case 'hard': return 'outline'
    }
  }

  if (!error) return null

  return (
    <AnimatePresence>
      <motion.div
        initial={{ opacity: 0, scale: 0.95 }}
        animate={{ opacity: 1, scale: 1 }}
        exit={{ opacity: 0, scale: 0.95 }}
        className="fixed inset-0 bg-black/50 flex items-center justify-center p-4 z-50"
      >
        <Card className={`max-w-4xl w-full max-h-[90vh] overflow-y-auto border-2 ${getSeverityColor(error.severity)}`}>
          <CardHeader>
            <div className="flex items-start gap-3">
              <div className="flex-shrink-0 mt-1">
                {getSeverityIcon(error.severity)}
              </div>
              <div className="flex-1">
                <div className="flex items-center gap-2 mb-2">
                  <CardTitle className="text-xl">{error.title}</CardTitle>
                  <Badge variant="outline" className="flex items-center gap-1">
                    {getTypeIcon(error.type)}
                    {error.type}
                  </Badge>
                  {retryCount > 0 && (
                    <Badge variant="secondary">
                      Attempt {retryCount + 1}
                    </Badge>
                  )}
                </div>
                <CardDescription className="text-base">{error.message}</CardDescription>
                {error.context && (
                  <div className="mt-2 text-sm text-muted-foreground">
                    {error.context.step && `Step: ${error.context.step}`}
                    {error.context.component && ` • Component: ${error.context.component}`}
                    {error.context.errorCode && ` • Code: ${error.context.errorCode}`}
                  </div>
                )}
              </div>
              <Button
                variant="ghost"
                size="sm"
                onClick={onResolve}
                className="flex-shrink-0"
              >
                <XCircle className="h-4 w-4" />
              </Button>
            </div>
          </CardHeader>

          <CardContent className="space-y-6">
            {/* Auto-retry Progress */}
            {error.autoRecoverable && isRetrying && (
              <div className="space-y-3">
                <div className="flex items-center gap-2">
                  <RefreshCw className="h-4 w-4 animate-spin text-primary" />
                  <span className="font-medium">Attempting automatic recovery...</span>
                </div>
                <Progress value={recoveryProgress} className="h-2" />
                <p className="text-sm text-muted-foreground">
                  This may take a few moments. We'll try to resolve the issue automatically.
                </p>
              </div>
            )}

            {/* Auto-retry Timer */}
            {error.autoRecoverable && autoRetryTimer && !isRetrying && (
              <Alert>
                <Clock className="h-4 w-4" />
                <AlertDescription>
                  <strong>Automatic retry in {autoRetryTimer} seconds...</strong>
                  <br />
                  We detected this error can often be resolved automatically. 
                  You can wait or try manual solutions below.
                </AlertDescription>
              </Alert>
            )}

            {/* Error Details */}
            {error.details && (
              <div className="space-y-2">
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={() => setShowDetails(!showDetails)}
                  className="h-auto p-0"
                >
                  <FileText className="h-3 w-3 mr-1" />
                  {showDetails ? 'Hide' : 'Show'} Technical Details
                </Button>
                
                <AnimatePresence>
                  {showDetails && (
                    <motion.div
                      initial={{ opacity: 0, height: 0 }}
                      animate={{ opacity: 1, height: 'auto' }}
                      exit={{ opacity: 0, height: 0 }}
                      className="p-3 bg-gray-100 rounded-lg text-sm font-mono"
                    >
                      {error.details}
                    </motion.div>
                  )}
                </AnimatePresence>
              </div>
            )}

            {/* Solutions */}
            <div className="space-y-4">
              <h3 className="text-lg font-semibold flex items-center gap-2">
                <Lightbulb className="h-5 w-5 text-yellow-500" />
                Recommended Solutions
              </h3>

              <div className="grid gap-4">
                {error.solutions.map((solution) => (
                  <Card
                    key={solution.id}
                    className={`cursor-pointer transition-all ${
                      selectedSolution?.id === solution.id
                        ? 'border-primary ring-2 ring-primary/20'
                        : 'hover:border-primary/50'
                    }`}
                    onClick={() => setSelectedSolution(
                      selectedSolution?.id === solution.id ? null : solution
                    )}
                  >
                    <CardContent className="p-4">
                      <div className="flex items-start gap-3">
                        <div className={`p-2 rounded-lg flex-shrink-0 ${
                          solution.type === 'automatic' ? 'bg-green-100 text-green-600' :
                          solution.type === 'guided' ? 'bg-blue-100 text-blue-600' :
                          solution.type === 'manual' ? 'bg-orange-100 text-orange-600' :
                          'bg-purple-100 text-purple-600'
                        }`}>
                          {solution.type === 'automatic' && <Zap className="h-4 w-4" />}
                          {solution.type === 'guided' && <Target className="h-4 w-4" />}
                          {solution.type === 'manual' && <Settings className="h-4 w-4" />}
                          {solution.type === 'contact_support' && <MessageCircle className="h-4 w-4" />}
                        </div>
                        
                        <div className="flex-1">
                          <div className="flex items-center gap-2 mb-1">
                            <h4 className="font-medium">{solution.title}</h4>
                            <Badge variant={getDifficultyBadgeVariant(solution.difficulty)}>
                              {solution.difficulty}
                            </Badge>
                            <Badge variant="outline" className="text-xs">
                              ~{solution.estimatedTime} min
                            </Badge>
                          </div>
                          <p className="text-sm text-muted-foreground mb-2">
                            {solution.description}
                          </p>
                          
                          {selectedSolution?.id === solution.id && (
                            <motion.div
                              initial={{ opacity: 0, height: 0 }}
                              animate={{ opacity: 1, height: 'auto' }}
                              className="mt-3 space-y-3"
                            >
                              {/* Steps */}
                              <div className="space-y-2">
                                <h5 className="font-medium text-sm">Steps to follow:</h5>
                                <ol className="space-y-1">
                                  {solution.steps.map((step, idx) => (
                                    <li key={idx} className="flex items-start gap-2 text-sm">
                                      <span className="flex-shrink-0 w-5 h-5 rounded-full bg-primary/10 text-primary text-xs flex items-center justify-center mt-0.5">
                                        {idx + 1}
                                      </span>
                                      <span>{step}</span>
                                    </li>
                                  ))}
                                </ol>
                              </div>

                              {/* Resources */}
                              {solution.resources && (
                                <div className="space-y-2">
                                  <h5 className="font-medium text-sm">Helpful Resources:</h5>
                                  <div className="flex flex-wrap gap-2">
                                    {solution.resources.documentation?.map((doc, idx) => (
                                      <Button key={idx} variant="outline" size="sm" asChild>
                                        <a href={doc} target="_blank" rel="noopener noreferrer">
                                          <Book className="h-3 w-3 mr-1" />
                                          Documentation
                                          <ExternalLink className="h-3 w-3 ml-1" />
                                        </a>
                                      </Button>
                                    ))}
                                    {solution.resources.videos?.map((video, idx) => (
                                      <Button key={idx} variant="outline" size="sm">
                                        <Target className="h-3 w-3 mr-1" />
                                        {video}
                                      </Button>
                                    ))}
                                  </div>
                                </div>
                              )}

                              {/* Action Buttons */}
                              <div className="flex gap-2 pt-2">
                                {solution.type === 'automatic' && (
                                  <Button onClick={handleAutoRetry} disabled={isRetrying}>
                                    {isRetrying ? (
                                      <>
                                        <RefreshCw className="h-3 w-3 mr-1 animate-spin" />
                                        Retrying...
                                      </>
                                    ) : (
                                      <>
                                        <Zap className="h-3 w-3 mr-1" />
                                        Try Automatic Fix
                                      </>
                                    )}
                                  </Button>
                                )}
                                {solution.type === 'contact_support' && (
                                  <Button onClick={onContactSupport}>
                                    <MessageCircle className="h-3 w-3 mr-1" />
                                    Contact Support
                                  </Button>
                                )}
                                <Button variant="outline" onClick={() => setSelectedSolution(null)}>
                                  I've completed these steps
                                </Button>
                              </div>
                            </motion.div>
                          )}
                        </div>
                      </div>
                    </CardContent>
                  </Card>
                ))}
              </div>
            </div>

            {/* Quick Actions */}
            <div className="flex flex-wrap gap-3 pt-4 border-t">
              <Button onClick={handleManualRetry} disabled={isRetrying} variant="default">
                <RefreshCw className="h-4 w-4 mr-2" />
                Retry
              </Button>
              
              {onSkip && (
                <Button onClick={onSkip} variant="outline">
                  Skip This Step
                  <ArrowRight className="h-4 w-4 ml-2" />
                </Button>
              )}
              
              <Button onClick={onContactSupport} variant="outline">
                <HelpCircle className="h-4 w-4 mr-2" />
                Get Help
              </Button>
              
              <div className="flex-1" />
              
              <Button onClick={onResolve} variant="ghost">
                Mark as Resolved
              </Button>
            </div>

            {/* Context Info */}
            {context && (
              <div className="text-xs text-muted-foreground bg-gray-50 p-3 rounded">
                Step {context.step} of {context.totalSteps} • 
                User Level: {context.userType} • 
                Error occurred at {error.timestamp.toLocaleTimeString()}
              </div>
            )}
          </CardContent>
        </Card>
      </motion.div>
    </AnimatePresence>
  )
}