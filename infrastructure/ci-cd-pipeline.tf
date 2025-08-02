# CI/CD Pipeline Infrastructure for PyAirtable
# Cost-optimized CodeBuild, CodePipeline with ECR and automated deployments

# S3 Bucket for CodePipeline artifacts
resource "aws_s3_bucket" "codepipeline_artifacts" {
  bucket = "${var.project_name}-${var.environment}-codepipeline-artifacts-${random_id.bucket_suffix.hex}"

  tags = {
    Name        = "${var.project_name}-codepipeline-artifacts"
    Environment = var.environment
  }
}

resource "aws_s3_bucket_versioning" "codepipeline_artifacts" {
  bucket = aws_s3_bucket.codepipeline_artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_encryption" "codepipeline_artifacts" {
  bucket = aws_s3_bucket.codepipeline_artifacts.id

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "codepipeline_artifacts" {
  bucket = aws_s3_bucket.codepipeline_artifacts.id

  rule {
    id     = "cleanup_artifacts"
    status = "Enabled"

    expiration {
      days = 30
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}

# IAM Role for CodeBuild
resource "aws_iam_role" "codebuild" {
  name = "${var.project_name}-${var.environment}-codebuild-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "codebuild.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-codebuild-role"
  }
}

resource "aws_iam_policy" "codebuild" {
  name        = "${var.project_name}-${var.environment}-codebuild-policy"
  description = "Policy for CodeBuild projects"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject"
        ]
        Resource = [
          "${aws_s3_bucket.codepipeline_artifacts.arn}",
          "${aws_s3_bucket.codepipeline_artifacts.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:GetAuthorizationToken",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:DescribeNodegroup"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameters",
          "ssm:GetParameter"
        ]
        Resource = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/${var.project_name}/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "codebuild" {
  policy_arn = aws_iam_policy.codebuild.arn
  role       = aws_iam_role.codebuild.name
}

# CodeBuild Projects for each service type
resource "aws_codebuild_project" "go_services" {
  name          = "${var.project_name}-${var.environment}-go-services"
  description   = "Build Go microservices"
  service_role  = aws_iam_role.codebuild.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"  # Cost-optimized
    image                      = "aws/codebuild/amazonlinux2-x86_64-standard:4.0"
    type                       = "LINUX_CONTAINER"
    privileged_mode            = true

    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = var.aws_region
    }

    environment_variable {
      name  = "AWS_ACCOUNT_ID"
      value = data.aws_caller_identity.current.account_id
    }

    environment_variable {
      name  = "IMAGE_REPO_NAME"
      value = "pyairtable"
    }

    environment_variable {
      name  = "EKS_CLUSTER_NAME"
      value = aws_eks_cluster.pyairtable.name
    }
  }

  source {
    type = "CODEPIPELINE"
    buildspec = "buildspec-go.yml"
  }

  tags = {
    Name        = "${var.project_name}-go-services-build"
    Environment = var.environment
  }
}

resource "aws_codebuild_project" "python_services" {
  name          = "${var.project_name}-${var.environment}-python-services"
  description   = "Build Python microservices"
  service_role  = aws_iam_role.codebuild.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_MEDIUM"  # More resources for Python builds
    image                      = "aws/codebuild/amazonlinux2-x86_64-standard:4.0"
    type                       = "LINUX_CONTAINER"
    privileged_mode            = true

    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = var.aws_region
    }

    environment_variable {
      name  = "AWS_ACCOUNT_ID"
      value = data.aws_caller_identity.current.account_id
    }

    environment_variable {
      name  = "IMAGE_REPO_NAME"
      value = "pyairtable"
    }

    environment_variable {
      name  = "EKS_CLUSTER_NAME"
      value = aws_eks_cluster.pyairtable.name
    }
  }

  source {
    type = "CODEPIPELINE"
    buildspec = "buildspec-python.yml"
  }

  tags = {
    Name        = "${var.project_name}-python-services-build"
    Environment = var.environment
  }
}

# CodeBuild for Lambda functions
resource "aws_codebuild_project" "lambda_functions" {
  name          = "${var.project_name}-${var.environment}-lambda-functions"
  description   = "Build and deploy Lambda functions"
  service_role  = aws_iam_role.codebuild.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                      = "aws/codebuild/amazonlinux2-x86_64-standard:4.0"
    type                       = "LINUX_CONTAINER"
    privileged_mode            = false

    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = var.aws_region
    }
  }

  source {
    type = "CODEPIPELINE"
    buildspec = "buildspec-lambda.yml"
  }

  tags = {
    Name        = "${var.project_name}-lambda-build"
    Environment = var.environment
  }
}

# IAM Role for CodePipeline
resource "aws_iam_role" "codepipeline" {
  name = "${var.project_name}-${var.environment}-codepipeline-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "codepipeline.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-codepipeline-role"
  }
}

resource "aws_iam_policy" "codepipeline" {
  name        = "${var.project_name}-${var.environment}-codepipeline-policy"
  description = "Policy for CodePipeline"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetBucketVersioning",
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject"
        ]
        Resource = [
          "${aws_s3_bucket.codepipeline_artifacts.arn}",
          "${aws_s3_bucket.codepipeline_artifacts.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "codebuild:BatchGetBuilds",
          "codebuild:StartBuild"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "codepipeline" {
  policy_arn = aws_iam_policy.codepipeline.arn
  role       = aws_iam_role.codepipeline.name
}

# CodePipeline for microservices deployment
resource "aws_codepipeline" "microservices" {
  name     = "${var.project_name}-${var.environment}-microservices-pipeline"
  role_arn = aws_iam_role.codepipeline.arn

  artifact_store {
    location = aws_s3_bucket.codepipeline_artifacts.bucket
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "ThirdParty"
      provider         = "GitHub"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        Owner      = var.github_owner
        Repo       = var.github_repo
        Branch     = var.github_branch
        OAuthToken = var.github_token
      }
    }
  }

  stage {
    name = "Build"

    action {
      name             = "BuildGoServices"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["source_output"]
      output_artifacts = ["go_build_output"]
      version          = "1"

      configuration = {
        ProjectName = aws_codebuild_project.go_services.name
      }

      run_order = 1
    }

    action {
      name             = "BuildPythonServices"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["source_output"]
      output_artifacts = ["python_build_output"]
      version          = "1"

      configuration = {
        ProjectName = aws_codebuild_project.python_services.name
      }

      run_order = 1
    }

    action {
      name             = "BuildLambdaFunctions"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["source_output"]
      output_artifacts = ["lambda_build_output"]
      version          = "1"

      configuration = {
        ProjectName = aws_codebuild_project.lambda_functions.name
      }

      run_order = 1
    }
  }

  stage {
    name = "Deploy"

    action {
      name            = "DeployToEKS"
      category        = "Invoke"
      owner           = "AWS"
      provider        = "Lambda"
      input_artifacts = ["go_build_output", "python_build_output"]
      version         = "1"

      configuration = {
        FunctionName = aws_lambda_function.deployment_orchestrator.function_name
      }

      run_order = 1
    }
  }

  tags = {
    Name        = "${var.project_name}-microservices-pipeline"
    Environment = var.environment
  }
}

# Lambda function for deployment orchestration
resource "aws_lambda_function" "deployment_orchestrator" {
  filename         = "../lambda/deployment-orchestrator.zip"
  function_name    = "${var.project_name}-${var.environment}-deployment-orchestrator"
  role            = aws_iam_role.deployment_lambda.arn
  handler         = "handler.lambda_handler"
  runtime         = "python3.11"
  timeout         = 900  # 15 minutes for deployment
  memory_size     = 512

  environment {
    variables = {
      EKS_CLUSTER_NAME = aws_eks_cluster.pyairtable.name
      AWS_REGION       = var.aws_region
      HELM_RELEASE     = "pyairtable-stack"
      HELM_NAMESPACE   = "pyairtable"
    }
  }

  tags = {
    Name        = "${var.project_name}-deployment-orchestrator"
    Environment = var.environment
  }

  depends_on = [aws_cloudwatch_log_group.deployment_orchestrator]
}

resource "aws_cloudwatch_log_group" "deployment_orchestrator" {
  name              = "/aws/lambda/${var.project_name}-${var.environment}-deployment-orchestrator"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.project_name}-deployment-orchestrator-logs"
  }
}

# IAM role for deployment Lambda
resource "aws_iam_role" "deployment_lambda" {
  name = "${var.project_name}-${var.environment}-deployment-lambda-role"

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
    Name = "${var.project_name}-deployment-lambda-role"
  }
}

resource "aws_iam_policy" "deployment_lambda" {
  name        = "${var.project_name}-${var.environment}-deployment-lambda-policy"
  description = "Policy for deployment Lambda function"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters",
          "eks:DescribeNodegroup",
          "eks:ListNodegroups"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = [
          "${aws_s3_bucket.codepipeline_artifacts.arn}/*",
          "${aws_s3_bucket.file_storage.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "codepipeline:PutJobSuccessResult",
          "codepipeline:PutJobFailureResult"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "deployment_lambda" {
  policy_arn = aws_iam_policy.deployment_lambda.arn
  role       = aws_iam_role.deployment_lambda.name
}

resource "aws_iam_role_policy_attachment" "deployment_lambda_basic" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.deployment_lambda.name
}

# CloudWatch dashboard for CI/CD monitoring
resource "aws_cloudwatch_dashboard" "cicd" {
  dashboard_name = "${var.project_name}-${var.environment}-cicd-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/CodeBuild", "Builds", "ProjectName", aws_codebuild_project.go_services.name],
            ["AWS/CodeBuild", "Builds", "ProjectName", aws_codebuild_project.python_services.name],
            ["AWS/CodeBuild", "Builds", "ProjectName", aws_codebuild_project.lambda_functions.name]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "CodeBuild Projects"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/CodePipeline", "PipelineExecutionSuccess", "PipelineName", aws_codepipeline.microservices.name],
            ["AWS/CodePipeline", "PipelineExecutionFailure", "PipelineName", aws_codepipeline.microservices.name]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "Pipeline Executions"
          period  = 300
        }
      }
    ]
  })
}

# Outputs
output "codepipeline_name" {
  description = "Name of the CodePipeline"
  value       = aws_codepipeline.microservices.name
}

output "ecr_repositories" {
  description = "ECR repository URLs"
  value = {
    for service in var.services : service => aws_ecr_repository.services[service].repository_url
  }
}

output "build_projects" {
  description = "CodeBuild project names"
  value = {
    go_services     = aws_codebuild_project.go_services.name
    python_services = aws_codebuild_project.python_services.name
    lambda_functions = aws_codebuild_project.lambda_functions.name
  }
}