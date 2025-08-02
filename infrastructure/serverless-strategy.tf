# Serverless Strategy for Event-Driven PyAirtable Services
# Cost-optimized Lambda functions for batch processing and async tasks

# Lambda execution role
resource "aws_iam_role" "lambda_execution" {
  name = "${var.project_name}-${var.environment}-lambda-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-lambda-execution-role"
  }
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_execution.name
}

resource "aws_iam_role_policy_attachment" "lambda_vpc_access" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
  role       = aws_iam_role.lambda_execution.name
}

# Custom policy for Lambda functions
resource "aws_iam_policy" "lambda_custom" {
  name        = "${var.project_name}-${var.environment}-lambda-custom-policy"
  description = "Custom policy for Lambda functions"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "rds:DescribeDBInstances",
          "rds:DescribeDBClusters",
          "secretsmanager:GetSecretValue",
          "ssm:GetParameter",
          "ssm:GetParameters",
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "sns:Publish",
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "events:PutEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_custom" {
  policy_arn = aws_iam_policy.lambda_custom.arn
  role       = aws_iam_role.lambda_execution.name
}

# SQS Queue for async processing
resource "aws_sqs_queue" "file_processing" {
  name                       = "${var.project_name}-${var.environment}-file-processing"
  delay_seconds              = 0
  max_message_size           = 262144
  message_retention_seconds  = 1209600
  receive_wait_time_seconds  = 20
  visibility_timeout_seconds = 300

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.file_processing_dlq.arn
    maxReceiveCount     = 3
  })

  tags = {
    Name        = "${var.project_name}-file-processing-queue"
    Environment = var.environment
  }
}

resource "aws_sqs_queue" "file_processing_dlq" {
  name                      = "${var.project_name}-${var.environment}-file-processing-dlq"
  message_retention_seconds = 1209600

  tags = {
    Name        = "${var.project_name}-file-processing-dlq"
    Environment = var.environment
  }
}

# SNS Topic for notifications
resource "aws_sns_topic" "notifications" {
  name = "${var.project_name}-${var.environment}-notifications"

  tags = {
    Name        = "${var.project_name}-notifications"
    Environment = var.environment
  }
}

# S3 Bucket for file storage and processing
resource "aws_s3_bucket" "file_storage" {
  bucket = "${var.project_name}-${var.environment}-file-storage-${random_id.bucket_suffix.hex}"

  tags = {
    Name        = "${var.project_name}-file-storage"
    Environment = var.environment
  }
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket_versioning" "file_storage" {
  bucket = aws_s3_bucket.file_storage.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_encryption" "file_storage" {
  bucket = aws_s3_bucket.file_storage.id

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "file_storage" {
  bucket = aws_s3_bucket.file_storage.id

  rule {
    id     = "file_lifecycle"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

# Lambda function for file processing (Python-based)
resource "aws_lambda_function" "file_processor" {
  filename         = "../lambda/file-processor.zip"
  function_name    = "${var.project_name}-${var.environment}-file-processor"
  role            = aws_iam_role.lambda_execution.arn
  handler         = "handler.lambda_handler"
  runtime         = "python3.11"
  timeout         = 300
  memory_size     = 1024

  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      DB_HOST         = aws_rds_cluster.postgres.endpoint
      DB_NAME         = aws_rds_cluster.postgres.database_name
      S3_BUCKET       = aws_s3_bucket.file_storage.bucket
      SNS_TOPIC       = aws_sns_topic.notifications.arn
      ENVIRONMENT     = var.environment
      LOG_LEVEL       = "INFO"
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.file_processor,
  ]

  tags = {
    Name        = "${var.project_name}-file-processor"
    Environment = var.environment
  }
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "file_processor" {
  name              = "/aws/lambda/${var.project_name}-${var.environment}-file-processor"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.project_name}-file-processor-logs"
  }
}

# Lambda function for workflow automation (Go-based)
resource "aws_lambda_function" "workflow_processor" {
  filename         = "../lambda/workflow-processor.zip"
  function_name    = "${var.project_name}-${var.environment}-workflow-processor"
  role            = aws_iam_role.lambda_execution.arn
  handler         = "bootstrap"
  runtime         = "provided.al2"
  timeout         = 180
  memory_size     = 512  # Go uses less memory

  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      REDIS_ENDPOINT  = aws_elasticache_replication_group.redis.primary_endpoint_address
      DB_HOST         = aws_rds_cluster.postgres.endpoint
      DB_NAME         = aws_rds_cluster.postgres.database_name
      ENVIRONMENT     = var.environment
      LOG_LEVEL       = "INFO"
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.workflow_processor,
  ]

  tags = {
    Name        = "${var.project_name}-workflow-processor"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_log_group" "workflow_processor" {
  name              = "/aws/lambda/${var.project_name}-${var.environment}-workflow-processor"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.project_name}-workflow-processor-logs"
  }
}

# SQS event source for file processing Lambda
resource "aws_lambda_event_source_mapping" "file_processing_queue" {
  event_source_arn = aws_sqs_queue.file_processing.arn
  function_name    = aws_lambda_function.file_processor.arn
  batch_size       = 10
  maximum_batching_window_in_seconds = 30
}

# EventBridge rule for scheduled workflows
resource "aws_cloudwatch_event_rule" "workflow_schedule" {
  name        = "${var.project_name}-${var.environment}-workflow-schedule"
  description = "Trigger workflow processing"

  # Run every 5 minutes
  schedule_expression = "rate(5 minutes)"

  tags = {
    Name        = "${var.project_name}-workflow-schedule"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_event_target" "workflow_lambda" {
  rule      = aws_cloudwatch_event_rule.workflow_schedule.name
  target_id = "WorkflowProcessorTarget"
  arn       = aws_lambda_function.workflow_processor.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.workflow_processor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.workflow_schedule.arn
}

# S3 event trigger for file uploads
resource "aws_s3_bucket_notification" "file_upload" {
  bucket = aws_s3_bucket.file_storage.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.file_processor.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "uploads/"
    filter_suffix       = ""
  }

  depends_on = [aws_lambda_permission.allow_s3]
}

resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.file_processor.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.file_storage.arn
}

# Security group for Lambda functions
resource "aws_security_group" "lambda" {
  name_prefix = "${var.project_name}-${var.environment}-lambda-"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow access to RDS
  egress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Allow access to Redis
  egress {
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = {
    Name = "${var.project_name}-lambda-sg"
  }
}

# Lambda Layer for shared dependencies (Python)
resource "aws_lambda_layer_version" "python_dependencies" {
  filename   = "../lambda/layers/python-deps.zip"
  layer_name = "${var.project_name}-${var.environment}-python-deps"

  compatible_runtimes = ["python3.11"]
  
  description = "Shared Python dependencies for PyAirtable Lambda functions"

  depends_on = [
    null_resource.build_python_layer
  ]
}

# Build Python layer
resource "null_resource" "build_python_layer" {
  provisioner "local-exec" {
    command = <<EOF
mkdir -p ../lambda/layers/python
pip install -r ../pyairtable-automation-services/requirements.txt -t ../lambda/layers/python/
cd ../lambda/layers && zip -r python-deps.zip python/
EOF
  }

  triggers = {
    requirements_hash = filemd5("../pyairtable-automation-services/requirements.txt")
  }
}

# Cost optimization: Lambda provisioned concurrency for file processor (if needed)
resource "aws_lambda_provisioned_concurrency_config" "file_processor" {
  count                     = var.environment == "prod" ? 1 : 0
  function_name             = aws_lambda_function.file_processor.function_name
  provisioned_concurrency   = 2
  qualifier                 = aws_lambda_function.file_processor.version
}

# API Gateway for webhook endpoints (serverless)
resource "aws_api_gateway_rest_api" "webhooks" {
  name        = "${var.project_name}-${var.environment}-webhooks"
  description = "Serverless webhook endpoints"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "${var.project_name}-webhooks"
    Environment = var.environment
  }
}

resource "aws_api_gateway_deployment" "webhooks" {
  depends_on = [
    aws_api_gateway_method.webhook_post,
    aws_api_gateway_integration.webhook_post,
  ]

  rest_api_id = aws_api_gateway_rest_api.webhooks.id
  stage_name  = var.environment

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_resource" "webhook" {
  rest_api_id = aws_api_gateway_rest_api.webhooks.id
  parent_id   = aws_api_gateway_rest_api.webhooks.root_resource_id
  path_part   = "webhook"
}

resource "aws_api_gateway_method" "webhook_post" {
  rest_api_id   = aws_api_gateway_rest_api.webhooks.id
  resource_id   = aws_api_gateway_resource.webhook.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "webhook_post" {
  rest_api_id = aws_api_gateway_rest_api.webhooks.id
  resource_id = aws_api_gateway_method.webhook_post.resource_id
  http_method = aws_api_gateway_method.webhook_post.http_method

  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.file_processor.invoke_arn
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.file_processor.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.webhooks.execution_arn}/*/*"
}

# Outputs
output "sqs_queue_url" {
  description = "URL of the SQS queue for file processing"
  value       = aws_sqs_queue.file_processing.url
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket for file storage"
  value       = aws_s3_bucket.file_storage.bucket
}

output "webhook_api_url" {
  description = "URL of the webhook API"
  value       = "${aws_api_gateway_deployment.webhooks.invoke_url}/webhook"
}