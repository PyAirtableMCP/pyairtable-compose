# Production Apache Kafka Deployment for PyAirtable
# Scalable, secure, and cost-optimized event streaming platform

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
  }
}

# ==============================================================================
# KAFKA CLUSTER CONFIGURATION
# ==============================================================================

# MSK (Managed Streaming for Apache Kafka) Cluster
resource "aws_msk_cluster" "pyairtable_kafka" {
  cluster_name           = "${var.project_name}-${var.environment}-kafka"
  kafka_version          = "3.5.1"
  number_of_broker_nodes = var.environment == "prod" ? 6 : 3

  broker_node_group_info {
    instance_type   = var.environment == "prod" ? "kafka.m5.xlarge" : "kafka.m5.large"
    ebs_volume_size = var.environment == "prod" ? 1000 : 500
    client_subnets  = aws_subnet.private[*].id
    security_groups = [aws_security_group.kafka.id]

    # Cost optimization for development
    storage_info {
      ebs_storage_info {
        volume_size = var.environment == "prod" ? 1000 : 500
        # Use gp3 for better cost/performance ratio
        provisioned_throughput {
          enabled           = true
          volume_throughput = var.environment == "prod" ? 250 : 125
        }
      }
    }
  }

  # Configuration for optimal performance
  configuration_info {
    arn      = aws_msk_configuration.kafka_config.arn
    revision = aws_msk_configuration.kafka_config.latest_revision
  }

  # Security configuration
  encryption_info {
    encryption_at_rest_kms_key_id = aws_kms_key.kafka.arn
    encryption_in_transit {
      client_broker = "TLS"
      in_cluster    = true
    }
  }

  # Authentication and authorization
  client_authentication {
    sasl {
      scram = true
      iam   = true
    }
    tls {
      certificate_authority_arns = []
    }
  }

  logging_info {
    broker_logs {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.kafka.name
      }
      firehose {
        enabled         = var.environment == "prod"
        delivery_stream = var.environment == "prod" ? aws_kinesis_firehose_delivery_stream.kafka_logs[0].name : ""
      }
      s3 {
        enabled = var.environment == "prod"
        bucket  = var.environment == "prod" ? aws_s3_bucket.kafka_logs[0].bucket : ""
        prefix  = "kafka-logs/"
      }
    }
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-kafka"
    Environment = var.environment
    Purpose     = "event-streaming"
    Component   = "messaging"
  }
}

# Kafka Configuration for optimal performance
resource "aws_msk_configuration" "kafka_config" {
  kafka_versions = ["3.5.1"]
  name           = "${var.project_name}-${var.environment}-kafka-config"

  server_properties = <<PROPERTIES
# Broker Configuration
num.network.threads=8
num.io.threads=16
socket.send.buffer.bytes=102400
socket.receive.buffer.bytes=102400
socket.request.max.bytes=104857600

# Log Configuration
num.partitions=12
default.replication.factor=3
min.insync.replicas=2
log.retention.hours=${var.environment == "prod" ? 168 : 72}
log.retention.bytes=${var.environment == "prod" ? 1073741824 : 536870912}
log.segment.bytes=1073741824
log.cleanup.policy=delete

# Performance Optimizations
compression.type=snappy
message.max.bytes=10485760
replica.fetch.max.bytes=10485760
log.flush.interval.ms=1000
log.flush.interval.messages=10000

# Replication Configuration
replica.lag.time.max.ms=30000
replica.socket.timeout.ms=30000
replica.socket.receive.buffer.bytes=65536
replica.fetch.max.bytes=1048576

# ZooKeeper Configuration
zookeeper.connection.timeout.ms=18000
zookeeper.session.timeout.ms=18000

# Auto Topic Creation (disabled for production control)
auto.create.topics.enable=false
delete.topic.enable=true

# Producer/Consumer Optimizations
batch.size=16384
linger.ms=5
buffer.memory=33554432
max.request.size=1048576

# Security Configuration
security.inter.broker.protocol=SASL_SSL
sasl.mechanism.inter.broker.protocol=AWS_MSK_IAM
PROPERTIES

  description = "Optimized Kafka configuration for PyAirtable ${var.environment}"
}

# ==============================================================================
# SECURITY CONFIGURATION
# ==============================================================================

# KMS Key for Kafka encryption
resource "aws_kms_key" "kafka" {
  description             = "KMS key for Kafka encryption"
  deletion_window_in_days = var.environment == "prod" ? 30 : 7

  tags = {
    Name = "${var.project_name}-${var.environment}-kafka-key"
  }
}

resource "aws_kms_alias" "kafka" {
  name          = "alias/${var.project_name}-${var.environment}-kafka"
  target_key_id = aws_kms_key.kafka.key_id
}

# Security Group for Kafka
resource "aws_security_group" "kafka" {
  name_prefix = "${var.project_name}-${var.environment}-kafka-"
  vpc_id      = aws_vpc.main.id

  # Kafka broker communication
  ingress {
    description = "Kafka broker communication"
    from_port   = 9092
    to_port     = 9098
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  # ZooKeeper communication
  ingress {
    description = "ZooKeeper communication"
    from_port   = 2181
    to_port     = 2188
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  # JMX monitoring
  ingress {
    description = "JMX monitoring"
    from_port   = 11001
    to_port     = 11002
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-kafka-sg"
  }
}

# IAM role for Kafka clients
resource "aws_iam_role" "kafka_client" {
  name = "${var.project_name}-${var.environment}-kafka-client-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
      }
    ]
  })
}

# IAM policy for Kafka client access
resource "aws_iam_policy" "kafka_client" {
  name        = "${var.project_name}-${var.environment}-kafka-client-policy"
  description = "IAM policy for Kafka client access"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kafka-cluster:Connect",
          "kafka-cluster:AlterCluster",
          "kafka-cluster:DescribeCluster"
        ]
        Resource = aws_msk_cluster.pyairtable_kafka.arn
      },
      {
        Effect = "Allow"
        Action = [
          "kafka-cluster:*Topic*",
          "kafka-cluster:WriteData",
          "kafka-cluster:ReadData"
        ]
        Resource = "${aws_msk_cluster.pyairtable_kafka.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "kafka-cluster:AlterGroup",
          "kafka-cluster:DescribeGroup"
        ]
        Resource = "${aws_msk_cluster.pyairtable_kafka.arn}/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "kafka_client" {
  role       = aws_iam_role.kafka_client.name
  policy_arn = aws_iam_policy.kafka_client.arn
}

# ==============================================================================
# TOPIC CONFIGURATION
# ==============================================================================

# Topic definitions for PyAirtable events
locals {
  kafka_topics = {
    # Authentication and User Events
    "pyairtable.auth.events" = {
      partitions         = 6
      replication_factor = 3
      retention_ms       = var.environment == "prod" ? 604800000 : 259200000 # 7 days prod, 3 days dev
      cleanup_policy     = "delete"
      compression_type   = "snappy"
    }

    # Airtable Integration Events
    "pyairtable.airtable.events" = {
      partitions         = 12
      replication_factor = 3
      retention_ms       = var.environment == "prod" ? 1209600000 : 604800000 # 14 days prod, 7 days dev
      cleanup_policy     = "delete"
      compression_type   = "snappy"
    }

    # File Processing Events
    "pyairtable.files.events" = {
      partitions         = 8
      replication_factor = 3
      retention_ms       = 86400000 # 1 day (files processed quickly)
      cleanup_policy     = "delete"
      compression_type   = "lz4"
    }

    # Workflow and Automation Events
    "pyairtable.workflows.events" = {
      partitions         = 10
      replication_factor = 3
      retention_ms       = var.environment == "prod" ? 2592000000 : 604800000 # 30 days prod, 7 days dev
      cleanup_policy     = "delete"
      compression_type   = "snappy"
    }

    # AI and LLM Events
    "pyairtable.ai.events" = {
      partitions         = 4
      replication_factor = 3
      retention_ms       = 604800000 # 7 days
      cleanup_policy     = "delete"
      compression_type   = "gzip"
    }

    # System and Audit Events
    "pyairtable.system.events" = {
      partitions         = 6
      replication_factor = 3
      retention_ms       = var.environment == "prod" ? 7776000000 : 2592000000 # 90 days prod, 30 days dev
      cleanup_policy     = "delete"
      compression_type   = "snappy"
    }

    # Dead Letter Queue
    "pyairtable.dlq.events" = {
      partitions         = 3
      replication_factor = 3
      retention_ms       = 2592000000 # 30 days
      cleanup_policy     = "delete"
      compression_type   = "snappy"
    }

    # SAGA Orchestration Events
    "pyairtable.saga.events" = {
      partitions         = 6
      replication_factor = 3
      retention_ms       = var.environment == "prod" ? 2592000000 : 604800000 # 30 days prod, 7 days dev
      cleanup_policy     = "delete"
      compression_type   = "snappy"
    }

    # Real-time Analytics Events
    "pyairtable.analytics.events" = {
      partitions         = 8
      replication_factor = 3
      retention_ms       = 86400000 # 1 day (processed into time-series DB)
      cleanup_policy     = "delete"
      compression_type   = "lz4"
    }

    # Command Events (CQRS)
    "pyairtable.commands" = {
      partitions         = 12
      replication_factor = 3
      retention_ms       = 604800000 # 7 days
      cleanup_policy     = "delete"
      compression_type   = "snappy"
    }
  }
}

# ==============================================================================
# MONITORING AND ALERTING
# ==============================================================================

# CloudWatch Log Group for Kafka
resource "aws_cloudwatch_log_group" "kafka" {
  name              = "/aws/msk/${var.project_name}-${var.environment}"
  retention_in_days = var.environment == "prod" ? 90 : 30

  tags = {
    Name = "${var.project_name}-${var.environment}-kafka-logs"
  }
}

# S3 bucket for Kafka logs (production only)
resource "aws_s3_bucket" "kafka_logs" {
  count  = var.environment == "prod" ? 1 : 0
  bucket = "${var.project_name}-${var.environment}-kafka-logs-${random_id.bucket_suffix.hex}"

  tags = {
    Name        = "${var.project_name}-kafka-logs"
    Environment = var.environment
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "kafka_logs" {
  count  = var.environment == "prod" ? 1 : 0
  bucket = aws_s3_bucket.kafka_logs[0].id

  rule {
    id     = "kafka_logs_lifecycle"
    status = "Enabled"

    expiration {
      days = 90
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 60
      storage_class = "GLACIER"
    }
  }
}

# Kinesis Firehose for real-time log processing (production only)
resource "aws_kinesis_firehose_delivery_stream" "kafka_logs" {
  count       = var.environment == "prod" ? 1 : 0
  name        = "${var.project_name}-${var.environment}-kafka-logs"
  destination = "s3"

  s3_configuration {
    role_arn   = aws_iam_role.firehose[0].arn
    bucket_arn = aws_s3_bucket.kafka_logs[0].arn
    prefix     = "year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/hour=!{timestamp:HH}/"

    buffer_size     = 5
    buffer_interval = 300

    compression_format = "GZIP"
  }

  tags = {
    Name = "${var.project_name}-kafka-firehose"
  }
}

# IAM role for Firehose
resource "aws_iam_role" "firehose" {
  count = var.environment == "prod" ? 1 : 0
  name  = "${var.project_name}-${var.environment}-firehose-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "firehose.amazonaws.com"
        }
      }
    ]
  })
}

# CloudWatch Alarms for Kafka monitoring
resource "aws_cloudwatch_metric_alarm" "kafka_cpu_utilization" {
  alarm_name          = "${var.project_name}-${var.environment}-kafka-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CpuIdle"
  namespace           = "AWS/Kafka"
  period              = "300"
  statistic           = "Average"
  threshold           = "20" # Alert if CPU idle is less than 20%
  alarm_description   = "This metric monitors kafka cpu utilization"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    "Cluster Name" = aws_msk_cluster.pyairtable_kafka.cluster_name
  }

  tags = {
    Name = "${var.project_name}-kafka-cpu-alarm"
  }
}

resource "aws_cloudwatch_metric_alarm" "kafka_disk_utilization" {
  alarm_name          = "${var.project_name}-${var.environment}-kafka-disk-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "KafkaDataLogsDiskUsed"
  namespace           = "AWS/Kafka"
  period              = "300"
  statistic           = "Average"
  threshold           = "80" # Alert if disk usage is above 80%
  alarm_description   = "This metric monitors kafka disk utilization"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    "Cluster Name" = aws_msk_cluster.pyairtable_kafka.cluster_name
  }

  tags = {
    Name = "${var.project_name}-kafka-disk-alarm"
  }
}

# SNS topic for alerts
resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-${var.environment}-kafka-alerts"

  tags = {
    Name = "${var.project_name}-kafka-alerts"
  }
}

# ==============================================================================
# KAFKA CONNECT CLUSTER (for data integration)
# ==============================================================================

# ECS cluster for Kafka Connect
resource "aws_ecs_cluster" "kafka_connect" {
  name = "${var.project_name}-${var.environment}-kafka-connect"

  configuration {
    execute_command_configuration {
      logging = "OVERRIDE"

      log_configuration {
        cloud_watch_encryption_enabled = true
        cloud_watch_log_group_name     = aws_cloudwatch_log_group.kafka_connect.name
      }
    }
  }

  tags = {
    Name = "${var.project_name}-kafka-connect"
  }
}

# CloudWatch Log Group for Kafka Connect
resource "aws_cloudwatch_log_group" "kafka_connect" {
  name              = "/ecs/${var.project_name}-${var.environment}-kafka-connect"
  retention_in_days = 30

  tags = {
    Name = "${var.project_name}-kafka-connect-logs"
  }
}

# ECS Task Definition for Kafka Connect
resource "aws_ecs_task_definition" "kafka_connect" {
  family                   = "${var.project_name}-${var.environment}-kafka-connect"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 1024
  memory                   = 2048
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn           = aws_iam_role.kafka_client.arn

  container_definitions = jsonencode([
    {
      name  = "kafka-connect"
      image = "confluentinc/cp-kafka-connect:7.5.0"

      environment = [
        {
          name  = "CONNECT_BOOTSTRAP_SERVERS"
          value = aws_msk_cluster.pyairtable_kafka.bootstrap_brokers_sasl_iam
        },
        {
          name  = "CONNECT_REST_ADVERTISED_HOST_NAME"
          value = "kafka-connect"
        },
        {
          name  = "CONNECT_REST_PORT"
          value = "8083"
        },
        {
          name  = "CONNECT_GROUP_ID"
          value = "pyairtable-connect-cluster"
        },
        {
          name  = "CONNECT_CONFIG_STORAGE_TOPIC"
          value = "pyairtable.connect.configs"
        },
        {
          name  = "CONNECT_OFFSET_STORAGE_TOPIC"
          value = "pyairtable.connect.offsets"
        },
        {
          name  = "CONNECT_STATUS_STORAGE_TOPIC"
          value = "pyairtable.connect.status"
        },
        {
          name  = "CONNECT_KEY_CONVERTER"
          value = "org.apache.kafka.connect.json.JsonConverter"
        },
        {
          name  = "CONNECT_VALUE_CONVERTER"
          value = "org.apache.kafka.connect.json.JsonConverter"
        },
        {
          name  = "CONNECT_SECURITY_PROTOCOL"
          value = "SASL_SSL"
        },
        {
          name  = "CONNECT_SASL_MECHANISM"
          value = "AWS_MSK_IAM"
        },
        {
          name  = "CONNECT_SASL_JAAS_CONFIG"
          value = "software.amazon.msk.auth.iam.IAMLoginModule required;"
        }
      ]

      portMappings = [
        {
          containerPort = 8083
          protocol      = "tcp"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.kafka_connect.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }

      healthCheck = {
        command = [
          "CMD-SHELL",
          "curl -f http://localhost:8083/connectors || exit 1"
        ]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    }
  ])

  tags = {
    Name = "${var.project_name}-kafka-connect-task"
  }
}

# ECS Service for Kafka Connect
resource "aws_ecs_service" "kafka_connect" {
  name            = "${var.project_name}-${var.environment}-kafka-connect"
  cluster         = aws_ecs_cluster.kafka_connect.id
  task_definition = aws_ecs_task_definition.kafka_connect.arn
  desired_count   = var.environment == "prod" ? 2 : 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.kafka_connect.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.kafka_connect.arn
  }

  tags = {
    Name = "${var.project_name}-kafka-connect-service"
  }
}

# Security Group for Kafka Connect
resource "aws_security_group" "kafka_connect" {
  name_prefix = "${var.project_name}-${var.environment}-kafka-connect-"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Kafka Connect REST API"
    from_port   = 8083
    to_port     = 8083
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-kafka-connect-sg"
  }
}

# Service Discovery for Kafka Connect
resource "aws_service_discovery_service" "kafka_connect" {
  name = "kafka-connect"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.internal.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_grace_period_seconds = 30
}

# ==============================================================================
# KUBERNETES INTEGRATION
# ==============================================================================

# Kubernetes Secret for Kafka connection
resource "kubernetes_secret" "kafka_config" {
  metadata {
    name      = "kafka-config"
    namespace = "pyairtable"
  }

  data = {
    bootstrap_servers = aws_msk_cluster.pyairtable_kafka.bootstrap_brokers_sasl_iam
    cluster_arn       = aws_msk_cluster.pyairtable_kafka.arn
    security_protocol = "SASL_SSL"
    sasl_mechanism    = "AWS_MSK_IAM"
  }

  type = "Opaque"
}

# KEDA ScaledObject for Kafka-based autoscaling
resource "kubernetes_manifest" "kafka_scaler" {
  manifest = {
    apiVersion = "keda.sh/v1alpha1"
    kind       = "ScaledObject"
    metadata = {
      name      = "kafka-consumer-scaler"
      namespace = "pyairtable"
      labels = {
        app                             = "kafka-consumer"
        "app.kubernetes.io/component"   = "autoscaler"
        "app.kubernetes.io/managed-by"  = "terraform"
      }
    }
    spec = {
      scaleTargetRef = {
        name = "event-processor"
      }
      pollingInterval  = 15
      cooldownPeriod   = 300
      minReplicaCount  = 1
      maxReplicaCount  = 20
      triggers = [
        {
          type = "aws-kafka"
          metadata = {
            awsRegion       = var.aws_region
            bootstrapServers = aws_msk_cluster.pyairtable_kafka.bootstrap_brokers_sasl_iam
            consumerGroup   = "pyairtable-event-processor"
            topic           = "pyairtable.workflows.events"
            lagThreshold    = "100"
            # Authentication via IAM role
            authenticationRef = {
              name = "kafka-auth-trigger"
            }
          }
        }
      ]
    }
  }
}

# ==============================================================================
# OUTPUTS
# ==============================================================================

output "kafka_cluster" {
  description = "Kafka cluster information"
  value = {
    cluster_arn              = aws_msk_cluster.pyairtable_kafka.arn
    bootstrap_brokers        = aws_msk_cluster.pyairtable_kafka.bootstrap_brokers
    bootstrap_brokers_sasl   = aws_msk_cluster.pyairtable_kafka.bootstrap_brokers_sasl_iam
    zookeeper_connect_string = aws_msk_cluster.pyairtable_kafka.zookeeper_connect_string
    cluster_name            = aws_msk_cluster.pyairtable_kafka.cluster_name
  }
  sensitive = false
}

output "kafka_topics" {
  description = "Kafka topics configuration"
  value       = local.kafka_topics
}

output "kafka_cost_estimation" {
  description = "Monthly cost estimation for Kafka infrastructure (USD)"
  value = {
    msk_cluster = var.environment == "prod" ? {
      instance_cost = "432"  # 6 x kafka.m5.xlarge ($0.30/hour)
      storage_cost  = "300"  # 6TB EBS gp3 storage
      data_transfer = "50"   # Inter-AZ data transfer
      total        = "782"
    } : {
      instance_cost = "162"  # 3 x kafka.m5.large ($0.15/hour)
      storage_cost  = "75"   # 1.5TB EBS gp3 storage
      data_transfer = "25"   # Inter-AZ data transfer
      total        = "262"
    }
    kafka_connect = var.environment == "prod" ? {
      fargate_cost = "144"   # 2 instances on Fargate
      total       = "144"
    } : {
      fargate_cost = "72"    # 1 instance on Fargate
      total       = "72"
    }
    monitoring = {
      cloudwatch_logs = "25"
      cloudwatch_metrics = "15"
      s3_storage = var.environment == "prod" ? "10" : "0"
      total = var.environment == "prod" ? "50" : "40"
    }
    total_monthly = var.environment == "prod" ? "976" : "374"
  }
}

# Random ID for unique bucket naming
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# Data source for current AWS account
data "aws_caller_identity" "current" {}