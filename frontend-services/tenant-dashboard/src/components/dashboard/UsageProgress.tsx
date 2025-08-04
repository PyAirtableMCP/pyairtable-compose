"use client";

import React from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Progress } from "@/components/ui/progress";
import { Badge } from "@/components/ui/badge";
import { 
  cn, 
  formatNumber, 
  formatBytes, 
  formatCurrency, 
  formatPercentage,
  calculateUsagePercentage,
  getUsageColor 
} from "@/lib/utils";

interface UsageItem {
  name: string;
  current: number;
  limit: number;
  format?: "number" | "bytes" | "currency";
  color?: string;
  description?: string;
}

interface UsageProgressProps {
  title: string;
  items: UsageItem[];
  className?: string;
  showPercentages?: boolean;
}

export function UsageProgress({ 
  title, 
  items, 
  className, 
  showPercentages = true 
}: UsageProgressProps) {
  const formatValue = (value: number, format: string = "number") => {
    switch (format) {
      case "bytes":
        return formatBytes(value);
      case "currency":
        return formatCurrency(value);
      default:
        return formatNumber(value);
    }
  };

  const getProgressColor = (percentage: number, customColor?: string) => {
    if (customColor) return customColor;
    
    if (percentage >= 90) return "bg-red-500";
    if (percentage >= 75) return "bg-yellow-500";
    if (percentage >= 50) return "bg-blue-500";
    return "bg-green-500";
  };

  const getStatusBadge = (percentage: number) => {
    if (percentage >= 100) {
      return <Badge variant="destructive" className="text-xs">Over Limit</Badge>;
    }
    if (percentage >= 90) {
      return <Badge variant="warning" className="text-xs">Near Limit</Badge>;
    }
    if (percentage >= 75) {
      return <Badge variant="info" className="text-xs">High Usage</Badge>;
    }
    return <Badge variant="success" className="text-xs">Good</Badge>;
  };

  return (
    <Card className={cn("", className)}>
      <CardHeader>
        <CardTitle className="text-base font-medium">{title}</CardTitle>
      </CardHeader>
      <CardContent className="space-y-6">
        {items.map((item, index) => {
          const percentage = calculateUsagePercentage(item.current, item.limit);
          const isUnlimited = item.limit === -1 || item.limit === Infinity;
          
          return (
            <div key={index} className="space-y-2">
              <div className="flex items-center justify-between">
                <div className="space-y-1">
                  <div className="flex items-center space-x-2">
                    <h4 className="text-sm font-medium">{item.name}</h4>
                    {!isUnlimited && getStatusBadge(percentage)}
                  </div>
                  {item.description && (
                    <p className="text-xs text-muted-foreground">
                      {item.description}
                    </p>
                  )}
                </div>
                <div className="text-right">
                  <div className="text-sm font-medium">
                    {formatValue(item.current, item.format)}
                    {!isUnlimited && (
                      <span className="text-muted-foreground">
                        {" / "}
                        {formatValue(item.limit, item.format)}
                      </span>
                    )}
                  </div>
                  {showPercentages && !isUnlimited && (
                    <div className="text-xs text-muted-foreground">
                      {formatPercentage(item.current, item.limit)}
                    </div>
                  )}
                </div>
              </div>
              
              {!isUnlimited && (
                <div className="space-y-1">
                  <Progress
                    value={Math.min(percentage, 100)}
                    className="h-2"
                    indicatorClassName={getProgressColor(percentage, item.color)}
                  />
                  {percentage > 100 && (
                    <div className="text-xs text-red-600">
                      Exceeded limit by {formatValue(item.current - item.limit, item.format)}
                    </div>
                  )}
                </div>
              )}
              
              {isUnlimited && (
                <div className="flex items-center space-x-2">
                  <div className="flex-1 h-2 bg-secondary rounded-full">
                    <div className="h-full bg-green-500 rounded-full animate-pulse" style={{ width: "100%" }} />
                  </div>
                  <Badge variant="success" className="text-xs">
                    Unlimited
                  </Badge>
                </div>
              )}
            </div>
          );
        })}
      </CardContent>
    </Card>
  );
}