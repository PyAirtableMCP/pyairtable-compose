"use client"

import React, { useState, useEffect } from "react"
import { motion, AnimatePresence } from "framer-motion"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Badge } from "@/components/ui/badge"
import { Separator } from "@/components/ui/separator"
import { Input } from "@/components/ui/input"
import { 
  Loader2, 
  Database, 
  Table,
  ArrowRight, 
  ArrowLeft,
  Search,
  Filter,
  Eye,
  Settings,
  CheckCircle,
  AlertTriangle,
  Info,
  BarChart3,
  FileText,
  Hash,
  Calendar,
  Link,
  Image,
  Type,
  ToggleLeft,
  Star,
  Users,
  Globe,
  Zap,
  Brain,
  Target,
  TrendingUp,
  Lightbulb,
  Shield,
  Clock,
  RefreshCw,
  Download,
  Upload
} from "lucide-react"
import toast from "react-hot-toast"

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

interface TableAnalysis {
  tableId: string
  tableName: string
  recordCount: number
  fieldCount: number
  dataTypes: { [key: string]: number }
  relationships: string[]
  suggestedQueries: string[]
  dataQuality: {
    completeness: number
    consistency: number
    duplicates: number
  }
  aiInsights: {
    primaryUseCase: string
    keyFields: string[]
    automationOpportunities: string[]
    chartSuggestions: string[]
  }
}

interface WorkspaceConfiguration {
  name: string
  description: string
  selectedTables: string[]
  permissions: {
    [tableId: string]: {
      read: boolean
      write: boolean
      delete: boolean
    }
  }
  preferences: {
    enableAIInsights: boolean
    enableAutomations: boolean
    dataRefreshInterval: number
    notificationSettings: string[]
  }
}

interface BaseConfigurationStepProps {
  availableBases: AirtableBase[]
  selectedBases: AirtableBase[]
  onUpdate: (bases: AirtableBase[]) => void
  onNext: () => void
  onPrev: () => void
  error: string | null
  setError: (error: string | null) => void
}

export default function BaseConfigurationStep({
  availableBases,
  selectedBases,
  onUpdate,
  onNext,
  onPrev,
  error,
  setError
}: BaseConfigurationStepProps) {
  const [currentStep, setCurrentStep] = useState<'overview' | 'analysis' | 'configuration' | 'validation'>('overview')
  const [isAnalyzing, setIsAnalyzing] = useState(false)
  const [analysisResults, setAnalysisResults] = useState<{ [baseId: string]: TableAnalysis[] }>({})
  const [selectedTables, setSelectedTables] = useState<{ [baseId: string]: string[] }>({})
  const [workspaceConfig, setWorkspaceConfig] = useState<WorkspaceConfiguration>({
    name: 'My PyAirtable Workspace',
    description: '',
    selectedTables: [],
    permissions: {},
    preferences: {
      enableAIInsights: true,
      enableAutomations: true,
      dataRefreshInterval: 300, // 5 minutes
      notificationSettings: ['data_changes', 'automation_results']
    }
  })
  const [searchTerm, setSearchTerm] = useState('')
  const [filterDataType, setFilterDataType] = useState<string>('all')
  const [expandedBase, setExpandedBase] = useState<string | null>(null)

  const analyzeBaseStructure = async (baseId: string) => {
    try {
      const response = await fetch('/api/airtable/analyze-structure', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ baseId })
      })

      if (!response.ok) {
        throw new Error('Failed to analyze base structure')
      }

      const analysis = await response.json()
      return analysis.tables as TableAnalysis[]
    } catch (error) {
      console.error('Base analysis error:', error)
      throw error
    }
  }

  const performStructureAnalysis = async () => {
    setIsAnalyzing(true)
    setCurrentStep('analysis')

    try {
      const results = {}
      for (const base of selectedBases) {
        const tableAnalyses = await analyzeBaseStructure(base.id)
        results[base.id] = tableAnalyses
      }

      setAnalysisResults(results)
      setCurrentStep('configuration')
      toast.success('Structure analysis completed! 🎉')
    } catch (error) {
      setError(error instanceof Error ? error.message : 'Failed to analyze base structures')
      setCurrentStep('overview')
    } finally {
      setIsAnalyzing(false)
    }
  }

  const handleTableSelection = (baseId: string, tableId: string) => {
    setSelectedTables(prev => {
      const baseTables = prev[baseId] || []
      const updated = baseTables.includes(tableId)
        ? baseTables.filter(id => id !== tableId)
        : [...baseTables, tableId]
      
      return {
        ...prev,
        [baseId]: updated
      }
    })
  }

  const generateAISuggestions = (analysis: TableAnalysis) => {
    const suggestions = []
    
    if (analysis.dataQuality.completeness < 80) {
      suggestions.push({
        type: 'data_quality',
        icon: <AlertTriangle className="h-4 w-4 text-amber-500" />,
        message: `${analysis.tableName} has ${100 - analysis.dataQuality.completeness}% missing data. Consider data cleanup.`
      })
    }

    if (analysis.aiInsights.automationOpportunities.length > 0) {
      suggestions.push({
        type: 'automation',
        icon: <Zap className="h-4 w-4 text-blue-500" />,
        message: `Found ${analysis.aiInsights.automationOpportunities.length} automation opportunities in ${analysis.tableName}.`
      })
    }

    if (analysis.dataTypes['date'] && analysis.dataTypes['number']) {
      suggestions.push({
        type: 'visualization',
        icon: <TrendingUp className="h-4 w-4 text-green-500" />,
        message: `${analysis.tableName} is perfect for time-series analysis and trending charts.`
      })
    }

    return suggestions
  }

  const getFieldTypeIcon = (fieldType: string) => {
    const icons = {
      'singleLineText': <Type className="h-4 w-4" />,
      'multipleRecordLinks': <Link className="h-4 w-4" />,
      'number': <Hash className="h-4 w-4" />,
      'date': <Calendar className="h-4 w-4" />,
      'attachment': <Image className="h-4 w-4" />,
      'checkbox': <ToggleLeft className="h-4 w-4" />,
      'multipleSelects': <Filter className="h-4 w-4" />,
      'singleSelect': <Target className="h-4 w-4" />
    }
    return icons[fieldType] || <FileText className="h-4 w-4" />
  }

  const calculateSetupScore = () => {
    const totalTables = Object.values(selectedTables).flat().length
    const totalBases = selectedBases.length
    const hasWorkspaceName = workspaceConfig.name.length > 0
    const hasDescription = workspaceConfig.description.length > 0
    
    let score = 0
    if (totalBases > 0) score += 30
    if (totalTables > 0) score += 40
    if (hasWorkspaceName) score += 15
    if (hasDescription) score += 15
    
    return Math.min(score, 100)
  }

  const renderOverviewStep = () => (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <Database className="h-6 w-6 text-primary" />
          Base Structure Overview
        </CardTitle>
        <CardDescription>
          Let's analyze your selected bases to understand their structure and identify 
          opportunities for AI-powered insights and automation.
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-6">
        {/* Selected Bases Summary */}
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          <div className="text-center p-4 bg-blue-50 rounded-lg">
            <Database className="h-8 w-8 text-blue-600 mx-auto mb-2" />
            <div className="text-2xl font-bold text-blue-600">{selectedBases.length}</div>
            <div className="text-sm text-blue-700">Connected Bases</div>
          </div>
          <div className="text-center p-4 bg-green-50 rounded-lg">
            <Table className="h-8 w-8 text-green-600 mx-auto mb-2" />
            <div className="text-2xl font-bold text-green-600">
              {selectedBases.reduce((sum, base) => sum + (base.tableCount || 0), 0)}
            </div>
            <div className="text-sm text-green-700">Total Tables</div>
          </div>
          <div className="text-center p-4 bg-purple-50 rounded-lg">
            <BarChart3 className="h-8 w-8 text-purple-600 mx-auto mb-2" />
            <div className="text-2xl font-bold text-purple-600">
              {selectedBases.reduce((sum, base) => sum + (base.recordCount || 0), 0)}
            </div>
            <div className="text-sm text-purple-700">Total Records</div>
          </div>
        </div>

        {/* Base Details */}
        <div className="space-y-4">
          <h3 className="text-lg font-semibold">Your Connected Bases</h3>
          {selectedBases.map((base) => (
            <div key={base.id} className="border rounded-lg p-4">
              <div className="flex items-center justify-between mb-3">
                <div>
                  <h4 className="font-medium text-lg">{base.name}</h4>
                  {base.description && (
                    <p className="text-sm text-muted-foreground">{base.description}</p>
                  )}
                </div>
                <Badge variant={base.permissionLevel.includes('write') ? 'default' : 'secondary'}>
                  {base.permissionLevel}
                </Badge>
              </div>
              
              <div className="grid grid-cols-2 md:grid-cols-4 gap-4 text-sm">
                <div className="flex items-center gap-2">
                  <Table className="h-4 w-4 text-muted-foreground" />
                  <span>{base.tableCount} tables</span>
                </div>
                <div className="flex items-center gap-2">
                  <BarChart3 className="h-4 w-4 text-muted-foreground" />
                  <span>{base.recordCount || 'Unknown'} records</span>
                </div>
                <div className="flex items-center gap-2">
                  <Clock className="h-4 w-4 text-muted-foreground" />
                  <span>Created {new Date(base.createdTime).toLocaleDateString()}</span>
                </div>
                <div className="flex items-center gap-2">
                  <Shield className="h-4 w-4 text-muted-foreground" />
                  <span>Secure connection</span>
                </div>
              </div>
            </div>
          ))}
        </div>

        <Alert>
          <Lightbulb className="h-4 w-4" />
          <AlertDescription>
            <strong>What's next?</strong> We'll analyze your base structures to identify:
            <ul className="list-disc list-inside mt-2 space-y-1">
              <li>Data relationships and patterns</li>
              <li>Opportunities for automation</li>
              <li>Suggested AI queries and insights</li>
              <li>Data quality recommendations</li>
            </ul>
          </AlertDescription>
        </Alert>

        <div className="flex gap-3">
          <Button type="button" variant="outline" onClick={onPrev}>
            <ArrowLeft className="mr-2 h-4 w-4" />
            Back
          </Button>
          <Button onClick={performStructureAnalysis} className="flex-1" size="lg">
            Analyze Base Structures
            <Brain className="ml-2 h-5 w-5" />
          </Button>
        </div>
      </CardContent>
    </Card>
  )

  const renderAnalysisStep = () => (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <Loader2 className="h-6 w-6 animate-spin text-primary" />
          Analyzing Your Data Structure
        </CardTitle>
        <CardDescription>
          Our AI is examining your bases to understand data relationships, 
          identify patterns, and suggest optimization opportunities.
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-6">
        <div className="flex items-center justify-center py-12">
          <div className="text-center space-y-6">
            <motion.div
              animate={{ scale: [1, 1.1, 1] }}
              transition={{ duration: 2, repeat: Infinity }}
              className="relative"
            >
              <Brain className="h-20 w-20 text-primary mx-auto" />
              <motion.div
                animate={{ rotate: 360 }}
                transition={{ duration: 3, repeat: Infinity, ease: "linear" }}
                className="absolute -top-2 -right-2"
              >
                <Zap className="h-8 w-8 text-yellow-500" />
              </motion.div>
            </motion.div>
            
            <div className="space-y-2">
              <h3 className="text-xl font-semibold">AI Analysis in Progress</h3>
              <p className="text-muted-foreground">
                Analyzing data types, relationships, and patterns...
              </p>
            </div>

            <div className="flex items-center justify-center gap-2">
              <div className="w-2 h-2 bg-primary rounded-full animate-bounce [animation-delay:-0.3s]"></div>
              <div className="w-2 h-2 bg-primary rounded-full animate-bounce [animation-delay:-0.15s]"></div>
              <div className="w-2 h-2 bg-primary rounded-full animate-bounce"></div>
            </div>
          </div>
        </div>
      </CardContent>
    </Card>
  )

  const renderConfigurationStep = () => (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <Settings className="h-6 w-6 text-primary" />
          Configure Your Workspace
        </CardTitle>
        <CardDescription>
          Review the analysis results and configure your workspace preferences.
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-6">
        {/* Workspace Configuration */}
        <div className="space-y-4">
          <h3 className="text-lg font-semibold">Workspace Settings</h3>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div>
              <label className="text-sm font-medium">Workspace Name</label>
              <Input
                value={workspaceConfig.name}
                onChange={(e) => setWorkspaceConfig(prev => ({ ...prev, name: e.target.value }))}
                placeholder="My PyAirtable Workspace"
              />
            </div>
            <div>
              <label className="text-sm font-medium">Description (Optional)</label>
              <Input
                value={workspaceConfig.description}
                onChange={(e) => setWorkspaceConfig(prev => ({ ...prev, description: e.target.value }))}
                placeholder="Brief description of your workspace"
              />
            </div>
          </div>
        </div>

        <Separator />

        {/* Analysis Results */}
        <div className="space-y-4">
          <div className="flex items-center justify-between">
            <h3 className="text-lg font-semibold">Analysis Results & Table Selection</h3>
            <div className="flex items-center gap-2">
              <Search className="h-4 w-4 text-muted-foreground" />
              <Input
                placeholder="Search tables..."
                className="w-48"
                value={searchTerm}
                onChange={(e) => setSearchTerm(e.target.value)}
              />
            </div>
          </div>

          <div className="space-y-4">
            {selectedBases.map((base) => {
              const baseAnalysis = analysisResults[base.id] || []
              const selectedCount = selectedTables[base.id]?.length || 0
              
              return (
                <div key={base.id} className="border rounded-lg p-4">
                  <div 
                    className="flex items-center justify-between cursor-pointer"
                    onClick={() => setExpandedBase(expandedBase === base.id ? null : base.id)}
                  >
                    <div className="flex items-center gap-3">
                      <Database className="h-5 w-5 text-primary" />
                      <div>
                        <h4 className="font-medium">{base.name}</h4>
                        <p className="text-sm text-muted-foreground">
                          {baseAnalysis.length} tables analyzed • {selectedCount} selected
                        </p>
                      </div>
                    </div>
                    <div className="flex items-center gap-2">
                      <Badge variant="outline">{selectedCount}/{baseAnalysis.length} selected</Badge>
                      <Button variant="ghost" size="sm">
                        {expandedBase === base.id ? 'Collapse' : 'Expand'}
                      </Button>
                    </div>
                  </div>

                  <AnimatePresence>
                    {expandedBase === base.id && (
                      <motion.div
                        initial={{ opacity: 0, height: 0 }}
                        animate={{ opacity: 1, height: 'auto' }}
                        exit={{ opacity: 0, height: 0 }}
                        className="mt-4 space-y-3"
                      >
                        {baseAnalysis
                          .filter(table => 
                            searchTerm === '' || 
                            table.tableName.toLowerCase().includes(searchTerm.toLowerCase())
                          )
                          .map((table) => {
                            const isSelected = selectedTables[base.id]?.includes(table.tableId)
                            const suggestions = generateAISuggestions(table)
                            
                            return (
                              <div
                                key={table.tableId}
                                className={`p-4 border rounded-lg cursor-pointer transition-all ${
                                  isSelected 
                                    ? 'border-primary bg-primary/5 ring-1 ring-primary/20' 
                                    : 'hover:border-primary/50'
                                }`}
                                onClick={() => handleTableSelection(base.id, table.tableId)}
                              >
                                <div className="flex items-start justify-between mb-3">
                                  <div className="flex items-center gap-3">
                                    <Table className="h-5 w-5 text-muted-foreground" />
                                    <div>
                                      <h5 className="font-medium">{table.tableName}</h5>
                                      <p className="text-sm text-muted-foreground">
                                        {table.recordCount} records • {table.fieldCount} fields
                                      </p>
                                    </div>
                                  </div>
                                  {isSelected && (
                                    <CheckCircle className="h-5 w-5 text-primary" />
                                  )}
                                </div>

                                {/* Data Types */}
                                <div className="flex flex-wrap gap-2 mb-3">
                                  {Object.entries(table.dataTypes).map(([type, count]) => (
                                    <div key={type} className="flex items-center gap-1 text-xs">
                                      {getFieldTypeIcon(type)}
                                      <span>{type}: {count}</span>
                                    </div>
                                  ))}
                                </div>

                                {/* AI Insights */}
                                <div className="space-y-2">
                                  <div className="flex items-center gap-2">
                                    <Brain className="h-4 w-4 text-purple-500" />
                                    <span className="text-sm font-medium">AI Insights:</span>
                                    <span className="text-sm text-muted-foreground">
                                      {table.aiInsights.primaryUseCase}
                                    </span>
                                  </div>

                                  {suggestions.length > 0 && (
                                    <div className="space-y-1">
                                      {suggestions.map((suggestion, idx) => (
                                        <div key={idx} className="flex items-center gap-2 text-xs">
                                          {suggestion.icon}
                                          <span>{suggestion.message}</span>
                                        </div>
                                      ))}
                                    </div>
                                  )}
                                </div>

                                {/* Data Quality Score */}
                                <div className="mt-3 flex items-center gap-4 text-sm">
                                  <div className="flex items-center gap-1">
                                    <span>Data Quality:</span>
                                    <Badge 
                                      variant={table.dataQuality.completeness > 80 ? 'default' : 'secondary'}
                                    >
                                      {table.dataQuality.completeness}%
                                    </Badge>
                                  </div>
                                  {table.aiInsights.automationOpportunities.length > 0 && (
                                    <div className="flex items-center gap-1">
                                      <Zap className="h-3 w-3 text-yellow-500" />
                                      <span>{table.aiInsights.automationOpportunities.length} automation opportunities</span>
                                    </div>
                                  )}
                                </div>
                              </div>
                            )
                          })}
                      </motion.div>
                    )}
                  </AnimatePresence>
                </div>
              )
            })}
          </div>
        </div>

        {/* Setup Progress */}
        <div className="bg-gray-50 p-4 rounded-lg">
          <div className="flex items-center justify-between mb-2">
            <span className="text-sm font-medium">Setup Progress</span>
            <span className="text-sm text-muted-foreground">{calculateSetupScore()}%</span>
          </div>
          <div className="w-full bg-gray-200 rounded-full h-2">
            <div 
              className="bg-primary h-2 rounded-full transition-all duration-300"
              style={{ width: `${calculateSetupScore()}%` }}
            ></div>
          </div>
        </div>

        <div className="flex gap-3">
          <Button type="button" variant="outline" onClick={onPrev}>
            <ArrowLeft className="mr-2 h-4 w-4" />
            Back
          </Button>
          <Button 
            onClick={() => setCurrentStep('validation')} 
            className="flex-1"
            disabled={Object.values(selectedTables).flat().length === 0}
          >
            Continue Setup
            <ArrowRight className="ml-2 h-4 w-4" />
          </Button>
        </div>
      </CardContent>
    </Card>
  )

  const renderValidationStep = () => {
    const totalSelectedTables = Object.values(selectedTables).flat().length
    const setupScore = calculateSetupScore()
    
    return (
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <CheckCircle className="h-6 w-6 text-green-600" />
            Configuration Complete!
          </CardTitle>
          <CardDescription>
            Your workspace is configured and ready for AI-powered insights.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-6">
          {/* Summary Statistics */}
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
            <div className="text-center p-4 bg-blue-50 rounded-lg">
              <Database className="h-8 w-8 text-blue-600 mx-auto mb-2" />
              <div className="text-2xl font-bold text-blue-600">{selectedBases.length}</div>
              <div className="text-sm text-blue-700">Connected Bases</div>
            </div>
            <div className="text-center p-4 bg-green-50 rounded-lg">
              <Table className="h-8 w-8 text-green-600 mx-auto mb-2" />
              <div className="text-2xl font-bold text-green-600">{totalSelectedTables}</div>
              <div className="text-sm text-green-700">Selected Tables</div>
            </div>
            <div className="text-center p-4 bg-purple-50 rounded-lg">
              <Brain className="h-8 w-8 text-purple-600 mx-auto mb-2" />
              <div className="text-2xl font-bold text-purple-600">
                {Object.values(analysisResults).flat().length}
              </div>
              <div className="text-sm text-purple-700">AI Insights Generated</div>
            </div>
            <div className="text-center p-4 bg-orange-50 rounded-lg">
              <Star className="h-8 w-8 text-orange-600 mx-auto mb-2" />
              <div className="text-2xl font-bold text-orange-600">{setupScore}%</div>
              <div className="text-sm text-orange-700">Setup Complete</div>
            </div>
          </div>

          {/* Configuration Summary */}
          <Alert>
            <CheckCircle className="h-4 w-4" />
            <AlertDescription>
              <strong>Workspace "{workspaceConfig.name}" is ready!</strong>
              <br />
              You've configured {totalSelectedTables} tables across {selectedBases.length} bases. 
              Our AI has analyzed your data structure and is ready to provide intelligent insights.
            </AlertDescription>
          </Alert>

          {/* AI Recommendations */}
          <div className="space-y-3">
            <h3 className="font-semibold">🎯 AI Recommendations for Your Setup:</h3>
            <div className="space-y-2">
              {Object.values(analysisResults).flat().slice(0, 3).map((table, idx) => (
                <div key={idx} className="flex items-start gap-3 p-3 bg-blue-50 rounded-lg">
                  <Lightbulb className="h-4 w-4 text-blue-600 mt-0.5" />
                  <div className="flex-1">
                    <p className="text-sm">
                      <strong>{table.tableName}:</strong> {table.aiInsights.primaryUseCase}
                    </p>
                    {table.aiInsights.automationOpportunities.length > 0 && (
                      <p className="text-xs text-muted-foreground mt-1">
                        Automation opportunity: {table.aiInsights.automationOpportunities[0]}
                      </p>
                    )}
                  </div>
                </div>
              ))}
            </div>
          </div>

          <div className="flex gap-3">
            <Button type="button" variant="outline" onClick={onPrev}>
              <ArrowLeft className="mr-2 h-4 w-4" />
              Back to Configuration
            </Button>
            <Button onClick={onNext} className="flex-1" size="lg">
              Continue to Organization Setup
              <ArrowRight className="ml-2 h-5 w-5" />
            </Button>
          </div>
        </CardContent>
      </Card>
    )
  }

  return (
    <div className="space-y-6">
      {error && (
        <Alert variant="destructive">
          <AlertTriangle className="h-4 w-4" />
          <AlertDescription>{error}</AlertDescription>
        </Alert>
      )}

      <AnimatePresence mode="wait">
        <motion.div
          key={currentStep}
          initial={{ opacity: 0, x: 20 }}
          animate={{ opacity: 1, x: 0 }}
          exit={{ opacity: 0, x: -20 }}
          transition={{ duration: 0.3 }}
        >
          {currentStep === 'overview' && renderOverviewStep()}
          {currentStep === 'analysis' && renderAnalysisStep()}
          {currentStep === 'configuration' && renderConfigurationStep()}
          {currentStep === 'validation' && renderValidationStep()}
        </motion.div>
      </AnimatePresence>
    </div>
  )
}