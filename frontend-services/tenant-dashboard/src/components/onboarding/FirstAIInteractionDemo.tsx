"use client"

import React, { useState, useEffect, useRef } from "react"
import { motion, AnimatePresence } from "framer-motion"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Badge } from "@/components/ui/badge"
import { Separator } from "@/components/ui/separator"
import { 
  MessageSquare,
  Send,
  Brain,
  ArrowRight, 
  ArrowLeft,
  Sparkles,
  BarChart3,
  TrendingUp,
  Users,
  Calendar,
  Target,
  Lightbulb,
  CheckCircle,
  Clock,
  Star,
  ThumbsUp,
  ThumbsDown,
  Copy,
  Download,
  Share2,
  RefreshCw,
  Zap,
  Eye,
  Settings,
  HelpCircle,
  Wand2,
  Database,
  Filter,
  Search,
  PieChart,
  LineChart,
  Activity,
  Globe,
  Shield,
  FileText,
  Image,
  Play,
  Pause
} from "lucide-react"
import toast from "react-hot-toast"

interface AirtableBase {
  id: string
  name: string
  tables?: AirtableTable[]
}

interface AirtableTable {
  id: string
  name: string
  fields: AirtableField[]
}

interface AirtableField {
  id: string
  name: string
  type: string
}

interface ChatMessage {
  id: string
  type: 'user' | 'assistant' | 'system'
  content: string
  timestamp: Date
  metadata?: {
    query?: string
    visualization?: any
    suggestions?: string[]
    confidence?: number
    executionTime?: number
  }
}

interface QuerySuggestion {
  id: string
  category: 'basic' | 'analytical' | 'exploratory' | 'advanced'
  title: string
  description: string
  query: string
  expectedResult: string
  complexity: 1 | 2 | 3
  icon: React.ReactNode
}

interface FirstAIInteractionDemoProps {
  selectedBases: AirtableBase[]
  onQueryComplete: () => void
  onFeedbackSubmit: (feedback: any) => void
  onNext: () => void
  onPrev: () => void
  error: string | null
  setError: (error: string | null) => void
}

const SAMPLE_SUGGESTIONS: QuerySuggestion[] = [
  {
    id: 'basic_count',
    category: 'basic',
    title: 'Get Record Count',
    description: 'See how many records are in your tables',
    query: 'How many records do I have in total?',
    expectedResult: 'Shows total record count across all connected tables',
    complexity: 1,
    icon: <Database className="h-4 w-4" />
  },
  {
    id: 'recent_data',
    category: 'basic',
    title: 'Recent Activity',
    description: 'Find recently created or updated records',
    query: 'Show me records created in the last 7 days',
    expectedResult: 'Lists recent records with creation dates',
    complexity: 1,
    icon: <Clock className="h-4 w-4" />
  },
  {
    id: 'trend_analysis',
    category: 'analytical',
    title: 'Trend Analysis',
    description: 'Identify patterns and trends in your data',
    query: 'What trends can you see in my data over the last 3 months?',
    expectedResult: 'Charts and insights showing data trends',
    complexity: 2,
    icon: <TrendingUp className="h-4 w-4" />
  },
  {
    id: 'top_performers',
    category: 'analytical',
    title: 'Top Performers',
    description: 'Find your highest performing items or categories',
    query: 'Which items have the highest values?',
    expectedResult: 'Ranked list of top performing items',
    complexity: 2,
    icon: <Star className="h-4 w-4" />
  },
  {
    id: 'missing_data',
    category: 'exploratory',
    title: 'Data Quality Check',
    description: 'Find incomplete or missing data',
    query: 'Are there any records with missing important information?',
    expectedResult: 'Report on data completeness and quality',
    complexity: 2,
    icon: <Shield className="h-4 w-4" />
  },
  {
    id: 'correlation_analysis',
    category: 'advanced',
    title: 'Find Relationships',
    description: 'Discover correlations between different data points',
    query: 'What relationships exist between different fields in my data?',
    expectedResult: 'Statistical correlation analysis and insights',
    complexity: 3,
    icon: <Activity className="h-4 w-4" />
  },
  {
    id: 'predictive_insights',
    category: 'advanced',
    title: 'Predictive Analysis',
    description: 'Get AI predictions based on your data patterns',
    query: 'Based on historical data, what predictions can you make?',
    expectedResult: 'Forecasts and predictions with confidence intervals',
    complexity: 3,
    icon: <Brain className="h-4 w-4" />
  },
  {
    id: 'custom_visualization',
    category: 'advanced',
    title: 'Smart Visualizations',
    description: 'Generate intelligent charts and graphs',
    query: 'Create the best visualization for my data',
    expectedResult: 'AI-selected optimal charts with insights',
    complexity: 3,
    icon: <BarChart3 className="h-4 w-4" />
  }
]

const DEMO_RESPONSES = {
  'How many records do I have in total?': {
    type: 'data_summary',
    content: "I found a total of **2,847 records** across your connected bases:\n\n📊 **Breakdown by Base:**\n• Customer Database: 1,234 records\n• Sales Tracker: 892 records\n• Product Catalog: 721 records\n\n🔍 **Quick Insights:**\n• Most active table: Customer Database\n• Average records per table: 949\n• Data spans from Jan 2023 to present",
    visualization: {
      type: 'bar',
      data: [
        { name: 'Customer Database', value: 1234 },
        { name: 'Sales Tracker', value: 892 },
        { name: 'Product Catalog', value: 721 }
      ]
    },
    suggestions: [
      "Analyze customer growth trends",
      "Review sales performance by month",
      "Check product catalog completeness"
    ],
    confidence: 98,
    executionTime: 1.2
  },
  'Show me records created in the last 7 days': {
    type: 'filtered_data',
    content: "Found **47 new records** created in the last 7 days:\n\n📈 **Daily Breakdown:**\n• Monday: 12 records\n• Tuesday: 8 records\n• Wednesday: 15 records\n• Thursday: 6 records\n• Friday: 4 records\n• Weekend: 2 records\n\n🎯 **Most Active Areas:**\n• New customer registrations: 28 records\n• Product updates: 12 records\n• Sales entries: 7 records",
    visualization: {
      type: 'line',
      data: [
        { day: 'Mon', count: 12 },
        { day: 'Tue', count: 8 },
        { day: 'Wed', count: 15 },
        { day: 'Thu', count: 6 },
        { day: 'Fri', count: 4 },
        { day: 'Sat', count: 1 },
        { day: 'Sun', count: 1 }
      ]
    },
    suggestions: [
      "Set up automation for new customer welcome",
      "Analyze what drives Wednesday spikes",
      "Create alerts for daily activity thresholds"
    ],
    confidence: 95,
    executionTime: 0.8
  }
}

export default function FirstAIInteractionDemo({
  selectedBases,
  onQueryComplete,
  onFeedbackSubmit,
  onNext,
  onPrev,
  error,
  setError
}: FirstAIInteractionDemoProps) {
  const [messages, setMessages] = useState<ChatMessage[]>([
    {
      id: '1',
      type: 'system',
      content: 'Welcome! I\'m your AI assistant, ready to help you explore your data. Try asking me a question about your connected Airtable bases, or choose from the suggestions below.',
      timestamp: new Date()
    }
  ])
  const [currentQuery, setCurrentQuery] = useState('')
  const [isProcessing, setIsProcessing] = useState(false)
  const [selectedSuggestion, setSelectedSuggestion] = useState<QuerySuggestion | null>(null)
  const [showAdvanced, setShowAdvanced] = useState(false)
  const [feedback, setFeedback] = useState<{[messageId: string]: 'good' | 'bad' | null}>({})
  const [queryCount, setQueryCount] = useState(0)
  const [showInsights, setShowInsights] = useState(false)
  const chatEndRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    chatEndRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [messages])

  const simulateAIResponse = async (query: string): Promise<ChatMessage> => {
    await new Promise(resolve => setTimeout(resolve, 1500 + Math.random() * 1000))
    
    const demoResponse = DEMO_RESPONSES[query as keyof typeof DEMO_RESPONSES]
    
    if (demoResponse) {
      return {
        id: Date.now().toString(),
        type: 'assistant',
        content: demoResponse.content,
        timestamp: new Date(),
        metadata: {
          query,
          visualization: demoResponse.visualization,
          suggestions: demoResponse.suggestions,
          confidence: demoResponse.confidence,
          executionTime: demoResponse.executionTime
        }
      }
    }

    // Fallback response for custom queries
    return {
      id: Date.now().toString(),
      type: 'assistant',
      content: `Great question! "${query}"\n\nI'm analyzing your data across ${selectedBases.length} connected bases. This is a demo response showing how I would process your query using advanced AI algorithms.\n\n🔍 **What I would do:**\n• Parse your natural language query\n• Identify relevant data sources\n• Execute optimized data analysis\n• Generate insights and visualizations\n• Provide actionable recommendations`,
      timestamp: new Date(),
      metadata: {
        query,
        suggestions: [
          "Try more specific date ranges",
          "Ask about specific metrics",
          "Request comparative analysis"
        ],
        confidence: 87,
        executionTime: 2.1
      }
    }
  }

  const handleSendQuery = async (query: string = currentQuery) => {
    if (!query.trim()) return

    // Add user message
    const userMessage: ChatMessage = {
      id: Date.now().toString(),
      type: 'user',
      content: query,
      timestamp: new Date()
    }

    setMessages(prev => [...prev, userMessage])
    setCurrentQuery('')
    setIsProcessing(true)
    setQueryCount(prev => prev + 1)

    try {
      const aiResponse = await simulateAIResponse(query)
      setMessages(prev => [...prev, aiResponse])
      
      if (queryCount === 0) {
        onQueryComplete()
        toast.success("🎉 Great job! You've completed your first AI query.")
      }
    } catch (error) {
      setError("Failed to process query. This is a demo, so some features are simulated.")
    } finally {
      setIsProcessing(false)
    }
  }

  const handleSuggestionClick = (suggestion: QuerySuggestion) => {
    setSelectedSuggestion(suggestion)
    handleSendQuery(suggestion.query)
  }

  const handleFeedback = (messageId: string, rating: 'good' | 'bad') => {
    setFeedback(prev => ({
      ...prev,
      [messageId]: prev[messageId] === rating ? null : rating
    }))
  }

  const renderMessage = (message: ChatMessage) => {
    const isUser = message.type === 'user'
    const isSystem = message.type === 'system'

    return (
      <motion.div
        key={message.id}
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        className={`flex ${isUser ? 'justify-end' : 'justify-start'} mb-4`}
      >
        <div className={`max-w-[80%] ${isUser ? 'order-2' : 'order-1'}`}>
          <div
            className={`rounded-2xl px-4 py-3 ${
              isUser 
                ? 'bg-primary text-primary-foreground ml-4' 
                : isSystem 
                  ? 'bg-blue-50 border border-blue-200 text-blue-800'
                  : 'bg-gray-100 text-gray-900 mr-4'
            }`}
          >
            {!isUser && (
              <div className="flex items-center gap-2 mb-2">
                <Brain className="h-4 w-4 text-primary" />
                <span className="text-sm font-medium">PyAirtable AI</span>
                {message.metadata?.confidence && (
                  <Badge variant="outline" className="text-xs">
                    {message.metadata.confidence}% confident
                  </Badge>
                )}
              </div>
            )}
            
            <div className="prose prose-sm max-w-none">
              {message.content.split('\n').map((line, idx) => (
                <p key={idx} className="mb-2 last:mb-0">
                  {line.startsWith('•') ? (
                    <span className="flex items-start gap-2">
                      <span className="w-1.5 h-1.5 rounded-full bg-current mt-2 flex-shrink-0" />
                      <span>{line.substring(2)}</span>
                    </span>
                  ) : line.startsWith('**') && line.endsWith('**') ? (
                    <strong>{line.slice(2, -2)}</strong>
                  ) : (
                    line
                  )}
                </p>
              ))}
            </div>

            {message.metadata?.executionTime && (
              <div className="mt-2 text-xs opacity-70">
                Analyzed in {message.metadata.executionTime}s
              </div>
            )}
          </div>

          {/* Visualization */}
          {message.metadata?.visualization && (
            <div className="mt-3 p-3 bg-white rounded-lg border">
              <div className="flex items-center justify-between mb-3">
                <h4 className="font-medium flex items-center gap-2">
                  <BarChart3 className="h-4 w-4" />
                  Data Visualization
                </h4>
                <div className="flex gap-1">
                  <Button size="sm" variant="ghost">
                    <Download className="h-3 w-3" />
                  </Button>
                  <Button size="sm" variant="ghost">
                    <Share2 className="h-3 w-3" />
                  </Button>
                </div>
              </div>
              
              <div className="h-48 bg-gradient-to-br from-blue-50 to-purple-50 rounded flex items-center justify-center">
                <div className="text-center">
                  {message.metadata.visualization.type === 'bar' && (
                    <BarChart3 className="h-12 w-12 mx-auto mb-2 text-primary" />
                  )}
                  {message.metadata.visualization.type === 'line' && (
                    <LineChart className="h-12 w-12 mx-auto mb-2 text-primary" />
                  )}
                  {message.metadata.visualization.type === 'pie' && (
                    <PieChart className="h-12 w-12 mx-auto mb-2 text-primary" />
                  )}
                  <p className="text-sm text-muted-foreground">
                    Interactive {message.metadata.visualization.type} chart would appear here
                  </p>
                </div>
              </div>
            </div>
          )}

          {/* Suggestions */}
          {message.metadata?.suggestions && (
            <div className="mt-3 space-y-2">
              <p className="text-sm font-medium flex items-center gap-2">
                <Lightbulb className="h-3 w-3" />
                Follow-up suggestions:
              </p>
              {message.metadata.suggestions.map((suggestion, idx) => (
                <Button
                  key={idx}
                  variant="outline"
                  size="sm"
                  className="text-left h-auto p-2 block w-full"
                  onClick={() => handleSendQuery(suggestion)}
                >
                  {suggestion}
                </Button>
              ))}
            </div>
          )}

          {/* Feedback */}
          {!isUser && !isSystem && (
            <div className="flex items-center gap-2 mt-3">
              <span className="text-xs text-muted-foreground">Was this helpful?</span>
              <Button
                size="sm"
                variant={feedback[message.id] === 'good' ? 'default' : 'ghost'}
                onClick={() => handleFeedback(message.id, 'good')}
              >
                <ThumbsUp className="h-3 w-3" />
              </Button>
              <Button
                size="sm"
                variant={feedback[message.id] === 'bad' ? 'default' : 'ghost'}
                onClick={() => handleFeedback(message.id, 'bad')}
              >
                <ThumbsDown className="h-3 w-3" />
              </Button>
            </div>
          )}
        </div>
      </motion.div>
    )
  }

  const filteredSuggestions = SAMPLE_SUGGESTIONS.filter(suggestion => 
    showAdvanced || suggestion.category !== 'advanced'
  )

  return (
    <div className="space-y-6">
      {error && (
        <Alert variant="destructive">
          <AlertDescription>{error}</AlertDescription>
        </Alert>
      )}

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <MessageSquare className="h-6 w-6 text-primary" />
            Your First AI Conversation
            {queryCount > 0 && (
              <Badge variant="secondary" className="ml-2">
                {queryCount} {queryCount === 1 ? 'query' : 'queries'} completed
              </Badge>
            )}
          </CardTitle>
          <CardDescription>
            Experience the power of natural language queries. Ask questions about your data 
            and get instant, intelligent responses with visualizations and insights.
          </CardDescription>
        </CardHeader>

        <CardContent className="space-y-6">
          {/* Connected Bases Info */}
          <Alert>
            <Database className="h-4 w-4" />
            <AlertDescription>
              <strong>Ready to analyze:</strong> You have {selectedBases.length} connected bases 
              with comprehensive table structures loaded and ready for AI analysis.
            </AlertDescription>
          </Alert>

          {/* Chat Interface */}
          <div className="border rounded-lg bg-white">
            <div className="p-4 border-b bg-gray-50">
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-2">
                  <div className="w-3 h-3 rounded-full bg-green-500"></div>
                  <span className="font-medium">PyAirtable AI Assistant</span>
                </div>
                <div className="flex items-center gap-2 text-sm text-muted-foreground">
                  <Clock className="h-3 w-3" />
                  Real-time analysis
                </div>
              </div>
            </div>

            {/* Messages */}
            <div className="max-h-96 overflow-y-auto p-4">
              {messages.map(renderMessage)}
              
              {isProcessing && (
                <div className="flex justify-start mb-4">
                  <div className="bg-gray-100 rounded-2xl px-4 py-3 max-w-[80%]">
                    <div className="flex items-center gap-2 mb-2">
                      <Brain className="h-4 w-4 text-primary" />
                      <span className="text-sm font-medium">PyAirtable AI</span>
                    </div>
                    <div className="flex items-center gap-2">
                      <div className="flex space-x-1">
                        <div className="w-2 h-2 bg-primary rounded-full animate-bounce [animation-delay:-0.3s]"></div>
                        <div className="w-2 h-2 bg-primary rounded-full animate-bounce [animation-delay:-0.15s]"></div>
                        <div className="w-2 h-2 bg-primary rounded-full animate-bounce"></div>
                      </div>
                      <span className="text-sm text-muted-foreground">
                        Analyzing your data...
                      </span>
                    </div>
                  </div>
                </div>
              )}
              <div ref={chatEndRef} />
            </div>

            {/* Input */}
            <div className="p-4 border-t">
              <div className="flex gap-2">
                <Input
                  placeholder="Ask me anything about your data..."
                  value={currentQuery}
                  onChange={(e) => setCurrentQuery(e.target.value)}
                  onKeyPress={(e) => e.key === 'Enter' && handleSendQuery()}
                  disabled={isProcessing}
                />
                <Button 
                  onClick={() => handleSendQuery()} 
                  disabled={isProcessing || !currentQuery.trim()}
                >
                  <Send className="h-4 w-4" />
                </Button>
              </div>
            </div>
          </div>

          {/* Query Suggestions */}
          <div>
            <div className="flex items-center justify-between mb-4">
              <h3 className="font-semibold">Try These Sample Queries</h3>
              <div className="flex gap-2">
                <Button
                  variant="outline"
                  size="sm"
                  onClick={() => setShowAdvanced(!showAdvanced)}
                >
                  {showAdvanced ? 'Hide Advanced' : 'Show Advanced'}
                </Button>
                <Button
                  variant="outline"
                  size="sm"
                  onClick={() => setShowInsights(!showInsights)}
                >
                  <Eye className="h-3 w-3 mr-1" />
                  {showInsights ? 'Hide' : 'Show'} Insights
                </Button>
              </div>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              {filteredSuggestions.map((suggestion) => (
                <motion.div
                  key={suggestion.id}
                  whileHover={{ scale: 1.02 }}
                  whileTap={{ scale: 0.98 }}
                  className={`p-4 border rounded-lg cursor-pointer transition-all ${
                    selectedSuggestion?.id === suggestion.id
                      ? 'border-primary bg-primary/5'
                      : 'hover:border-primary/50 hover:bg-gray-50'
                  }`}
                  onClick={() => handleSuggestionClick(suggestion)}
                >
                  <div className="flex items-start gap-3">
                    <div className={`p-2 rounded-lg ${
                      suggestion.category === 'basic' ? 'bg-green-100 text-green-600' :
                      suggestion.category === 'analytical' ? 'bg-blue-100 text-blue-600' :
                      suggestion.category === 'exploratory' ? 'bg-purple-100 text-purple-600' :
                      'bg-orange-100 text-orange-600'
                    }`}>
                      {suggestion.icon}
                    </div>
                    <div className="flex-1">
                      <div className="flex items-center gap-2 mb-1">
                        <h4 className="font-medium">{suggestion.title}</h4>
                        <div className="flex">
                          {[...Array(suggestion.complexity)].map((_, i) => (
                            <Star key={i} className="h-3 w-3 fill-yellow-400 text-yellow-400" />
                          ))}
                        </div>
                      </div>
                      <p className="text-sm text-muted-foreground mb-2">
                        {suggestion.description}
                      </p>
                      <div className="text-xs text-primary font-mono bg-primary/10 px-2 py-1 rounded">
                        "{suggestion.query}"
                      </div>
                      
                      {showInsights && (
                        <div className="mt-3 p-2 bg-gray-50 rounded text-xs">
                          <strong>Expected result:</strong> {suggestion.expectedResult}
                        </div>
                      )}
                    </div>
                  </div>
                </motion.div>
              ))}
            </div>
          </div>

          {/* Success Milestone */}
          {queryCount > 0 && (
            <div className="p-4 bg-gradient-to-r from-green-50 to-emerald-50 border border-green-200 rounded-lg">
              <div className="flex items-center gap-3 mb-2">
                <CheckCircle className="h-6 w-6 text-green-600" />
                <h3 className="font-semibold text-green-800">Milestone Achieved!</h3>
              </div>
              <p className="text-green-700 mb-3">
                🎉 Congratulations! You've successfully completed your first AI query. 
                You're now ready to explore the full power of PyAirtable.
              </p>
              <div className="flex gap-2">
                <Badge variant="outline" className="text-green-700 border-green-300">
                  +150 points earned
                </Badge>
                <Badge variant="outline" className="text-green-700 border-green-300">
                  First Query milestone unlocked
                </Badge>
              </div>
            </div>
          )}

          {/* Navigation */}
          <div className="flex gap-3">
            <Button type="button" variant="outline" onClick={onPrev}>
              <ArrowLeft className="mr-2 h-4 w-4" />
              Back to Tour
            </Button>
            
            <Button 
              onClick={() => {
                // Collect feedback data
                const feedbackData = {
                  queryCount,
                  messagesFeedback: feedback,
                  completedFirstQuery: queryCount > 0,
                  timestamp: new Date()
                }
                onFeedbackSubmit(feedbackData)
                onNext()
              }}
              className="flex-1" 
              size="lg"
              disabled={queryCount === 0}
            >
              {queryCount === 0 ? (
                <>
                  Complete at least one query to continue
                  <MessageSquare className="ml-2 h-4 w-4" />
                </>
              ) : (
                <>
                  Complete Onboarding
                  <CheckCircle className="ml-2 h-5 w-5" />
                </>
              )}
            </Button>
          </div>

          {/* Tips */}
          <div className="bg-blue-50 p-4 rounded-lg">
            <h4 className="font-medium flex items-center gap-2 mb-2">
              <Lightbulb className="h-4 w-4 text-blue-600" />
              Pro Tips for Better Results
            </h4>
            <ul className="text-sm text-blue-800 space-y-1">
              <li>• Be specific with date ranges and criteria</li>
              <li>• Ask follow-up questions to dive deeper into insights</li>
              <li>• Use field names from your Airtable bases when possible</li>
              <li>• Try asking for comparisons and trends over time</li>
              <li>• Request visualizations by saying "show me a chart of..."</li>
            </ul>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}