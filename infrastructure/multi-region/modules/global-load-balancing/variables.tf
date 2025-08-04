# Global Load Balancing Module Variables

variable "project_name" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "domain_name" {
  description = "Domain name for the application"
  type        = string
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID"
  type        = string
}

variable "certificate_arn" {
  description = "ARN of SSL certificate for CloudFront"
  type        = string
}

# CloudFront Configuration
variable "cloudfront_price_class" {
  description = "CloudFront price class"
  type        = string
  default     = "PriceClass_All"
  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.cloudfront_price_class)
    error_message = "CloudFront price class must be PriceClass_100, PriceClass_200, or PriceClass_All."
  }
}

variable "cloudfront_minimum_protocol_version" {
  description = "Minimum SSL/TLS protocol version for CloudFront"
  type        = string
  default     = "TLSv1.2_2021"
}

# US East Region Configuration
variable "us_east_alb_dns_name" {
  description = "DNS name of US East ALB"
  type        = string
}

variable "us_east_alb_zone_id" {
  description = "Zone ID of US East ALB"
  type        = string
}

variable "us_east_health_check_id" {
  description = "Health check ID for US East region"
  type        = string
}

# EU West Region Configuration
variable "eu_west_alb_dns_name" {
  description = "DNS name of EU West ALB"
  type        = string
}

variable "eu_west_alb_zone_id" {
  description = "Zone ID of EU West ALB"
  type        = string
}

variable "eu_west_health_check_id" {
  description = "Health check ID for EU West region"
  type        = string
}

# AP Southeast Region Configuration
variable "ap_southeast_alb_dns_name" {
  description = "DNS name of AP Southeast ALB"
  type        = string
}

variable "ap_southeast_alb_zone_id" {
  description = "Zone ID of AP Southeast ALB"
  type        = string
}

variable "ap_southeast_health_check_id" {
  description = "Health check ID for AP Southeast region"
  type        = string
}

# WAF Configuration
variable "enable_waf" {
  description = "Enable AWS WAF protection"
  type        = bool
  default     = true
}

variable "waf_rate_limit" {
  description = "Rate limit for WAF (requests per 5 minutes)"
  type        = number
  default     = 2000
}

# Monitoring Configuration
variable "sns_topic_arn" {
  description = "SNS topic ARN for alerts"
  type        = string
  default     = ""
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring"
  type        = bool
  default     = true
}

# Logging Configuration
variable "cloudfront_log_retention_days" {
  description = "CloudFront log retention in days"
  type        = number
  default     = 90
}

variable "enable_cloudfront_logging" {
  description = "Enable CloudFront access logging"
  type        = bool
  default     = true
}

# Geographic Routing Configuration
variable "enable_geolocation_routing" {
  description = "Enable geolocation-based routing"
  type        = bool
  default     = true
}

variable "fallback_region" {
  description = "Fallback region for geolocation routing"
  type        = string
  default     = "us-east-1"
}

# Cache Configuration
variable "static_content_cache_ttl" {
  description = "TTL for static content caching in seconds"
  type        = number
  default     = 86400
}

variable "api_cache_ttl" {
  description = "TTL for API response caching in seconds"
  type        = number
  default     = 0
}

# Security Configuration
variable "enable_security_headers" {
  description = "Enable security headers in CloudFront responses"
  type        = bool
  default     = true
}

variable "hsts_max_age" {
  description = "HSTS max age in seconds"
  type        = number
  default     = 31536000
}

# Cost Optimization
variable "enable_origin_shield" {
  description = "Enable CloudFront Origin Shield for cost optimization"
  type        = bool
  default     = true
}

variable "enable_compression" {
  description = "Enable CloudFront compression"
  type        = bool
  default     = true
}

# Advanced Configuration
variable "allowed_methods" {
  description = "Allowed HTTP methods for CloudFront"
  type        = list(string)
  default     = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
}

variable "cached_methods" {
  description = "Cached HTTP methods for CloudFront"
  type        = list(string)
  default     = ["GET", "HEAD"]
}

variable "viewer_protocol_policy" {
  description = "Viewer protocol policy for CloudFront"
  type        = string
  default     = "redirect-to-https"
  validation {
    condition     = contains(["allow-all", "https-only", "redirect-to-https"], var.viewer_protocol_policy)
    error_message = "Viewer protocol policy must be allow-all, https-only, or redirect-to-https."
  }
}

variable "custom_error_responses" {
  description = "Custom error responses for CloudFront"
  type = list(object({
    error_code         = number
    response_code      = number
    response_page_path = string
    error_caching_min_ttl = number
  }))
  default = [
    {
      error_code         = 404
      response_code      = 404
      response_page_path = "/error/404.html"
      error_caching_min_ttl = 300
    },
    {
      error_code         = 500
      response_code      = 500
      response_page_path = "/error/500.html"  
      error_caching_min_ttl = 0
    }
  ]
}