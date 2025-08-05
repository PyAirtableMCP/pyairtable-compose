"use client";

import React from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { cn, formatNumber, formatCurrency, formatBytes } from "@/lib/utils";
import { TrendingUp, TrendingDown, Minus } from "lucide-react";

interface MetricCardProps {
  title: string;
  value: number | string;
  change?: number;
  changeType?: "increase" | "decrease" | "neutral";
  format?: "number" | "currency" | "percentage" | "bytes";
  description?: string;
  icon?: React.ReactNode;
  className?: string;
  size?: "sm" | "md" | "lg";
}

export function MetricCard({
  title,
  value,
  change,
  changeType,
  format = "number",
  description,
  icon,
  className,
  size = "md",
}: MetricCardProps) {
  const formatValue = (val: number | string) => {
    if (typeof val === "string") return val;
    
    switch (format) {
      case "currency":
        return formatCurrency(val);
      case "percentage":
        return `${val}%`;
      case "bytes":
        return formatBytes(val);
      default:
        return formatNumber(val);
    }
  };

  const getChangeIcon = () => {
    switch (changeType) {
      case "increase":
        return <TrendingUp className="h-3 w-3" />;
      case "decrease":
        return <TrendingDown className="h-3 w-3" />;
      default:
        return <Minus className="h-3 w-3" />;
    }
  };

  const getChangeColor = () => {
    switch (changeType) {
      case "increase":
        return "text-green-600 bg-green-50";
      case "decrease":
        return "text-red-600 bg-red-50";
      default:
        return "text-gray-600 bg-gray-50";
    }
  };

  const cardSizes = {
    sm: "p-4",
    md: "p-6",
    lg: "p-8",
  };

  const titleSizes = {
    sm: "text-sm",
    md: "text-base",
    lg: "text-lg",
  };

  const valueSizes = {
    sm: "text-xl",
    md: "text-2xl",
    lg: "text-3xl",
  };

  return (
    <Card className={cn("relative overflow-hidden", className)}>
      <CardHeader className={cn("flex flex-row items-center justify-between space-y-0", cardSizes[size])}>
        <CardTitle className={cn("font-medium text-muted-foreground", titleSizes[size])}>
          {title}
        </CardTitle>
        {icon && (
          <div className="text-muted-foreground">
            {icon}
          </div>
        )}
      </CardHeader>
      <CardContent className={cn("pb-2", cardSizes[size], "pt-0")}>
        <div className="space-y-2">
          <div className={cn("font-bold tracking-tight", valueSizes[size])}>
            {formatValue(value)}
          </div>
          
          <div className="flex items-center justify-between">
            {change !== undefined && (
              <Badge
                variant="secondary"
                className={cn(
                  "flex items-center space-x-1 text-xs px-2 py-1",
                  getChangeColor()
                )}
              >
                {getChangeIcon()}
                <span>{Math.abs(change)}%</span>
              </Badge>
            )}
            
            {description && (
              <p className="text-xs text-muted-foreground">
                {description}
              </p>
            )}
          </div>
        </div>
      </CardContent>
    </Card>
  );
}