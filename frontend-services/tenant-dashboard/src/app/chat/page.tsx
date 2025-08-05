"use client"

import React from "react"
import { ChatInterface } from "@/components/chat/chat-interface"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Bot, Database, Zap, BarChart3, MessageSquare, Lightbulb } from "lucide-react"

export default function ChatPage() {
  return (
    <div className="min-h-screen bg-gradient-to-br from-blue-50 via-white to-purple-50">
      <div className="container mx-auto px-4 py-8">
        {/* Header Section */}
        <div className="text-center mb-8">
          <div className="flex items-center justify-center mb-4">
            <div className="bg-primary/10 p-3 rounded-full mr-3">
              <Bot className="h-8 w-8 text-primary" />
            </div>
            <h1 className="text-4xl font-bold bg-gradient-to-r from-blue-600 to-purple-600 bg-clip-text text-transparent">
              PyAirtable AI Assistant
            </h1>
          </div>
          <p className="text-xl text-muted-foreground max-w-2xl mx-auto mb-6">
            Ask questions about your Airtable data, create formulas, and get AI-powered insights. 
            Your intelligent companion for data analysis and automation.
          </p>
          
          {/* Feature Badges */}
          <div className="flex flex-wrap items-center justify-center gap-2 mb-8">
            <Badge variant="secondary" className="flex items-center gap-1">
              <Database className="h-3 w-3" />
              Data Analysis
            </Badge>
            <Badge variant="secondary" className="flex items-center gap-1">
              <Zap className="h-3 w-3" />
              Formula Creation
            </Badge>
            <Badge variant="secondary" className="flex items-center gap-1">
              <BarChart3 className="h-3 w-3" />
              Smart Insights
            </Badge>
            <Badge variant="secondary" className="flex items-center gap-1">
              <MessageSquare className="h-3 w-3" />
              Natural Language
            </Badge>
          </div>
        </div>

        {/* Main Content - Split Layout */}
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-8 max-w-7xl mx-auto">
          
          {/* Chat Interface - Main Focus */}
          <div className="lg:col-span-2">
            <ChatInterface 
              className="h-[600px]"
              placeholder="Try asking: 'Analyze my Facebook posts table' or 'Create a formula to calculate engagement rate'"
              showConnectionStatus={true}
              autoScroll={true}
            />
          </div>

          {/* Example Prompts & Tips Sidebar */}
          <div className="space-y-6">
            
            {/* Quick Start Examples */}
            <Card>
              <CardHeader>
                <CardTitle className="flex items-center gap-2 text-lg">
                  <Lightbulb className="h-5 w-5 text-amber-500" />
                  Try These Examples
                </CardTitle>
              </CardHeader>
              <CardContent className="space-y-3">
                <div className="space-y-2">
                  <h4 className="font-medium text-sm">Data Analysis</h4>
                  <div className="space-y-1 text-sm text-muted-foreground">
                    <p>"Show me the top 10 posts by engagement"</p>
                    <p>"What's the average response time this month?"</p>
                    <p>"Find all records created last week"</p>
                  </div>
                </div>
                
                <div className="space-y-2">
                  <h4 className="font-medium text-sm">Formula Creation</h4>
                  <div className="space-y-1 text-sm text-muted-foreground">
                    <p>"Create a formula to calculate ROI"</p>
                    <p>"Generate a status field based on conditions"</p>
                    <p>"Make a rollup formula for totals"</p>
                  </div>
                </div>

                <div className="space-y-2">
                  <h4 className="font-medium text-sm">Automation Ideas</h4>
                  <div className="space-y-1 text-sm text-muted-foreground">
                    <p>"Set up alerts for high-priority items"</p>
                    <p>"Create a workflow for new leads"</p>
                    <p>"Automate status updates"</p>
                  </div>
                </div>
              </CardContent>
            </Card>

            {/* Tips Card */}
            <Card>
              <CardHeader>
                <CardTitle className="text-lg">💡 Pro Tips</CardTitle>
              </CardHeader>
              <CardContent className="space-y-3 text-sm text-muted-foreground">
                <p>• Be specific about which table or view you're referring to</p>
                <p>• Ask follow-up questions to refine your analysis</p>
                <p>• Request explanations of formulas and automations</p>
                <p>• Use natural language - no need for technical jargon</p>
                <p>• The AI can access your actual Airtable data securely</p>
              </CardContent>
            </Card>

            {/* Status Card */}
            <Card>
              <CardHeader>
                <CardTitle className="text-lg">🚀 System Status</CardTitle>
              </CardHeader>
              <CardContent className="space-y-3">
                <div className="flex items-center justify-between text-sm">
                  <span>API Gateway</span>
                  <Badge variant="default" className="bg-green-100 text-green-800">Online</Badge>
                </div>
                <div className="flex items-center justify-between text-sm">
                  <span>AI Orchestrator</span>
                  <Badge variant="default" className="bg-green-100 text-green-800">Ready</Badge>
                </div>
                <div className="flex items-center justify-between text-sm">
                  <span>Airtable Gateway</span>
                  <Badge variant="default" className="bg-green-100 text-green-800">Connected</Badge>
                </div>
                <div className="flex items-center justify-between text-sm">
                  <span>Real-time Features</span>
                  <Badge variant="secondary">Enabled</Badge>
                </div>
              </CardContent>
            </Card>
          </div>
        </div>
      </div>
    </div>
  )
}