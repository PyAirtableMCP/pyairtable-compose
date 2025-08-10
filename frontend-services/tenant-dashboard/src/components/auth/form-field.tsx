"use client"

import React, { useState } from 'react'
import { UseFormReturn, FieldValues, Path } from 'react-hook-form'
import { Input } from '@/components/ui/input'
import { Checkbox } from '@/components/ui/checkbox'
import { Eye, EyeOff, LucideIcon } from 'lucide-react'
import Link from 'next/link'

interface FormFieldProps<T extends FieldValues> {
  form: UseFormReturn<T>
  name: Path<T>
  label?: string
  placeholder: string
  type?: string
  icon?: LucideIcon
  disabled?: boolean
  className?: string
}

export function FormField<T extends FieldValues>({
  form,
  name,
  label,
  placeholder,
  type = "text",
  icon: Icon,
  disabled = false,
  className = "",
}: FormFieldProps<T>) {
  const [showPassword, setShowPassword] = useState(false)
  const { register, formState: { errors } } = form
  const error = errors[name]
  
  const isPasswordField = type === "password"
  const inputType = isPasswordField && showPassword ? "text" : type

  return (
    <div className={`space-y-2 ${className}`}>
      {label && (
        <label className="text-sm font-medium">
          {label}
        </label>
      )}
      <div className="relative">
        {Icon && (
          <Icon className="absolute left-3 top-3 h-4 w-4 text-muted-foreground" />
        )}
        <Input
          {...register(name)}
          type={inputType}
          placeholder={placeholder}
          className={`${Icon ? 'pl-9' : ''} ${isPasswordField ? 'pr-9' : ''}`}
          disabled={disabled}
        />
        {isPasswordField && (
          <button
            type="button"
            onClick={() => setShowPassword(!showPassword)}
            className="absolute right-3 top-3 text-muted-foreground hover:text-foreground"
          >
            {showPassword ? (
              <EyeOff className="h-4 w-4" />
            ) : (
              <Eye className="h-4 w-4" />
            )}
          </button>
        )}
      </div>
      {error && (
        <p className="text-sm text-destructive">
          {error.message as string}
        </p>
      )}
    </div>
  )
}

interface CheckboxFieldProps<T extends FieldValues> {
  form: UseFormReturn<T>
  name: Path<T>
  children: React.ReactNode
  disabled?: boolean
}

export function CheckboxField<T extends FieldValues>({
  form,
  name,
  children,
  disabled = false,
}: CheckboxFieldProps<T>) {
  const { setValue, watch, formState: { errors } } = form
  const value = watch(name)
  const error = errors[name]

  return (
    <div className="space-y-2">
      <div className="flex items-center space-x-2">
        <Checkbox
          id={name}
          checked={!!value}
          onCheckedChange={(checked) => setValue(name, !!checked as any)}
          disabled={disabled}
        />
        <label
          htmlFor={name}
          className="text-sm font-medium leading-none peer-disabled:cursor-not-allowed peer-disabled:opacity-70"
        >
          {children}
        </label>
      </div>
      {error && (
        <p className="text-sm text-destructive">
          {error.message as string}
        </p>
      )}
    </div>
  )
}

// Terms and conditions checkbox with links
interface TermsCheckboxProps<T extends FieldValues> {
  form: UseFormReturn<T>
  name: Path<T>
  disabled?: boolean
  termsHref?: string
  privacyHref?: string
}

export function TermsCheckbox<T extends FieldValues>({
  form,
  name,
  disabled = false,
  termsHref = "/terms",
  privacyHref = "/privacy",
}: TermsCheckboxProps<T>) {
  return (
    <CheckboxField form={form} name={name} disabled={disabled}>
      I agree to the{" "}
      <Link href={termsHref} className="text-primary hover:underline">
        Terms of Service
      </Link>{" "}
      and{" "}
      <Link href={privacyHref} className="text-primary hover:underline">
        Privacy Policy
      </Link>
    </CheckboxField>
  )
}

// Password strength indicator
interface PasswordStrengthProps {
  password: string
  className?: string
}

export function PasswordStrength({ password, className = "" }: PasswordStrengthProps) {
  const getPasswordStrength = (password: string) => {
    if (!password) return { score: 0, text: "", color: "" }
    
    let score = 0
    if (password.length >= 8) score++
    if (/[a-z]/.test(password)) score++
    if (/[A-Z]/.test(password)) score++
    if (/\d/.test(password)) score++
    if (/[!@#$%^&*()_+\-=\[\]{};':"\\|,.<>\/?]/.test(password)) score++
    
    if (score < 3) return { score, text: "Weak", color: "text-red-500" }
    if (score < 4) return { score, text: "Fair", color: "text-yellow-500" }
    if (score < 5) return { score, text: "Good", color: "text-blue-500" }
    return { score, text: "Strong", color: "text-green-500" }
  }

  const strength = getPasswordStrength(password)

  if (!password) return null

  return (
    <div className={`flex items-center justify-between text-xs ${className}`}>
      <span className={strength.color}>
        Password strength: {strength.text}
      </span>
      <div className="flex space-x-1">
        {[1, 2, 3, 4, 5].map((i) => (
          <div
            key={i}
            className={`h-1 w-2 rounded ${
              i <= strength.score
                ? strength.score < 3
                  ? "bg-red-500"
                  : strength.score < 4
                  ? "bg-yellow-500"
                  : strength.score < 5
                  ? "bg-blue-500"
                  : "bg-green-500"
                : "bg-muted"
            }`}
          />
        ))}
      </div>
    </div>
  )
}