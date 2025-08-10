"use client"

import React, { useState, useEffect } from "react"
import { useForm } from "react-hook-form"
import { zodResolver } from "@hookform/resolvers/zod"
import { z } from "zod"
import { motion, AnimatePresence } from "framer-motion"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Badge } from "@/components/ui/badge"
import { Separator } from "@/components/ui/separator"
import { 
  Loader2, 
  Key, 
  Database, 
  CheckCircle, 
  ArrowRight, 
  ArrowLeft,
  ExternalLink,
  Shield,
  AlertTriangle,
  Info,
  Eye,
  EyeOff,
  RefreshCw,
  Search,
  Filter,
  Settings,
  Users,
  FileText,
  BarChart3,
  Clock,
  CheckCheck,
  XCircle,
  HelpCircle,
  Copy,
  Link
} from "lucide-react"
import toast from "react-hot-toast"

const airtableConfigSchema = z.object({
  personalAccessToken: z.string().min(1, "Personal Access Token is required"),
})

type AirtableConfigForm = z.infer<typeof airtableConfigSchema>

interface AirtableBase {
  id: string
  name: string
  permissionLevel: string
  tableCount: number
  recordCount?: number
  tables?: AirtableTable[]
  createdTime: string
  description?: string
}

interface AirtableTable {
  id: string
  name: string
  description?: string
  primaryFieldId: string
  fields: AirtableField[]
  views: AirtableView[]
  recordCount: number
}

interface AirtableField {
  id: string
  name: string
  type: string
  description?: string
  options?: any
}

interface AirtableView {
  id: string
  name: string
  type: string
}

interface ConnectionTestResult {
  success: boolean
  error?: string
  userInfo?: {
    id: string
    email: string
    name?: string
  }
  baseCount: number
  hasWriteAccess: boolean
}

interface AirtableConnectionWizardProps {
  data: Partial<AirtableConfigForm>
  onUpdate: (data: Partial<AirtableConfigForm>) => void
  availableBases: AirtableBase[]
  setAvailableBases: (bases: AirtableBase[]) => void
  onMilestoneComplete: () => void
  onNext: () => void
  onPrev: () => void
  error: string | null
  setError: (error: string | null) => void
  showTooltip: string | null
  setShowTooltip: (tooltip: string | null) => void
}

export default function AirtableConnectionWizard({
  data,
  onUpdate,
  availableBases,
  setAvailableBases,
  onMilestoneComplete,
  onNext,
  onPrev,
  error,
  setError,
  showTooltip,
  setShowTooltip
}: AirtableConnectionWizardProps) {
  const [currentSubStep, setCurrentSubStep] = useState<'token' | 'testing' | 'bases' | 'validation'>('token')
  const [isValidating, setIsValidating] = useState(false)
  const [isLoadingBases, setIsLoadingBases] = useState(false)
  const [showToken, setShowToken] = useState(false)
  const [connectionResult, setConnectionResult] = useState<ConnectionTestResult | null>(null)
  const [selectedBases, setSelectedBases] = useState<string[]>([])
  const [searchTerm, setSearchTerm] = useState('')
  const [filterPermission, setFilterPermission] = useState<'all' | 'read' | 'write'>('all')
  const [isAnalyzingStructure, setIsAnalyzingStructure] = useState(false)
  const [structureAnalysis, setStructureAnalysis] = useState<{[key: string]: any}>({})
  
  const { register, handleSubmit, formState: { errors }, watch } = useForm<AirtableConfigForm>({
    resolver: zodResolver(airtableConfigSchema),
    defaultValues: data,
  })

  const watchToken = watch('personalAccessToken')

  // Real-time token validation
  useEffect(() => {
    if (watchToken && watchToken.length > 10) {
      const debounceTimer = setTimeout(() => {
        validateTokenFormat(watchToken)
      }, 500)
      return () => clearTimeout(debounceTimer)
    }
  }, [watchToken])

  const validateTokenFormat = (token: string) => {
    // Basic token format validation
    if (!token.startsWith('pat') && !token.startsWith('key')) {
      setError('Token should start with "pat" for Personal Access Tokens')
      return false
    }
    if (token.length < 17) {
      setError('Token appears to be too short')
      return false
    }
    setError(null)
    return true
  }

  const testConnection = async (token: string): Promise<ConnectionTestResult> => {
    const response = await fetch("/api/airtable/test-connection", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ personalAccessToken: token }),
    })

    const result = await response.json()
    
    if (!response.ok) {
      throw new Error(result.error || "Failed to test connection")
    }

    return result
  }

  const fetchBases = async (token: string): Promise<AirtableBase[]> => {
    const response = await fetch("/api/airtable/bases", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ personalAccessToken: token }),
    })

    const result = await response.json()
    
    if (!response.ok) {
      throw new Error(result.error || "Failed to fetch bases")
    }

    return result.bases
  }

  const analyzeBaseStructure = async (baseId: string, token: string) => {
    const response = await fetch("/api/airtable/analyze-structure", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ 
        baseId,
        personalAccessToken: token 
      }),
    })

    const result = await response.json()
    
    if (!response.ok) {
      throw new Error(result.error || "Failed to analyze base structure")
    }

    return result
  }

  const onSubmit = async (formData: AirtableConfigForm) => {
    try {
      setIsValidating(true)
      setError(null)
      setCurrentSubStep('testing')

      // Test connection
      const connectionResult = await testConnection(formData.personalAccessToken)
      setConnectionResult(connectionResult)
      
      toast.success("Connection successful! 🎉")
      setCurrentSubStep('bases')

      // Fetch available bases
      setIsLoadingBases(true)
      const bases = await fetchBases(formData.personalAccessToken)
      setAvailableBases(bases)
      setIsLoadingBases(false)

      onUpdate(formData)

    } catch (error) {
      console.error("Connection test error:", error)
      setError(error instanceof Error ? error.message : "Failed to connect to Airtable")
      setCurrentSubStep('token')
    } finally {
      setIsValidating(false)
    }
  }

  const handleBaseSelection = (baseId: string) => {
    setSelectedBases(prev => 
      prev.includes(baseId) 
        ? prev.filter(id => id !== baseId)
        : [...prev, baseId]
    )
  }

  const analyzeSelectedBases = async () => {
    if (selectedBases.length === 0) {
      setError("Please select at least one base to continue")
      return
    }

    try {
      setIsAnalyzingStructure(true)
      setCurrentSubStep('validation')

      const analysisResults = {}
      for (const baseId of selectedBases) {
        const analysis = await analyzeBaseStructure(baseId, data.personalAccessToken!)
        analysisResults[baseId] = analysis
      }

      setStructureAnalysis(analysisResults)
      onMilestoneComplete()
      
      toast.success(`Successfully analyzed ${selectedBases.length} base(s)!`)
      
      // Auto-advance after successful analysis
      setTimeout(() => {
        onNext()
      }, 2000)

    } catch (error) {
      setError(error instanceof Error ? error.message : "Failed to analyze base structure")
    } finally {
      setIsAnalyzingStructure(false)
    }
  }

  const filteredBases = availableBases.filter(base => {
    const matchesSearch = base.name.toLowerCase().includes(searchTerm.toLowerCase())
    const matchesPermission = filterPermission === 'all' || 
      (filterPermission === 'read' && base.permissionLevel.includes('read')) ||
      (filterPermission === 'write' && base.permissionLevel.includes('write'))
    
    return matchesSearch && matchesPermission
  })

  const renderTokenStep = () => (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <Key className="h-6 w-6 text-primary" />
          Connect Your Airtable Account
        </CardTitle>
        <CardDescription>
          We'll need your Personal Access Token to securely connect to your Airtable bases.
          This allows us to read your data structure and provide AI-powered insights.
        </CardDescription>
      </CardHeader>
      <CardContent>
        <form onSubmit={handleSubmit(onSubmit)} className="space-y-6">
          {error && (
            <Alert variant="destructive">
              <AlertTriangle className="h-4 w-4" />
              <AlertDescription>{error}</AlertDescription>
            </Alert>
          )}

          {/* Security Notice */}
          <Alert>
            <Shield className="h-4 w-4" />
            <AlertDescription>
              <strong>Your data security is our priority.</strong> We use industry-standard encryption 
              and never store your Personal Access Token in plain text.
            </AlertDescription>
          </Alert>

          <div className="space-y-4">
            <div className="space-y-2">
              <label className="text-sm font-medium flex items-center gap-2">
                Personal Access Token *
                <Button
                  type="button"
                  variant="ghost"
                  size="sm"
                  onClick={() => setShowTooltip(showTooltip === 'pat-help' ? null : 'pat-help')}
                >
                  <HelpCircle className="h-4 w-4" />
                </Button>
              </label>

              <div className="relative">
                <Input
                  {...register("personalAccessToken")}
                  type={showToken ? "text" : "password"}
                  placeholder="pat1234567890abcdef..."
                  className="font-mono pr-12"
                  autoComplete="off"
                />
                <Button
                  type="button"
                  variant="ghost"
                  size="sm"
                  className="absolute right-1 top-1 h-8 w-8 p-0"
                  onClick={() => setShowToken(!showToken)}
                >
                  {showToken ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
                </Button>
              </div>

              {errors.personalAccessToken && (
                <p className="text-sm text-destructive flex items-center gap-1">
                  <XCircle className="h-3 w-3" />
                  {errors.personalAccessToken.message}
                </p>
              )}

              {/* Real-time validation feedback */}
              {watchToken && watchToken.length > 5 && !errors.personalAccessToken && (
                <div className="flex items-center gap-2 text-sm">
                  {validateTokenFormat(watchToken) ? (
                    <>
                      <CheckCircle className="h-4 w-4 text-green-500" />
                      <span className="text-green-600">Token format looks good</span>
                    </>
                  ) : (
                    <>
                      <XCircle className="h-4 w-4 text-red-500" />
                      <span className="text-red-600">Please check token format</span>
                    </>
                  )}
                </div>
              )}
            </div>

            {/* Help tooltip */}
            <AnimatePresence>
              {showTooltip === 'pat-help' && (
                <motion.div
                  initial={{ opacity: 0, y: -10 }}
                  animate={{ opacity: 1, y: 0 }}
                  exit={{ opacity: 0, y: -10 }}
                  className="p-4 bg-blue-50 border border-blue-200 rounded-lg"
                >
                  <h4 className="font-medium text-blue-900 mb-2">How to get your Personal Access Token:</h4>
                  <ol className="text-sm text-blue-800 space-y-1 list-decimal list-inside">
                    <li>Go to your Airtable Account settings</li>
                    <li>Click on "Personal access tokens"</li>
                    <li>Click "Create new token"</li>
                    <li>Give it a name and select the required scopes</li>
                    <li>Copy the token and paste it here</li>
                  </ol>
                  <div className="flex gap-2 mt-3">
                    <Button 
                      type="button" 
                      variant="outline" 
                      size="sm"
                      onClick={() => window.open('https://airtable.com/create/tokens', '_blank')}
                    >
                      <ExternalLink className="h-3 w-3 mr-1" />
                      Create Token
                    </Button>
                    <Button 
                      type="button" 
                      variant="ghost" 
                      size="sm"
                      onClick={() => setShowTooltip(null)}
                    >
                      Close
                    </Button>
                  </div>
                </motion.div>
              )}
            </AnimatePresence>
          </div>

          <div className="flex gap-3">
            <Button type="button" variant="outline" onClick={onPrev}>
              <ArrowLeft className="mr-2 h-4 w-4" />
              Back
            </Button>
            <Button 
              type="submit" 
              disabled={isValidating || !watchToken} 
              className="flex-1"
            >
              {isValidating ? (
                <>
                  <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                  Testing Connection...
                </>
              ) : (
                <>
                  Test Connection
                  <ArrowRight className="ml-2 h-4 w-4" />
                </>
              )}
            </Button>
          </div>
        </form>
      </CardContent>
    </Card>
  )

  const renderTestingStep = () => (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <Loader2 className="h-6 w-6 animate-spin text-primary" />
          Testing Connection
        </CardTitle>
        <CardDescription>
          Verifying your Personal Access Token and checking permissions...
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="flex items-center justify-center py-8">
          <div className="text-center space-y-4">
            <motion.div
              animate={{ rotate: 360 }}
              transition={{ duration: 2, repeat: Infinity, ease: "linear" }}
            >
              <Database className="h-16 w-16 text-primary mx-auto" />
            </motion.div>
            <p className="text-muted-foreground">
              Connecting to Airtable and validating your permissions...
            </p>
          </div>
        </div>

        {connectionResult && (
          <Alert>
            <CheckCircle className="h-4 w-4" />
            <AlertDescription>
              Connection successful! Found {connectionResult.baseCount} accessible bases.
            </AlertDescription>
          </Alert>
        )}
      </CardContent>
    </Card>
  )

  const renderBaseSelectionStep = () => (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <Database className="h-6 w-6 text-primary" />
          Select Your Bases
          {connectionResult && (
            <Badge variant="secondary">
              {availableBases.length} bases found
            </Badge>
          )}
        </CardTitle>
        <CardDescription>
          Choose which Airtable bases you'd like to connect. We'll analyze their structure 
          to provide better AI insights and suggestions.
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-6">
        {error && (
          <Alert variant="destructive">
            <AlertTriangle className="h-4 w-4" />
            <AlertDescription>{error}</AlertDescription>
          </Alert>
        )}

        {/* Connection Success Info */}
        {connectionResult && (
          <Alert>
            <CheckCircle className="h-4 w-4" />
            <AlertDescription>
              <strong>Connected successfully!</strong> 
              {connectionResult.userInfo && (
                <span> Logged in as {connectionResult.userInfo.email}</span>
              )}
              {connectionResult.hasWriteAccess && (
                <span> • Full write access available</span>
              )}
            </AlertDescription>
          </Alert>
        )}

        {/* Search and Filters */}
        <div className="flex gap-4">
          <div className="flex-1 relative">
            <Search className="absolute left-3 top-3 h-4 w-4 text-muted-foreground" />
            <Input
              placeholder="Search bases..."
              className="pl-10"
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
            />
          </div>
          <select
            className="px-3 py-2 border border-input bg-background rounded-md text-sm"
            value={filterPermission}
            onChange={(e) => setFilterPermission(e.target.value as any)}
          >
            <option value="all">All Permissions</option>
            <option value="read">Read Access</option>
            <option value="write">Write Access</option>
          </select>
        </div>

        {/* Bases Grid */}
        {isLoadingBases ? (
          <div className="flex items-center justify-center py-8">
            <Loader2 className="h-8 w-8 animate-spin text-primary" />
            <span className="ml-2">Loading your bases...</span>
          </div>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4 max-h-96 overflow-y-auto">
            {filteredBases.map((base) => (
              <motion.div
                key={base.id}
                whileHover={{ scale: 1.02 }}
                whileTap={{ scale: 0.98 }}
                className={`p-4 border rounded-lg cursor-pointer transition-all ${
                  selectedBases.includes(base.id)
                    ? 'border-primary bg-primary/5 ring-2 ring-primary/20'
                    : 'border-muted hover:border-primary/50'
                }`}
                onClick={() => handleBaseSelection(base.id)}
              >
                <div className="flex items-start justify-between mb-2">
                  <div className="flex-1">
                    <h3 className="font-medium text-lg">{base.name}</h3>
                    {base.description && (
                      <p className="text-sm text-muted-foreground mt-1">{base.description}</p>
                    )}
                  </div>
                  {selectedBases.includes(base.id) && (
                    <CheckCircle className="h-5 w-5 text-primary flex-shrink-0" />
                  )}
                </div>
                
                <div className="flex items-center gap-4 text-sm text-muted-foreground">
                  <div className="flex items-center gap-1">
                    <FileText className="h-4 w-4" />
                    {base.tableCount} tables
                  </div>
                  <div className="flex items-center gap-1">
                    <BarChart3 className="h-4 w-4" />
                    {base.recordCount || 'Unknown'} records
                  </div>
                </div>

                <div className="flex items-center justify-between mt-3">
                  <Badge 
                    variant={base.permissionLevel.includes('write') ? 'default' : 'secondary'}
                    className="text-xs"
                  >
                    {base.permissionLevel}
                  </Badge>
                  <span className="text-xs text-muted-foreground">
                    Created {new Date(base.createdTime).toLocaleDateString()}
                  </span>
                </div>
              </motion.div>
            ))}
          </div>
        )}

        {/* Selection Summary */}
        {selectedBases.length > 0 && (
          <Alert>
            <Info className="h-4 w-4" />
            <AlertDescription>
              <strong>{selectedBases.length} base(s) selected.</strong> 
              {' '}We'll analyze the structure of these bases to provide personalized AI insights.
            </AlertDescription>
          </Alert>
        )}

        <div className="flex gap-3">
          <Button type="button" variant="outline" onClick={onPrev}>
            <ArrowLeft className="mr-2 h-4 w-4" />
            Back
          </Button>
          <Button 
            onClick={analyzeSelectedBases}
            disabled={selectedBases.length === 0 || isAnalyzingStructure}
            className="flex-1"
          >
            {isAnalyzingStructure ? (
              <>
                <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                Analyzing Structure...
              </>
            ) : (
              <>
                Continue with {selectedBases.length} base(s)
                <ArrowRight className="ml-2 h-4 w-4" />
              </>
            )}
          </Button>
        </div>
      </CardContent>
    </Card>
  )

  const renderValidationStep = () => (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <CheckCheck className="h-6 w-6 text-green-600" />
          Setup Complete!
        </CardTitle>
        <CardDescription>
          Successfully connected and analyzed your Airtable bases. Here's what we found:
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-6">
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          <div className="text-center p-4 bg-green-50 rounded-lg">
            <Database className="h-8 w-8 text-green-600 mx-auto mb-2" />
            <div className="text-2xl font-bold text-green-600">{selectedBases.length}</div>
            <div className="text-sm text-green-700">Connected Bases</div>
          </div>
          <div className="text-center p-4 bg-blue-50 rounded-lg">
            <FileText className="h-8 w-8 text-blue-600 mx-auto mb-2" />
            <div className="text-2xl font-bold text-blue-600">
              {Object.values(structureAnalysis).reduce((sum: number, analysis: any) => 
                sum + (analysis.tableCount || 0), 0)}
            </div>
            <div className="text-sm text-blue-700">Total Tables</div>
          </div>
          <div className="text-center p-4 bg-purple-50 rounded-lg">
            <BarChart3 className="h-8 w-8 text-purple-600 mx-auto mb-2" />
            <div className="text-2xl font-bold text-purple-600">
              {Object.values(structureAnalysis).reduce((sum: number, analysis: any) => 
                sum + (analysis.totalRecords || 0), 0)}
            </div>
            <div className="text-sm text-purple-700">Total Records</div>
          </div>
        </div>

        <Alert>
          <CheckCircle className="h-4 w-4" />
          <AlertDescription>
            <strong>Analysis complete!</strong> Your bases are ready for AI-powered insights. 
            We've identified the data structures and will provide personalized recommendations.
          </AlertDescription>
        </Alert>

        <div className="flex gap-3">
          <Button 
            onClick={onNext}
            className="flex-1"
            size="lg"
          >
            Continue to Organization Setup
            <ArrowRight className="ml-2 h-5 w-5" />
          </Button>
        </div>
      </CardContent>
    </Card>
  )

  return (
    <div className="space-y-6">
      <AnimatePresence mode="wait">
        <motion.div
          key={currentSubStep}
          initial={{ opacity: 0, x: 20 }}
          animate={{ opacity: 1, x: 0 }}
          exit={{ opacity: 0, x: -20 }}
          transition={{ duration: 0.3 }}
        >
          {currentSubStep === 'token' && renderTokenStep()}
          {currentSubStep === 'testing' && renderTestingStep()}
          {currentSubStep === 'bases' && renderBaseSelectionStep()}
          {currentSubStep === 'validation' && renderValidationStep()}
        </motion.div>
      </AnimatePresence>
    </div>
  )
}