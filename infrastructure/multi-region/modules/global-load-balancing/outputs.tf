# Global Load Balancing Module Outputs

# CloudFront Distribution Outputs
output "cloudfront_distribution_id" {
  description = "ID of the CloudFront distribution"
  value       = aws_cloudfront_distribution.main.id
}

output "cloudfront_distribution_arn" {
  description = "ARN of the CloudFront distribution"
  value       = aws_cloudfront_distribution.main.arn
}

output "cloudfront_domain_name" {
  description = "Domain name of the CloudFront distribution"
  value       = aws_cloudfront_distribution.main.domain_name
}

output "cloudfront_hosted_zone_id" {
  description = "Hosted zone ID of the CloudFront distribution"
  value       = aws_cloudfront_distribution.main.hosted_zone_id
}

output "cloudfront_status" {
  description = "Current status of the CloudFront distribution"
  value       = aws_cloudfront_distribution.main.status
}

# DNS Outputs
output "domain_name" {
  description = "Primary domain name"
  value       = var.domain_name
}

output "www_domain_name" {
  description = "WWW domain name"
  value       = "www.${var.domain_name}"
}

output "api_domain_name" {
  description = "API domain name"
  value       = "api.${var.domain_name}"
}

# WAF Outputs
output "waf_web_acl_id" {
  description = "ID of the WAF web ACL"
  value       = aws_wafv2_web_acl.main.id
}

output "waf_web_acl_arn" {
  description = "ARN of the WAF web ACL"
  value       = aws_wafv2_web_acl.main.arn
}

# S3 Outputs
output "static_content_bucket" {
  description = "S3 bucket for static content"
  value       = aws_s3_bucket.static_content.bucket
}

output "static_content_bucket_arn" {
  description = "ARN of the S3 bucket for static content"
  value       = aws_s3_bucket.static_content.arn
}

output "cloudfront_logs_bucket" {
  description = "S3 bucket for CloudFront logs"
  value       = aws_s3_bucket.cloudfront_logs.bucket
}

output "cloudfront_logs_bucket_arn" {
  description = "ARN of the S3 bucket for CloudFront logs"
  value       = aws_s3_bucket.cloudfront_logs.arn
}

# Security Policy Outputs
output "response_headers_policy_id" {
  description = "ID of the CloudFront response headers policy"
  value       = aws_cloudfront_response_headers_policy.security_headers.id
}

output "origin_request_policy_id" {
  description = "ID of the CloudFront origin request policy"
  value       = aws_cloudfront_origin_request_policy.api_requests.id
}

output "cache_policy_id" {
  description = "ID of the CloudFront cache policy"
  value       = aws_cloudfront_cache_policy.api_cache.id
}

# Route53 Record Outputs
output "route53_records" {
  description = "Route53 records created"
  value = {
    main = {
      name = aws_route53_record.main.name
      type = aws_route53_record.main.type
    }
    www = {
      name = aws_route53_record.www.name
      type = aws_route53_record.www.type
    }
    api_us = {
      name           = aws_route53_record.api_us.name
      type           = aws_route53_record.api_us.type
      set_identifier = aws_route53_record.api_us.set_identifier
    }
    api_eu = {
      name           = aws_route53_record.api_eu.name
      type           = aws_route53_record.api_eu.type  
      set_identifier = aws_route53_record.api_eu.set_identifier
    }
    api_ap = {
      name           = aws_route53_record.api_ap.name
      type           = aws_route53_record.api_ap.type
      set_identifier = aws_route53_record.api_ap.set_identifier
    }
    api_default = {
      name           = aws_route53_record.api_default.name
      type           = aws_route53_record.api_default.type
      set_identifier = aws_route53_record.api_default.set_identifier
    }
  }
}

# CloudWatch Alarm Outputs
output "cloudwatch_alarms" {
  description = "CloudWatch alarms created"
  value = {
    cloudfront_4xx_errors = {
      name = aws_cloudwatch_metric_alarm.cloudfront_4xx_errors.alarm_name
      arn  = aws_cloudwatch_metric_alarm.cloudfront_4xx_errors.arn
    }
    cloudfront_5xx_errors = {
      name = aws_cloudwatch_metric_alarm.cloudfront_5xx_errors.alarm_name
      arn  = aws_cloudwatch_metric_alarm.cloudfront_5xx_errors.arn
    }
    waf_blocked_requests = {
      name = aws_cloudwatch_metric_alarm.waf_blocked_requests.alarm_name
      arn  = aws_cloudwatch_metric_alarm.waf_blocked_requests.arn
    }
  }
}

# Performance and Cost Information
output "performance_optimizations" {
  description = "Performance optimizations enabled"
  value = {
    origin_shield_enabled = true
    compression_enabled   = true
    http2_enabled        = true
    ipv6_enabled         = aws_cloudfront_distribution.main.is_ipv6_enabled
  }
}

output "cost_optimization_features" {
  description = "Cost optimization features enabled"
  value = {
    price_class      = var.cloudfront_price_class
    origin_shield    = var.enable_origin_shield
    compression      = var.enable_compression
    log_retention    = var.cloudfront_log_retention_days
  }
}

# Security Features
output "security_features" {
  description = "Security features enabled"
  value = {
    waf_enabled           = var.enable_waf
    security_headers      = var.enable_security_headers
    https_redirect        = var.viewer_protocol_policy == "redirect-to-https"
    hsts_enabled         = var.enable_security_headers
    content_type_options = var.enable_security_headers
    frame_options        = var.enable_security_headers
  }
}

# Geographic Routing Information
output "geographic_routing" {
  description = "Geographic routing configuration"
  value = {
    enabled = var.enable_geolocation_routing
    regions = {
      north_america = "us-east-1"
      europe        = "eu-west-1"
      asia_pacific  = "ap-southeast-1"
    }
    fallback_region = var.fallback_region
  }
}

# Configuration Summary
output "configuration_summary" {
  description = "Summary of global load balancing configuration"
  value = {
    distribution_id       = aws_cloudfront_distribution.main.id
    domain_name          = var.domain_name
    origins_count        = 4  # 3 ALBs + 1 S3
    behaviors_count      = 3  # default + static + health
    waf_enabled          = var.enable_waf
    geo_routing_enabled  = var.enable_geolocation_routing
    price_class          = var.cloudfront_price_class
  }
}