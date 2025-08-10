"use client"

import React from 'react'
import { useForm, FieldValues, Path, UseFormReturn } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { ZodType } from 'zod'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Alert, AlertDescription } from '@/components/ui/alert'
import { Loader2 } from 'lucide-react'

interface AuthFormProps<T extends FieldValues> {
  title: string
  description: string
  schema: ZodType<T>
  onSubmit: (data: T) => Promise<void>
  isLoading?: boolean
  error?: string | null
  children: (form: UseFormReturn<T>) => React.ReactNode
  footer?: React.ReactNode
  className?: string
}

export function AuthForm<T extends FieldValues>({
  title,
  description,
  schema,
  onSubmit,
  isLoading = false,
  error,
  children,
  footer,
  className = "w-full max-w-md",
}: AuthFormProps<T>) {
  const form = useForm<T>({
    resolver: zodResolver(schema),
  })

  const handleSubmit = async (data: T) => {
    try {
      await onSubmit(data)
    } catch (error) {
      // Error handling is done in parent component
      console.error('Form submission error:', error)
    }
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-blue-50 to-indigo-100 p-4">
      <Card className={className}>
        <CardHeader className="space-y-1">
          <CardTitle className="text-2xl font-bold text-center">
            {title}
          </CardTitle>
          <CardDescription className="text-center">
            {description}
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          {error && (
            <Alert variant="destructive">
              <AlertDescription>{error}</AlertDescription>
            </Alert>
          )}

          <form onSubmit={form.handleSubmit(handleSubmit)} className="space-y-4">
            {children(form)}
          </form>

          {footer}
        </CardContent>
      </Card>
    </div>
  )
}

// Reusable submit button component
interface AuthSubmitButtonProps {
  isLoading?: boolean
  children: React.ReactNode
  className?: string
  disabled?: boolean
}

export function AuthSubmitButton({
  isLoading = false,
  children,
  className = "w-full",
  disabled = false,
}: AuthSubmitButtonProps) {
  return (
    <Button
      type="submit"
      className={className}
      disabled={isLoading || disabled}
    >
      {isLoading && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
      {children}
    </Button>
  )
}