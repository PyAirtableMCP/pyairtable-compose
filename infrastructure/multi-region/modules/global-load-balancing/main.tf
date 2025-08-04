# Global Load Balancing and CDN Module
# This module sets up CloudFront, Route53 with geolocation routing, and WAF

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# CloudFront Distribution for Global CDN
resource "aws_cloudfront_origin_access_control" "main" {
  name                              = "${var.project_name}-${var.environment}-oac"
  description                       = "Origin Access Control for ${var.project_name}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# S3 bucket for static content
resource "aws_s3_bucket" "static_content" {
  bucket = "${var.project_name}-${var.environment}-static-content-${random_string.bucket_suffix.result}"

  tags = {
    Name = "${var.project_name}-${var.environment}-static-content"
  }
}

resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "aws_s3_bucket_versioning" "static_content" {
  bucket = aws_s3_bucket.static_content.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "static_content" {
  bucket = aws_s3_bucket.static_content.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "static_content" {
  bucket = aws_s3_bucket.static_content.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "main" {
  # Origin for US East region
  origin {
    domain_name              = var.us_east_alb_dns_name
    origin_id                = "us-east-alb"
    connection_attempts      = 3
    connection_timeout       = 10

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    origin_shield {
      enabled              = true
      origin_shield_region = "us-east-1"
    }
  }

  # Origin for EU West region
  origin {
    domain_name              = var.eu_west_alb_dns_name
    origin_id                = "eu-west-alb"
    connection_attempts      = 3
    connection_timeout       = 10

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    origin_shield {
      enabled              = true
      origin_shield_region = "eu-west-1"
    }
  }

  # Origin for AP Southeast region
  origin {
    domain_name              = var.ap_southeast_alb_dns_name
    origin_id                = "ap-southeast-alb"
    connection_attempts      = 3
    connection_timeout       = 10

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    origin_shield {
      enabled              = true
      origin_shield_region = "ap-southeast-1"
    }
  }

  # S3 origin for static content
  origin {
    domain_name              = aws_s3_bucket.static_content.bucket_regional_domain_name
    origin_id                = "s3-static-content"
    origin_access_control_id = aws_cloudfront_origin_access_control.main.id
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "PyAirtable Global CDN Distribution"
  default_root_object = "index.html"

  aliases = [var.domain_name, "www.${var.domain_name}"]

  # Default cache behavior (API requests)
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "us-east-alb"

    forwarded_values {
      query_string = true
      headers      = ["Authorization", "CloudFront-Viewer-Country", "CloudFront-Is-Mobile-Viewer"]

      cookies {
        forward = "all"
      }
    }

    viewer_protocol_policy     = "redirect-to-https"
    min_ttl                    = 0
    default_ttl                = 0
    max_ttl                    = 86400
    compress                   = true
    
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security_headers.id
  }

  # Cache behavior for static assets
  ordered_cache_behavior {
    path_pattern     = "/static/*"
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "s3-static-content"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl                = 86400
    default_ttl            = 86400
    max_ttl                = 31536000
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }

  # Cache behavior for API health checks (no caching)
  ordered_cache_behavior {
    path_pattern     = "/health"
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "us-east-alb"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }

  price_class = var.cloudfront_price_class

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn            = var.certificate_arn
    ssl_support_method             = "sni-only"
    minimum_protocol_version       = var.cloudfront_minimum_protocol_version
    cloudfront_default_certificate = false
  }

  web_acl_id = aws_wafv2_web_acl.main.arn

  logging_config {
    include_cookies = false
    bucket          = aws_s3_bucket.cloudfront_logs.bucket_domain_name
    prefix          = "cloudfront-logs/"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-cloudfront"
  }
}

# CloudFront Response Headers Policy for Security
resource "aws_cloudfront_response_headers_policy" "security_headers" {
  name = "${var.project_name}-${var.environment}-security-headers"

  security_headers_config {
    strict_transport_security {
      access_control_max_age_sec = 31536000
      include_subdomains         = true
      override                   = true
    }

    content_type_options {
      override = true
    }

    frame_options {
      frame_option = "DENY"
      override     = true
    }

    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }
  }

  custom_headers_config {
    items {
      header   = "X-Permitted-Cross-Domain-Policies"
      value    = "none"
      override = true
    }
    items {
      header   = "Permissions-Policy"
      value    = "geolocation=(), microphone=(), camera=()"
      override = true
    }
  }
}

# S3 bucket for CloudFront logs
resource "aws_s3_bucket" "cloudfront_logs" {
  bucket = "${var.project_name}-${var.environment}-cloudfront-logs-${random_string.bucket_suffix.result}"

  tags = {
    Name = "${var.project_name}-${var.environment}-cloudfront-logs"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudfront_logs" {
  bucket = aws_s3_bucket.cloudfront_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "cloudfront_logs" {
  bucket = aws_s3_bucket.cloudfront_logs.id

  rule {
    id     = "log_lifecycle"
    status = "Enabled"

    expiration {
      days = 90
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

# WAF Web ACL for DDoS protection and security
resource "aws_wafv2_web_acl" "main" {
  name  = "${var.project_name}-${var.environment}-waf"
  scope = "CLOUDFRONT"

  default_action {
    allow {}
  }

  # AWS Managed Rule - Core Rule Set
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "CommonRuleSetMetric"
      sampled_requests_enabled   = true
    }
  }

  # AWS Managed Rule - Known Bad Inputs
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "KnownBadInputsRuleSetMetric"
      sampled_requests_enabled   = true
    }
  }

  # Rate limiting rule
  rule {
    name     = "RateLimitRule"
    priority = 3

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimitRuleMetric"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}WAFMetric"
    sampled_requests_enabled   = true
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-waf"
  }
}

# Route53 DNS with Geolocation Routing
resource "aws_route53_record" "main" {
  zone_id = var.route53_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "www" {
  zone_id = var.route53_zone_id
  name    = "www.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false
  }
}

# Geolocation-based routing for API endpoints
resource "aws_route53_record" "api_us" {
  zone_id = var.route53_zone_id
  name    = "api.${var.domain_name}"
  type    = "A"

  set_identifier = "us-east"
  
  geolocation_routing_policy {
    continent = "NA"
  }

  alias {
    name                   = var.us_east_alb_dns_name
    zone_id                = var.us_east_alb_zone_id
    evaluate_target_health = true
  }

  health_check_id = var.us_east_health_check_id
}

resource "aws_route53_record" "api_eu" {
  zone_id = var.route53_zone_id
  name    = "api.${var.domain_name}"
  type    = "A"

  set_identifier = "eu-west"
  
  geolocation_routing_policy {
    continent = "EU"
  }

  alias {
    name                   = var.eu_west_alb_dns_name
    zone_id                = var.eu_west_alb_zone_id
    evaluate_target_health = true
  }

  health_check_id = var.eu_west_health_check_id
}

resource "aws_route53_record" "api_ap" {
  zone_id = var.route53_zone_id
  name    = "api.${var.domain_name}"
  type    = "A"

  set_identifier = "ap-southeast"
  
  geolocation_routing_policy {
    continent = "AS"
  }

  alias {
    name                   = var.ap_southeast_alb_dns_name
    zone_id                = var.ap_southeast_alb_zone_id
    evaluate_target_health = true
  }

  health_check_id = var.ap_southeast_health_check_id
}

# Default routing (fallback to US East)
resource "aws_route53_record" "api_default" {
  zone_id = var.route53_zone_id
  name    = "api.${var.domain_name}"
  type    = "A"

  set_identifier = "default"
  
  geolocation_routing_policy {
    country = "*"
  }

  alias {
    name                   = var.us_east_alb_dns_name
    zone_id                = var.us_east_alb_zone_id
    evaluate_target_health = true
  }

  health_check_id = var.us_east_health_check_id
}

# CloudWatch Alarms for monitoring
resource "aws_cloudwatch_metric_alarm" "cloudfront_4xx_errors" {
  alarm_name          = "${var.project_name}-${var.environment}-cloudfront-4xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "4xxErrorRate"
  namespace           = "AWS/CloudFront"
  period              = "300"
  statistic           = "Sum"
  threshold           = "50"
  alarm_description   = "This metric monitors CloudFront 4xx error rate"
  alarm_actions       = var.sns_topic_arn != "" ? [var.sns_topic_arn] : []

  dimensions = {
    DistributionId = aws_cloudfront_distribution.main.id
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-cloudfront-4xx-alarm"
  }
}

resource "aws_cloudfront_metric_alarm" "cloudfront_5xx_errors" {
  alarm_name          = "${var.project_name}-${var.environment}-cloudfront-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "5xxErrorRate"
  namespace           = "AWS/CloudFront"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "This metric monitors CloudFront 5xx error rate"
  alarm_actions       = var.sns_topic_arn != "" ? [var.sns_topic_arn] : []

  dimensions = {
    DistributionId = aws_cloudfront_distribution.main.id
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-cloudfront-5xx-alarm"
  }
}

resource "aws_cloudwatch_metric_alarm" "waf_blocked_requests" {
  alarm_name          = "${var.project_name}-${var.environment}-waf-blocked-requests"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "BlockedRequests"
  namespace           = "AWS/WAFV2"
  period              = "300"
  statistic           = "Sum"
  threshold           = "100"
  alarm_description   = "This metric monitors WAF blocked requests"
  alarm_actions       = var.sns_topic_arn != "" ? [var.sns_topic_arn] : []

  dimensions = {
    WebACL = aws_wafv2_web_acl.main.name
    Rule   = "ALL"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-waf-blocked-alarm"
  }
}

# CloudFront Origin Request Policy for proper header forwarding
resource "aws_cloudfront_origin_request_policy" "api_requests" {
  name    = "${var.project_name}-${var.environment}-api-requests"
  comment = "Policy for API requests with proper header forwarding"
  
  cookies_config {
    cookie_behavior = "all"
  }
  
  headers_config {
    header_behavior = "whitelist"
    headers {
      items = [
        "Authorization",
        "CloudFront-Viewer-Country",
        "CloudFront-Is-Mobile-Viewer",
        "User-Agent",
        "Referer",
        "Origin"
      ]
    }
  }
  
  query_strings_config {
    query_string_behavior = "all"
  }
}

# CloudFront Cache Policy for API responses
resource "aws_cloudfront_cache_policy" "api_cache" {
  name    = "${var.project_name}-${var.environment}-api-cache"
  comment = "Cache policy for API responses"
  
  default_ttl = 0
  max_ttl     = 86400
  min_ttl     = 0
  
  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config {
      cookie_behavior = "all"
    }
    
    headers_config {
      header_behavior = "whitelist"
      headers {
        items = ["Authorization"]
      }
    }
    
    query_strings_config {
      query_string_behavior = "all"
    }
    
    enable_accept_encoding_brotli = true
    enable_accept_encoding_gzip   = true
  }
}