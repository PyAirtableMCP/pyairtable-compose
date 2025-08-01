# Terraform State Backend Bootstrap
# This creates the S3 bucket and DynamoDB table for Terraform state management
# Run this ONCE before using the main infrastructure code

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = "bootstrap"
      ManagedBy   = "terraform"
      Purpose     = "state-management"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# KMS Key for state encryption
resource "aws_kms_key" "terraform_state" {
  description             = "KMS key for Terraform state encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow S3 Service"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-terraform-state-key"
  }
}

resource "aws_kms_alias" "terraform_state" {
  name          = "alias/${var.project_name}-terraform-state"
  target_key_id = aws_kms_key.terraform_state.key_id
}

# S3 Bucket for Terraform State
resource "aws_s3_bucket" "terraform_state" {
  bucket        = "${var.project_name}-terraform-state-${random_id.bucket_suffix.hex}"
  force_destroy = false

  tags = {
    Name        = "${var.project_name}-terraform-state"
    Description = "Terraform state bucket for ${var.project_name}"
  }
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# S3 Bucket Versioning
resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 Bucket Encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.terraform_state.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

# S3 Bucket Public Access Block
resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 Bucket Lifecycle Configuration
resource "aws_s3_bucket_lifecycle_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    id     = "terraform_state_lifecycle"
    status = "Enabled"

    # Keep current versions
    expiration {
      days = 0 # Never expire current versions
    }

    # Transition non-current versions to IA after 30 days
    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }

    # Transition non-current versions to Glacier after 90 days
    noncurrent_version_transition {
      noncurrent_days = 90
      storage_class   = "GLACIER"
    }

    # Delete non-current versions after 1 year
    noncurrent_version_expiration {
      noncurrent_days = 365
    }

    # Abort incomplete multipart uploads after 7 days
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# S3 Bucket Notification (optional - for state change monitoring)
resource "aws_s3_bucket_notification" "terraform_state" {
  count  = var.enable_state_notifications ? 1 : 0
  bucket = aws_s3_bucket.terraform_state.id

  eventbridge = true

  depends_on = [aws_s3_bucket.terraform_state]
}

# DynamoDB Table for State Locking
resource "aws_dynamodb_table" "terraform_state_lock" {
  name           = "${var.project_name}-terraform-state-lock"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.terraform_state.arn
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name        = "${var.project_name}-terraform-state-lock"
    Description = "Terraform state locking for ${var.project_name}"
  }
}

# CloudTrail for state bucket access logging (security)
resource "aws_cloudtrail" "terraform_state_trail" {
  count = var.enable_state_audit_trail ? 1 : 0

  name           = "${var.project_name}-terraform-state-trail"
  s3_bucket_name = aws_s3_bucket.audit_logs[0].bucket

  event_selector {
    read_write_type                 = "All"
    include_management_events       = false

    data_resource {
      type   = "AWS::S3::Object"
      values = ["${aws_s3_bucket.terraform_state.arn}/*"]
    }

    data_resource {
      type   = "AWS::DynamoDB::Table"
      values = [aws_dynamodb_table.terraform_state_lock.arn]
    }
  }

  depends_on = [aws_s3_bucket_policy.audit_logs]

  tags = {
    Name = "${var.project_name}-terraform-state-trail"
  }
}

# S3 Bucket for CloudTrail logs
resource "aws_s3_bucket" "audit_logs" {
  count  = var.enable_state_audit_trail ? 1 : 0
  bucket = "${var.project_name}-terraform-audit-logs-${random_id.audit_bucket_suffix[0].hex}"

  tags = {
    Name = "${var.project_name}-terraform-audit-logs"
  }
}

resource "random_id" "audit_bucket_suffix" {
  count       = var.enable_state_audit_trail ? 1 : 0
  byte_length = 4
}

resource "aws_s3_bucket_policy" "audit_logs" {
  count  = var.enable_state_audit_trail ? 1 : 0
  bucket = aws_s3_bucket.audit_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.audit_logs[0].arn
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.audit_logs[0].arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

# IAM Policy for Terraform State Access
resource "aws_iam_policy" "terraform_state_policy" {
  name        = "${var.project_name}-terraform-state-policy"
  description = "Policy for accessing Terraform state resources"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketVersioning"
        ]
        Resource = aws_s3_bucket.terraform_state.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.terraform_state.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem"
        ]
        Resource = aws_dynamodb_table.terraform_state_lock.arn
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = aws_kms_key.terraform_state.arn
      }
    ]
  })
}

# Output backend configuration file
resource "local_file" "backend_config" {
  content = templatefile("${path.module}/backend-config.tpl", {
    bucket_name    = aws_s3_bucket.terraform_state.bucket
    dynamodb_table = aws_dynamodb_table.terraform_state_lock.name
    kms_key_id     = aws_kms_key.terraform_state.arn
    region         = data.aws_region.current.name
  })
  filename = "${path.module}/../backend-config.hcl"
}

# Create workspace-specific backend configurations
resource "local_file" "workspace_backend_configs" {
  for_each = toset(var.workspaces)

  content = templatefile("${path.module}/workspace-backend-config.tpl", {
    bucket_name    = aws_s3_bucket.terraform_state.bucket
    dynamodb_table = aws_dynamodb_table.terraform_state_lock.name
    kms_key_id     = aws_kms_key.terraform_state.arn
    region         = data.aws_region.current.name
    workspace      = each.value
  })
  filename = "${path.module}/../environments/${each.value}/backend.hcl"
}

# Monitoring and Alerting for State Management
resource "aws_cloudwatch_metric_alarm" "state_bucket_size" {
  count = var.enable_state_monitoring ? 1 : 0

  alarm_name          = "${var.project_name}-terraform-state-bucket-size"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "BucketSizeBytes"
  namespace           = "AWS/S3"
  period              = "86400" # Daily
  statistic           = "Average"
  threshold           = var.state_bucket_size_alarm_threshold
  alarm_description   = "Terraform state bucket size is growing unusually large"

  dimensions = {
    BucketName  = aws_s3_bucket.terraform_state.bucket
    StorageType = "StandardStorage"
  }

  tags = {
    Name = "${var.project_name}-state-bucket-size-alarm"
  }
}

resource "aws_cloudwatch_metric_alarm" "state_lock_table_throttles" {
  count = var.enable_state_monitoring ? 1 : 0

  alarm_name          = "${var.project_name}-terraform-state-lock-throttles"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ThrottledRequests"
  namespace           = "AWS/DynamoDB"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "DynamoDB throttling detected on Terraform state lock table"

  dimensions = {
    TableName = aws_dynamodb_table.terraform_state_lock.name
  }

  tags = {
    Name = "${var.project_name}-state-lock-throttles-alarm"
  }
}