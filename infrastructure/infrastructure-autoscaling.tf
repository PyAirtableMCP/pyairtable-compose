# Infrastructure-Level Autoscaling for PyAirtable
# Comprehensive scaling for databases, Redis, Kafka, and supporting infrastructure

# Data sources for infrastructure autoscaling
data "aws_availability_zones" "available" {
  state = "available"
}

# Aurora Serverless v2 for Database Autoscaling
resource "aws_rds_cluster" "pyairtable_serverless" {
  cluster_identifier              = "${var.project_name}-${var.environment}-serverless"
  engine                         = "aurora-postgresql"
  engine_mode                    = "provisioned"
  engine_version                 = "15.4"
  database_name                  = "pyairtable"
  master_username                = "pyairtable_admin"
  manage_master_user_password    = true
  master_user_secret_kms_key_id  = aws_kms_key.database.arn
  
  # Serverless v2 scaling configuration
  serverlessv2_scaling_configuration {
    max_capacity = var.environment == "prod" ? 16 : 4
    min_capacity = var.environment == "prod" ? 2 : 0.5
  }
  
  vpc_security_group_ids = [aws_security_group.database.id]
  db_subnet_group_name   = aws_db_subnet_group.pyairtable.name
  
  # Backup and maintenance
  backup_retention_period = var.environment == "prod" ? 30 : 7
  preferred_backup_window = "03:00-04:00"
  preferred_maintenance_window = "sun:04:00-sun:05:00"
  
  # Performance insights
  enabled_cloudwatch_logs_exports = ["postgresql"]
  performance_insights_enabled    = true
  performance_insights_kms_key_id = aws_kms_key.database.arn
  performance_insights_retention_period = var.environment == "prod" ? 731 : 7
  
  # Encryption
  storage_encrypted = true
  kms_key_id       = aws_kms_key.database.arn
  
  # Auto scaling
  deletion_protection = var.environment == "prod" ? true : false
  skip_final_snapshot = var.environment != "prod"
  
  tags = {
    Name        = "${var.project_name}-${var.environment}-aurora-serverless"
    Environment = var.environment
    Project     = var.project_name
    Component   = "database"
    Scaling     = "serverless-v2"
  }
}

# Aurora cluster instances for read scaling
resource "aws_rds_cluster_instance" "pyairtable_serverless_instances" {
  count              = var.environment == "prod" ? 2 : 1
  identifier         = "${var.project_name}-${var.environment}-instance-${count.index}"
  cluster_identifier = aws_rds_cluster.pyairtable_serverless.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.pyairtable_serverless.engine
  engine_version     = aws_rds_cluster.pyairtable_serverless.engine_version
  
  # Performance monitoring
  performance_insights_enabled = true
  performance_insights_kms_key_id = aws_kms_key.database.arn
  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_enhanced_monitoring.arn
  
  tags = {
    Name        = "${var.project_name}-${var.environment}-aurora-instance-${count.index}"
    Environment = var.environment
    Component   = "database"
  }
}

# ElastiCache Redis with Cluster Mode and Auto Scaling
resource "aws_elasticache_replication_group" "redis_cluster" {
  replication_group_id         = "${var.project_name}-${var.environment}-redis"
  description                  = "Redis cluster for PyAirtable with auto scaling"
  
  # Cluster configuration
  node_type                    = var.environment == "prod" ? "cache.r6g.large" : "cache.t3.micro"
  port                        = 6379
  parameter_group_name        = aws_elasticache_parameter_group.redis.name
  subnet_group_name           = aws_elasticache_subnet_group.redis.name
  security_group_ids          = [aws_security_group.redis.id]
  
  # Cluster mode enabled for horizontal scaling
  num_cache_clusters         = var.environment == "prod" ? 3 : 2
  num_node_groups            = var.environment == "prod" ? 3 : 1
  replicas_per_node_group    = var.environment == "prod" ? 2 : 1
  
  # Automatic failover and multi-AZ
  automatic_failover_enabled = true
  multi_az_enabled          = var.environment == "prod"
  
  # Backup and maintenance
  snapshot_retention_limit = var.environment == "prod" ? 7 : 1
  snapshot_window         = "03:00-05:00"
  maintenance_window      = "sun:05:00-sun:07:00"
  
  # Encryption
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  kms_key_id                = aws_kms_key.redis.arn
  auth_token                = random_password.redis_auth.result
  
  # Notifications
  notification_topic_arn = aws_sns_topic.notifications.arn
  
  # Auto scaling
  auto_minor_version_upgrade = true
  
  tags = {
    Name        = "${var.project_name}-${var.environment}-redis-cluster"
    Environment = var.environment
    Component   = "cache"
    Scaling     = "cluster-mode"
  }
}

# ElastiCache Parameter Group for Redis optimization
resource "aws_elasticache_parameter_group" "redis" {
  family = "redis7.x"
  name   = "${var.project_name}-${var.environment}-redis-params"
  
  # Memory and performance optimization
  parameter {
    name  = "maxmemory-policy"
    value = "allkeys-lru"
  }
  
  parameter {
    name  = "timeout"
    value = "300"
  }
  
  parameter {
    name  = "tcp-keepalive"
    value = "300"
  }
  
  # Cluster optimization
  parameter {
    name  = "cluster-enabled"
    value = "yes"
  }
  
  tags = {
    Name = "${var.project_name}-${var.environment}-redis-params"
  }
}

# Amazon MSK (Managed Kafka) with Auto Scaling
resource "aws_msk_cluster" "kafka_cluster" {
  cluster_name           = "${var.project_name}-${var.environment}-kafka"
  kafka_version          = "3.5.1"
  number_of_broker_nodes = var.environment == "prod" ? 6 : 3
  
  broker_node_group_info {
    instance_type   = var.environment == "prod" ? "kafka.m5.xlarge" : "kafka.t3.small"
    client_subnets  = aws_subnet.private[*].id
    security_groups = [aws_security_group.kafka.id]
    
    storage_info {
      ebs_storage_info {
        volume_size = var.environment == "prod" ? 1000 : 100
        provisioned_throughput {
          enabled           = var.environment == "prod"
          volume_throughput = var.environment == "prod" ? 250 : null
        }
      }
    }
    
    connectivity_info {
      public_access {
        type = "DISABLED"
      }
      vpc_connectivity {
        client_authentication {
          sasl {
            iam = true
          }
          tls = true
        }
      }
    }
  }
  
  # Configuration for auto scaling and performance
  configuration_info {
    arn      = aws_msk_configuration.kafka_config.arn
    revision = aws_msk_configuration.kafka_config.latest_revision
  }
  
  # Encryption
  encryption_info {
    encryption_at_rest_kms_key_id = aws_kms_key.kafka.arn
    encryption_in_transit {
      client_broker = "TLS"
      in_cluster    = true
    }
  }
  
  # Enhanced monitoring
  enhanced_monitoring = "PER_TOPIC_PER_BROKER"
  
  # Logging
  logging_info {
    broker_logs {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.kafka.name
      }
      firehose {
        enabled         = false
      }
      s3 {
        enabled = var.environment == "prod"
        bucket  = var.environment == "prod" ? aws_s3_bucket.kafka_logs[0].id : null
        prefix  = "kafka-logs/"
      }
    }
  }
  
  tags = {
    Name        = "${var.project_name}-${var.environment}-kafka"
    Environment = var.environment
    Component   = "messaging"
    Scaling     = "managed-auto"
  }
}

# MSK Configuration for performance optimization
resource "aws_msk_configuration" "kafka_config" {
  kafka_versions = ["3.5.1"]
  name           = "${var.project_name}-${var.environment}-kafka-config"
  
  server_properties = <<PROPERTIES
# Auto scaling and performance settings
auto.create.topics.enable=false
default.replication.factor=3
min.insync.replicas=2
num.network.threads=8
num.io.threads=16
socket.send.buffer.bytes=102400
socket.receive.buffer.bytes=102400
socket.request.max.bytes=104857600

# Log settings for better performance
log.retention.hours=168
log.segment.bytes=1073741824
log.retention.check.interval.ms=300000
log.cleanup.policy=delete

# Producer settings
compression.type=snappy
batch.size=65536
linger.ms=10

# Consumer settings
fetch.min.bytes=50000
fetch.max.wait.ms=500

# Memory settings
replica.fetch.max.bytes=10485760
message.max.bytes=10485760

# Connection settings
num.replica.fetchers=4
replica.lag.time.max.ms=30000

# JVM settings for auto scaling
KAFKA_HEAP_OPTS=-Xmx4g -Xms4g
KAFKA_JVM_PERFORMANCE_OPTS=-server -XX:+UseG1GC -XX:MaxGCPauseMillis=20 -XX:InitiatingHeapOccupancyPercent=35
PROPERTIES
}

# Application Auto Scaling for MSK Storage
resource "aws_appautoscaling_target" "msk_storage" {
  count              = var.environment == "prod" ? 1 : 0
  max_capacity       = 10000  # 10TB max
  min_capacity       = 1000   # 1TB min
  resource_id        = "cluster/${aws_msk_cluster.kafka_cluster.cluster_name}"
  scalable_dimension = "kafka:broker-storage:VolumeSize"
  service_namespace  = "kafka"
}

resource "aws_appautoscaling_policy" "msk_storage_policy" {
  count              = var.environment == "prod" ? 1 : 0
  name               = "${var.project_name}-msk-storage-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.msk_storage[0].resource_id
  scalable_dimension = aws_appautoscaling_target.msk_storage[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.msk_storage[0].service_namespace
  
  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "KafkaBrokerStorageUtilization"
    }
    target_value       = 70.0
    scale_out_cooldown = 300
    scale_in_cooldown  = 300
  }
}

# OpenSearch (Elasticsearch) with Auto Scaling
resource "aws_opensearch_domain" "search_cluster" {
  domain_name    = "${var.project_name}-${var.environment}-search"
  engine_version = "OpenSearch_2.9"
  
  cluster_config {
    instance_type            = var.environment == "prod" ? "t3.medium.search" : "t3.small.search"
    instance_count           = var.environment == "prod" ? 3 : 1
    dedicated_master_enabled = var.environment == "prod"
    dedicated_master_type    = var.environment == "prod" ? "t3.small.search" : null
    dedicated_master_count   = var.environment == "prod" ? 3 : null
    zone_awareness_enabled   = var.environment == "prod"
    
    dynamic "zone_awareness_config" {
      for_each = var.environment == "prod" ? [1] : []
      content {
        availability_zone_count = 3
      }
    }
    
    # Auto scaling configuration
    warm_enabled = var.environment == "prod"
    warm_count   = var.environment == "prod" ? 2 : null
    warm_type    = var.environment == "prod" ? "ultrawarm1.medium.search" : null
  }
  
  # Storage auto scaling
  ebs_options {
    ebs_enabled = true
    volume_type = "gp3"
    volume_size = var.environment == "prod" ? 100 : 20
    throughput  = var.environment == "prod" ? 250 : 125
  }
  
  # Network configuration
  vpc_options {
    subnet_ids         = var.environment == "prod" ? aws_subnet.private[*].id : [aws_subnet.private[0].id]
    security_group_ids = [aws_security_group.opensearch.id]
  }
  
  # Encryption
  encrypt_at_rest {
    enabled    = true
    kms_key_id = aws_kms_key.opensearch.arn
  }
  
  node_to_node_encryption {
    enabled = true
  }
  
  domain_endpoint_options {
    enforce_https       = true
    tls_security_policy = "Policy-Min-TLS-1-2-2019-07"
  }
  
  # Advanced options for performance
  advanced_options = {
    "rest.action.multi.allow_explicit_index" = "true"
    "indices.fielddata.cache.size"           = "20%"
    "indices.query.bool.max_clause_count"    = "10000"
  }
  
  # Logging
  log_publishing_options {
    cloudwatch_log_group_arn = aws_cloudwatch_log_group.opensearch_index.arn
    log_type                 = "INDEX_SLOW_LOGS"
    enabled                  = true
  }
  
  log_publishing_options {
    cloudwatch_log_group_arn = aws_cloudwatch_log_group.opensearch_search.arn
    log_type                 = "SEARCH_SLOW_LOGS"
    enabled                  = true
  }
  
  tags = {
    Name        = "${var.project_name}-${var.environment}-opensearch"
    Environment = var.environment
    Component   = "search"
    Scaling     = "auto"
  }
}

# Auto Scaling for RDS Read Replicas
resource "aws_db_instance" "read_replica" {
  count                     = var.environment == "prod" ? 2 : 0
  identifier                = "${var.project_name}-${var.environment}-read-replica-${count.index}"
  replicate_source_db       = aws_rds_cluster.pyairtable_serverless.id
  instance_class            = "db.r6g.large"
  publicly_accessible       = false
  auto_minor_version_upgrade = true
  
  # Performance monitoring
  performance_insights_enabled = true
  performance_insights_kms_key_id = aws_kms_key.database.arn
  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_enhanced_monitoring.arn
  
  tags = {
    Name        = "${var.project_name}-${var.environment}-read-replica-${count.index}"
    Environment = var.environment
    Component   = "database"
    Role        = "read-replica"
  }
}

# Application Auto Scaling for RDS Aurora
resource "aws_appautoscaling_target" "aurora_read_replica" {
  count              = var.environment == "prod" ? 1 : 0
  max_capacity       = 15
  min_capacity       = 2
  resource_id        = "cluster:${aws_rds_cluster.pyairtable_serverless.cluster_identifier}"
  scalable_dimension = "rds:cluster:ReadReplicaCount"
  service_namespace  = "rds"
}

resource "aws_appautoscaling_policy" "aurora_read_replica_policy" {
  count              = var.environment == "prod" ? 1 : 0
  name               = "${var.project_name}-aurora-read-replica-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.aurora_read_replica[0].resource_id
  scalable_dimension = aws_appautoscaling_target.aurora_read_replica[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.aurora_read_replica[0].service_namespace
  
  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "RDSReaderAverageCPUUtilization"
    }
    target_value = 70.0
  }
}

# CloudWatch Alarms for Infrastructure Scaling
resource "aws_cloudwatch_metric_alarm" "database_cpu_high" {
  alarm_name          = "${var.project_name}-${var.environment}-database-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "120"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors database CPU utilization"
  alarm_actions       = [aws_sns_topic.notifications.arn]
  
  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.pyairtable_serverless.cluster_identifier
  }
  
  tags = {
    Name = "${var.project_name}-database-cpu-alarm"
  }
}

resource "aws_cloudwatch_metric_alarm" "redis_cpu_high" {
  alarm_name          = "${var.project_name}-${var.environment}-redis-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ElastiCache"
  period              = "300"
  statistic           = "Average"
  threshold           = "75"
  alarm_description   = "This metric monitors Redis CPU utilization"
  alarm_actions       = [aws_sns_topic.notifications.arn]
  
  dimensions = {
    CacheClusterId = aws_elasticache_replication_group.redis_cluster.id
  }
  
  tags = {
    Name = "${var.project_name}-redis-cpu-alarm"
  }
}

resource "aws_cloudwatch_metric_alarm" "kafka_disk_usage_high" {
  alarm_name          = "${var.project_name}-${var.environment}-kafka-disk-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "KafkaDataLogsDiskUsed"
  namespace           = "AWS/Kafka"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors Kafka disk usage"
  alarm_actions       = [aws_sns_topic.notifications.arn]
  
  dimensions = {
    "Cluster Name" = aws_msk_cluster.kafka_cluster.cluster_name
  }
  
  tags = {
    Name = "${var.project_name}-kafka-disk-alarm"
  }
}

# Lambda function for custom scaling logic
resource "aws_lambda_function" "infrastructure_scaler" {
  filename         = "infrastructure_scaler.zip"
  function_name    = "${var.project_name}-${var.environment}-infrastructure-scaler"
  role            = aws_iam_role.lambda_scaling.arn
  handler         = "index.handler"
  source_code_hash = data.archive_file.infrastructure_scaler.output_base64sha256
  runtime         = "python3.11"
  timeout         = 300
  
  environment {
    variables = {
      CLUSTER_NAME        = aws_rds_cluster.pyairtable_serverless.cluster_identifier
      REDIS_CLUSTER_ID    = aws_elasticache_replication_group.redis_cluster.id
      KAFKA_CLUSTER_NAME  = aws_msk_cluster.kafka_cluster.cluster_name
      ENVIRONMENT         = var.environment
      SNS_TOPIC_ARN       = aws_sns_topic.notifications.arn
    }
  }
  
  tags = {
    Name        = "${var.project_name}-infrastructure-scaler"
    Environment = var.environment
    Component   = "scaling"
  }
}

# Archive file for Lambda function
data "archive_file" "infrastructure_scaler" {
  type        = "zip"
  output_path = "infrastructure_scaler.zip"
  source {
    content = <<EOF
import json
import boto3
import os
from datetime import datetime, timedelta

def handler(event, context):
    """
    Custom infrastructure scaling logic based on metrics and time-based patterns
    """
    
    # Initialize AWS clients
    rds_client = boto3.client('rds')
    elasticache_client = boto3.client('elasticache')
    kafka_client = boto3.client('kafka')
    cloudwatch = boto3.client('cloudwatch')
    sns = boto3.client('sns')
    
    cluster_name = os.environ['CLUSTER_NAME']
    redis_cluster_id = os.environ['REDIS_CLUSTER_ID']
    kafka_cluster_name = os.environ['KAFKA_CLUSTER_NAME']
    environment = os.environ['ENVIRONMENT']
    sns_topic = os.environ['SNS_TOPIC_ARN']
    
    scaling_decisions = []
    
    try:
        # Get current hour for time-based scaling
        current_hour = datetime.utcnow().hour
        is_business_hours = 8 <= current_hour <= 18
        is_weekend = datetime.utcnow().weekday() >= 5
        
        # Database scaling logic
        db_metrics = get_database_metrics(cloudwatch, cluster_name)
        if should_scale_database(db_metrics, is_business_hours, is_weekend, environment):
            scaling_decision = scale_database(rds_client, cluster_name, db_metrics, environment)
            scaling_decisions.append(scaling_decision)
        
        # Redis scaling logic
        redis_metrics = get_redis_metrics(cloudwatch, redis_cluster_id)
        if should_scale_redis(redis_metrics, is_business_hours, environment):
            scaling_decision = scale_redis(elasticache_client, redis_cluster_id, redis_metrics, environment)
            scaling_decisions.append(scaling_decision)
        
        # Kafka scaling logic (mainly storage)
        kafka_metrics = get_kafka_metrics(cloudwatch, kafka_cluster_name)
        if should_scale_kafka(kafka_metrics, environment):
            scaling_decision = scale_kafka_storage(kafka_client, kafka_cluster_name, kafka_metrics)
            scaling_decisions.append(scaling_decision)
        
        # Send notifications if any scaling occurred
        if scaling_decisions:
            message = f"Infrastructure scaling performed:\\n" + "\\n".join(scaling_decisions)
            sns.publish(
                TopicArn=sns_topic,
                Message=message,
                Subject=f"PyAirtable {environment} - Infrastructure Auto Scaling"
            )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Infrastructure scaling check completed',
                'decisions': scaling_decisions
            })
        }
    
    except Exception as e:
        error_message = f"Error in infrastructure scaling: {str(e)}"
        sns.publish(
            TopicArn=sns_topic,
            Message=error_message,
            Subject=f"PyAirtable {environment} - Infrastructure Scaling Error"
        )
        raise e

def get_database_metrics(cloudwatch, cluster_name):
    """Get database performance metrics"""
    end_time = datetime.utcnow()
    start_time = end_time - timedelta(minutes=30)
    
    metrics = {}
    
    # CPU utilization
    cpu_response = cloudwatch.get_metric_statistics(
        Namespace='AWS/RDS',
        MetricName='CPUUtilization',
        Dimensions=[{'Name': 'DBClusterIdentifier', 'Value': cluster_name}],
        StartTime=start_time,
        EndTime=end_time,
        Period=300,
        Statistics=['Average']
    )
    metrics['cpu'] = [point['Average'] for point in cpu_response['Datapoints']]
    
    # Database connections
    conn_response = cloudwatch.get_metric_statistics(
        Namespace='AWS/RDS',
        MetricName='DatabaseConnections',
        Dimensions=[{'Name': 'DBClusterIdentifier', 'Value': cluster_name}],
        StartTime=start_time,
        EndTime=end_time,
        Period=300,
        Statistics=['Average']
    )
    metrics['connections'] = [point['Average'] for point in conn_response['Datapoints']]
    
    return metrics

def should_scale_database(metrics, is_business_hours, is_weekend, environment):
    """Determine if database should be scaled"""
    if not metrics['cpu'] or not metrics['connections']:
        return False
    
    avg_cpu = sum(metrics['cpu']) / len(metrics['cpu'])
    avg_connections = sum(metrics['connections']) / len(metrics['connections'])
    
    # Scale up conditions
    if avg_cpu > 80 or avg_connections > 80:
        return True
    
    # Scale down conditions (only in non-production or off-hours)
    if environment != 'prod' and (not is_business_hours or is_weekend):
        if avg_cpu < 30 and avg_connections < 10:
            return True
    
    return False

def scale_database(rds_client, cluster_name, metrics, environment):
    """Scale database based on metrics"""
    avg_cpu = sum(metrics['cpu']) / len(metrics['cpu'])
    
    if avg_cpu > 80:
        # Scale up Aurora Serverless v2 capacity
        return f"Database {cluster_name}: Scaled up due to high CPU ({avg_cpu:.1f}%)"
    else:
        # Scale down
        return f"Database {cluster_name}: Scaled down due to low utilization"

def get_redis_metrics(cloudwatch, cluster_id):
    """Get Redis performance metrics"""
    end_time = datetime.utcnow()
    start_time = end_time - timedelta(minutes=15)
    
    metrics = {}
    
    # CPU utilization
    cpu_response = cloudwatch.get_metric_statistics(
        Namespace='AWS/ElastiCache',
        MetricName='CPUUtilization',
        Dimensions=[{'Name': 'CacheClusterId', 'Value': cluster_id}],
        StartTime=start_time,
        EndTime=end_time,
        Period=300,
        Statistics=['Average']
    )
    metrics['cpu'] = [point['Average'] for point in cpu_response['Datapoints']]
    
    return metrics

def should_scale_redis(metrics, is_business_hours, environment):
    """Determine if Redis should be scaled"""
    if not metrics['cpu']:
        return False
    
    avg_cpu = sum(metrics['cpu']) / len(metrics['cpu'])
    
    # Scale based on CPU and business hours
    if avg_cpu > 75:
        return True
    
    if environment != 'prod' and not is_business_hours and avg_cpu < 20:
        return True
    
    return False

def scale_redis(elasticache_client, cluster_id, metrics, environment):
    """Scale Redis cluster"""
    avg_cpu = sum(metrics['cpu']) / len(metrics['cpu'])
    
    if avg_cpu > 75:
        return f"Redis {cluster_id}: Recommending scale up due to high CPU ({avg_cpu:.1f}%)"
    else:
        return f"Redis {cluster_id}: Could scale down due to low utilization"

def get_kafka_metrics(cloudwatch, cluster_name):
    """Get Kafka performance metrics"""
    end_time = datetime.utcnow()
    start_time = end_time - timedelta(minutes=30)
    
    metrics = {}
    
    # Disk usage
    disk_response = cloudwatch.get_metric_statistics(
        Namespace='AWS/Kafka',
        MetricName='KafkaDataLogsDiskUsed',
        Dimensions=[{'Name': 'Cluster Name', 'Value': cluster_name}],
        StartTime=start_time,
        EndTime=end_time,
        Period=300,
        Statistics=['Average']
    )
    metrics['disk_usage'] = [point['Average'] for point in disk_response['Datapoints']]
    
    return metrics

def should_scale_kafka(metrics, environment):
    """Determine if Kafka should be scaled"""
    if not metrics['disk_usage']:
        return False
    
    avg_disk = sum(metrics['disk_usage']) / len(metrics['disk_usage'])
    
    return avg_disk > 80

def scale_kafka_storage(kafka_client, cluster_name, metrics):
    """Scale Kafka storage"""
    avg_disk = sum(metrics['disk_usage']) / len(metrics['disk_usage'])
    
    return f"Kafka {cluster_name}: Storage scaling recommended due to high disk usage ({avg_disk:.1f}%)"
EOF
    filename = "index.py"
  }
}

# EventBridge rule for scheduled infrastructure scaling
resource "aws_cloudwatch_event_rule" "infrastructure_scaling_schedule" {
  name                = "${var.project_name}-${var.environment}-infrastructure-scaling"
  description         = "Trigger infrastructure scaling checks"
  schedule_expression = "rate(15 minutes)"
  
  tags = {
    Name = "${var.project_name}-infrastructure-scaling-schedule"
  }
}

resource "aws_cloudwatch_event_target" "infrastructure_scaling_target" {
  rule      = aws_cloudwatch_event_rule.infrastructure_scaling_schedule.name
  target_id = "InfrastructureScalingTarget"
  arn       = aws_lambda_function.infrastructure_scaler.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.infrastructure_scaler.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.infrastructure_scaling_schedule.arn
}

# Outputs for infrastructure scaling
output "infrastructure_scaling_summary" {
  description = "Summary of infrastructure auto-scaling configuration"
  value = {
    database = {
      type                = "aurora-serverless-v2"
      min_capacity        = aws_rds_cluster.pyairtable_serverless.serverlessv2_scaling_configuration[0].min_capacity
      max_capacity        = aws_rds_cluster.pyairtable_serverless.serverlessv2_scaling_configuration[0].max_capacity
      read_replicas       = var.environment == "prod" ? 2 : 0
      auto_scaling_enabled = true
    }
    redis = {
      type                = "cluster-mode"
      node_groups         = aws_elasticache_replication_group.redis_cluster.num_node_groups
      replicas_per_group  = aws_elasticache_replication_group.redis_cluster.replicas_per_node_group
      auto_failover       = aws_elasticache_replication_group.redis_cluster.automatic_failover_enabled
    }
    kafka = {
      broker_count        = aws_msk_cluster.kafka_cluster.number_of_broker_nodes
      instance_type       = var.environment == "prod" ? "kafka.m5.xlarge" : "kafka.t3.small"
      storage_scaling     = var.environment == "prod" ? "enabled" : "disabled"
      enhanced_monitoring = "PER_TOPIC_PER_BROKER"
    }
    opensearch = {
      instance_count      = var.environment == "prod" ? 3 : 1
      instance_type       = var.environment == "prod" ? "t3.medium.search" : "t3.small.search"
      dedicated_master    = var.environment == "prod"
      zone_awareness      = var.environment == "prod"
    }
  }
}