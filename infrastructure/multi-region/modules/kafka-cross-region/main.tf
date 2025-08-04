# Kafka Cross-Region Mirroring Module
# Amazon MSK with cross-region replication and consistent data partitioning

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

# KMS key for MSK encryption
resource "aws_kms_key" "msk" {
  description             = "KMS key for MSK cluster encryption"
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
        Sid    = "Allow MSK Service"
        Effect = "Allow"
        Principal = {
          Service = "kafka.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-${var.region}-msk-key"
  })
}

resource "aws_kms_alias" "msk" {
  name          = "alias/${var.project_name}-${var.environment}-${var.region}-msk"
  target_key_id = aws_kms_key.msk.key_id
}

data "aws_caller_identity" "current" {}

# Security group for MSK cluster
resource "aws_security_group" "msk" {
  name_prefix = "${var.project_name}-${var.environment}-${var.region}-msk-"
  vpc_id      = var.vpc_id

  # Kafka broker communication
  ingress {
    description = "Kafka broker communication"
    from_port   = 9092
    to_port     = 9092
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Kafka TLS communication
  ingress {
    description = "Kafka TLS communication"
    from_port   = 9094
    to_port     = 9094
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Kafka SASL/SCRAM communication
  ingress {
    description = "Kafka SASL/SCRAM communication"
    from_port   = 9096
    to_port     = 9096
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Kafka IAM authentication
  ingress {
    description = "Kafka IAM authentication"
    from_port   = 9098
    to_port     = 9098
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Zookeeper (for older MSK versions)
  ingress {
    description = "Zookeeper"
    from_port   = 2181
    to_port     = 2181
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # JMX monitoring
  ingress {
    description = "JMX monitoring"
    from_port   = 11001
    to_port     = 11002
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Cross-region peering
  dynamic "ingress" {
    for_each = var.cross_region_cidrs
    content {
      description = "Cross-region access from ${ingress.key}"
      from_port   = 9092
      to_port     = 9098
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-${var.region}-msk-sg"
  })
}

# MSK Configuration
resource "aws_msk_configuration" "main" {
  kafka_versions    = [var.kafka_version]
  name             = "${var.project_name}-${var.environment}-${var.region}-config"
  description      = "MSK configuration for ${var.project_name}"

  server_properties = <<-EOT
    # Replication and durability
    default.replication.factor=3
    min.insync.replicas=2
    unclean.leader.election.enable=false
    
    # Performance optimizations
    num.network.threads=8
    num.io.threads=16
    socket.send.buffer.bytes=102400
    socket.receive.buffer.bytes=102400
    socket.request.max.bytes=104857600
    
    # Log settings
    num.partitions=${var.default_partitions}
    log.retention.hours=${var.log_retention_hours}
    log.segment.bytes=1073741824
    log.retention.check.interval.ms=300000
    log.segment.ms=604800000
    
    # Compression
    compression.type=snappy
    
    # Producer settings
    acks=all
    retries=2147483647
    max.in.flight.requests.per.connection=5
    enable.idempotence=true
    
    # Consumer settings
    auto.offset.reset=earliest
    enable.auto.commit=false
    
    # Cross-region replication settings
    replica.fetch.min.bytes=1
    replica.fetch.wait.max.ms=500
    replica.high.watermark.checkpoint.interval.ms=5000
    replica.socket.timeout.ms=30000
    replica.socket.receive.buffer.bytes=65536
    
    # Topic management
    auto.create.topics.enable=false
    delete.topic.enable=true
    
    # Security settings
    security.inter.broker.protocol=SSL
    ssl.keystore.type=JKS
    ssl.truststore.type=JKS
    
    # Monitoring
    jmx.port=11001
    
    # Cross-region mirroring
    replica.lag.time.max.ms=30000
    replica.fetch.max.bytes=1048576
    
    # Partitioning strategy for consistent hashing
    partitioner.class=org.apache.kafka.clients.producer.RoundRobinPartitioner
  EOT

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-${var.region}-msk-config"
  })
}

# MSK Cluster
resource "aws_msk_cluster" "main" {
  cluster_name           = "${var.project_name}-${var.environment}-${var.region}"
  kafka_version          = var.kafka_version
  number_of_broker_nodes = var.number_of_broker_nodes

  broker_node_group_info {
    instance_type   = var.kafka_instance_type
    client_subnets  = var.private_subnet_ids
    security_groups = [aws_security_group.msk.id]
    
    storage_info {
      ebs_storage_info {
        volume_size = var.kafka_ebs_volume_size
      }
    }
    
    connectivity_info {
      public_access {
        type = "DISABLED"
      }
    }
  }

  configuration_info {
    arn      = aws_msk_configuration.main.arn
    revision = aws_msk_configuration.main.latest_revision
  }

  encryption_info {
    encryption_at_rest_kms_key_id = aws_kms_key.msk.id
    encryption_in_transit {
      client_broker = "TLS"
      in_cluster    = true
    }
  }

  client_authentication {
    sasl {
      iam   = true
      scram = false
    }
    tls {}
  }

  logging_info {
    broker_logs {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.msk_broker.name
      }
      s3 {
        enabled = true
        bucket  = aws_s3_bucket.msk_logs.bucket
        prefix  = "broker-logs/"
      }
    }
  }

  open_monitoring {
    prometheus {
      jmx_exporter {
        enabled_in_broker = true
      }
      node_exporter {
        enabled_in_broker = true
      }
    }
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-${var.region}-msk"
  })
}

# CloudWatch Log Group for MSK
resource "aws_cloudwatch_log_group" "msk_broker" {
  name              = "/aws/msk/${var.project_name}-${var.environment}-${var.region}/broker"
  retention_in_days = var.log_retention_days
  kms_key_id       = aws_kms_key.msk.arn

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-${var.region}-msk-broker-logs"
  })
}

# S3 bucket for MSK logs
resource "aws_s3_bucket" "msk_logs" {
  bucket = "${var.project_name}-${var.environment}-${var.region}-msk-logs-${random_string.bucket_suffix.result}"

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-${var.region}-msk-logs"
  })
}

resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "aws_s3_bucket_versioning" "msk_logs" {
  bucket = aws_s3_bucket.msk_logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "msk_logs" {
  bucket = aws_s3_bucket.msk_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.msk.arn
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "msk_logs" {
  bucket = aws_s3_bucket.msk_logs.id

  rule {
    id     = "log_lifecycle"
    status = "Enabled"

    expiration {
      days = var.log_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

# MSK Connect service role
resource "aws_iam_role" "msk_connect" {
  name = "${var.project_name}-${var.environment}-${var.region}-msk-connect-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "kafkaconnect.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-${var.region}-msk-connect-role"
  })
}

resource "aws_iam_policy" "msk_connect" {
  name        = "${var.project_name}-${var.environment}-${var.region}-msk-connect-policy"
  description = "Policy for MSK Connect service"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kafka:DescribeCluster",
          "kafka:GetBootstrapBrokers",
          "kafka:DescribeClusterV2",
          "kafka:GetCompatibleKafkaVersions"
        ]
        Resource = aws_msk_cluster.main.arn
      },
      {
        Effect = "Allow"
        Action = [
          "kafka-cluster:Connect",
          "kafka-cluster:DescribeCluster",
          "kafka-cluster:WriteData",
          "kafka-cluster:ReadData",
          "kafka-cluster:CreateTopic",
          "kafka-cluster:DescribeTopic",
          "kafka-cluster:WriteDataIdempotently",
          "kafka-cluster:DescribeTopicDynamicConfiguration"
        ]
        Resource = [
          aws_msk_cluster.main.arn,
          "${aws_msk_cluster.main.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.msk_logs.arn,
          "${aws_s3_bucket.msk_logs.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "msk_connect" {
  role       = aws_iam_role.msk_connect.name
  policy_arn = aws_iam_policy.msk_connect.arn
}

# Custom plugin for cross-region mirroring
resource "aws_s3_object" "mirror_maker_plugin" {
  bucket = aws_s3_bucket.msk_logs.bucket
  key    = "plugins/mirror-maker-connector.jar"
  source = "${path.module}/plugins/mirror-maker-connector.jar"
  etag   = filemd5("${path.module}/plugins/mirror-maker-connector.jar")

  tags = merge(var.tags, {
    Name = "mirror-maker-plugin"
  })
}

resource "aws_mskconnect_custom_plugin" "mirror_maker" {
  name         = "${var.project_name}-${var.environment}-${var.region}-mirror-maker"
  content_type = "JAR"
  description  = "MirrorMaker 2.0 connector for cross-region replication"

  location {
    s3 {
      bucket_arn = aws_s3_bucket.msk_logs.arn
      file_key   = aws_s3_object.mirror_maker_plugin.key
    }
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-${var.region}-mirror-maker-plugin"
  })
}

# Cross-region replication connectors (only if target regions are specified)
resource "aws_mskconnect_connector" "cross_region_mirror" {
  for_each = var.target_regions

  name = "${var.project_name}-${var.environment}-${var.region}-to-${each.key}-mirror"

  kafkaconnect_version = "2.7.1"

  capacity {
    provisioned_capacity {
      mcu_count    = 2
      worker_count = 2
    }
  }

  connector_configuration = {
    "connector.class"                = "org.apache.kafka.connect.mirror.MirrorSourceConnector"
    "source.cluster.alias"          = var.region
    "target.cluster.alias"          = each.key
    "source.cluster.bootstrap.servers" = aws_msk_cluster.main.bootstrap_brokers_tls
    "target.cluster.bootstrap.servers" = each.value.bootstrap_servers
    "topics"                        = join(",", var.topics_to_replicate)
    "groups"                        = ".*"
    "tasks.max"                     = "4"
    "replication.factor"            = "3"
    "checkpoints.topic.replication.factor" = "3"
    "heartbeats.topic.replication.factor"  = "3"
    "offset-syncs.topic.replication.factor" = "3"
    "sync.topic.acls.enabled"       = "false"
    "emit.checkpoints.enabled"      = "true"
    "emit.heartbeats.enabled"       = "true"
    "refresh.topics.enabled"        = "true"
    "refresh.topics.interval.seconds" = "300"
    "key.converter"                 = "org.apache.kafka.connect.converters.ByteArrayConverter"
    "value.converter"               = "org.apache.kafka.connect.converters.ByteArrayConverter"
    "security.protocol"             = "SSL"
    "ssl.truststore.type"           = "JKS"
    "producer.security.protocol"    = "SSL"
    "consumer.security.protocol"    = "SSL"
    "admin.security.protocol"       = "SSL"
  }

  kafka_cluster {
    apache_kafka_cluster {
      bootstrap_servers = aws_msk_cluster.main.bootstrap_brokers_tls

      vpc {
        security_groups = [aws_security_group.msk.id]
        subnets        = var.private_subnet_ids
      }
    }
  }

  kafka_cluster_client_authentication {
    authentication_type = "IAM"
  }

  kafka_cluster_encryption_in_transit {
    encryption_type = "TLS"
  }

  plugin {
    custom_plugin {
      arn      = aws_mskconnect_custom_plugin.mirror_maker.arn
      revision = aws_mskconnect_custom_plugin.mirror_maker.latest_revision
    }
  }

  service_execution_role_arn = aws_iam_role.msk_connect.arn

  log_delivery {
    worker_log_delivery {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.msk_connect.name
      }
    }
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-${var.region}-to-${each.key}-mirror"
  })
}

# CloudWatch Log Group for MSK Connect
resource "aws_cloudwatch_log_group" "msk_connect" {
  name              = "/aws/mskconnect/${var.project_name}-${var.environment}-${var.region}"
  retention_in_days = var.log_retention_days
  kms_key_id       = aws_kms_key.msk.arn

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-${var.region}-msk-connect-logs"
  })
}

# CloudWatch Alarms for MSK monitoring
resource "aws_cloudwatch_metric_alarm" "kafka_cpu_utilization" {
  alarm_name          = "${var.project_name}-${var.environment}-${var.region}-kafka-cpu-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CpuIdle"
  namespace           = "AWS/Kafka"
  period              = "300"
  statistic           = "Average"
  threshold           = "20"  # Alert when CPU idle is less than 20%
  alarm_description   = "This metric monitors Kafka CPU utilization"
  alarm_actions       = var.alarm_actions

  dimensions = {
    "Cluster Name" = aws_msk_cluster.main.cluster_name
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-${var.region}-kafka-cpu-alarm"
  })
}

resource "aws_cloudwatch_metric_alarm" "kafka_network_rx" {
  alarm_name          = "${var.project_name}-${var.environment}-${var.region}-kafka-network-rx"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "NetworkRxErrors"
  namespace           = "AWS/Kafka"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "This metric monitors Kafka network receive errors"
  alarm_actions       = var.alarm_actions

  dimensions = {
    "Cluster Name" = aws_msk_cluster.main.cluster_name
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-${var.region}-kafka-network-rx-alarm"
  })
}

resource "aws_cloudwatch_metric_alarm" "kafka_under_replicated_partitions" {
  alarm_name          = "${var.project_name}-${var.environment}-${var.region}-kafka-under-replicated"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "UnderReplicatedPartitions"
  namespace           = "AWS/Kafka"
  period              = "300"
  statistic           = "Maximum"
  threshold           = "0"
  alarm_description   = "This metric monitors under-replicated partitions"
  alarm_actions       = var.alarm_actions

  dimensions = {
    "Cluster Name" = aws_msk_cluster.main.cluster_name
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-${var.region}-kafka-under-replicated-alarm"
  })
}

# Lambda function for topic creation and management
resource "aws_lambda_function" "kafka_topic_manager" {
  filename         = data.archive_file.topic_manager.output_path
  function_name    = "${var.project_name}-${var.environment}-${var.region}-kafka-topic-manager"
  role            = aws_iam_role.topic_manager.arn
  handler         = "topic_manager.handler"
  runtime         = "python3.11"
  timeout         = 300
  memory_size     = 512

  source_code_hash = data.archive_file.topic_manager.output_base64sha256

  environment {
    variables = {
      BOOTSTRAP_SERVERS = aws_msk_cluster.main.bootstrap_brokers_tls
      REGION           = var.region
      PROJECT_NAME     = var.project_name
      ENVIRONMENT      = var.environment
    }
  }

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [aws_security_group.msk.id]
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-${var.region}-kafka-topic-manager"
  })
}

data "archive_file" "topic_manager" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/topic_manager"
  output_path = "/tmp/kafka_topic_manager.zip"
}

# IAM role for topic manager Lambda
resource "aws_iam_role" "topic_manager" {
  name = "${var.project_name}-${var.environment}-${var.region}-kafka-topic-manager-role"

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

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-${var.region}-kafka-topic-manager-role"
  })
}

resource "aws_iam_policy" "topic_manager" {
  name        = "${var.project_name}-${var.environment}-${var.region}-kafka-topic-manager-policy"
  description = "Policy for Kafka topic manager Lambda"

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
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "kafka-cluster:*"
        ]
        Resource = [
          aws_msk_cluster.main.arn,
          "${aws_msk_cluster.main.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "topic_manager" {
  role       = aws_iam_role.topic_manager.name
  policy_arn = aws_iam_policy.topic_manager.arn
}

resource "aws_iam_role_policy_attachment" "topic_manager_vpc" {
  role       = aws_iam_role.topic_manager.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Create default topics
resource "aws_lambda_invocation" "create_topics" {
  for_each = toset(var.default_topics)

  function_name = aws_lambda_function.kafka_topic_manager.function_name

  input = jsonencode({
    action = "create_topic"
    topic_name = each.key
    partitions = var.default_partitions
    replication_factor = 3
    configs = {
      "cleanup.policy" = "delete"
      "retention.ms" = "${var.log_retention_hours * 3600000}"
      "compression.type" = "snappy"
      "min.insync.replicas" = "2"
    }
  })

  depends_on = [aws_msk_cluster.main]
}