# Storage Module for PyAirtable EKS Infrastructure
# EBS CSI Driver, EFS, and backup strategies

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20"
    }
  }
}

locals {
  name = "${var.project_name}-${var.environment}"
}

# KMS Key for EFS encryption
resource "aws_kms_key" "efs" {
  count = var.enable_efs ? 1 : 0

  description             = "EFS Encryption Key for ${var.cluster_name}"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = merge(var.tags, {
    Name = "${local.name}-efs-encryption-key"
  })
}

resource "aws_kms_alias" "efs" {
  count = var.enable_efs ? 1 : 0

  name          = "alias/${local.name}-efs-encryption-key"
  target_key_id = aws_kms_key.efs[0].key_id
}

# EFS File System
resource "aws_efs_file_system" "main" {
  count = var.enable_efs ? 1 : 0

  creation_token   = "${local.name}-efs"
  performance_mode = var.efs_performance_mode
  throughput_mode  = var.efs_throughput_mode
  encrypted        = true
  kms_key_id       = aws_kms_key.efs[0].arn

  # Provisioned throughput (only if throughput_mode is provisioned)
  dynamic "provisioned_throughput_in_mibps" {
    for_each = var.efs_throughput_mode == "provisioned" ? [var.efs_provisioned_throughput] : []
    content {
      provisioned_throughput_in_mibps = provisioned_throughput_in_mibps.value
    }
  }

  # Lifecycle policy for cost optimization
  lifecycle_policy {
    transition_to_ia                    = var.efs_transition_to_ia
    transition_to_primary_storage_class = var.efs_transition_to_primary_storage_class
  }

  tags = merge(var.tags, {
    Name = "${local.name}-efs"
  })
}

# EFS Mount Targets
resource "aws_efs_mount_target" "main" {
  count = var.enable_efs ? length(var.subnet_ids) : 0

  file_system_id  = aws_efs_file_system.main[0].id
  subnet_id       = var.subnet_ids[count.index]
  security_groups = var.security_group_ids

  depends_on = [aws_efs_file_system.main]
}

# EFS Access Points for different workloads
resource "aws_efs_access_point" "application_data" {
  count = var.enable_efs ? 1 : 0

  file_system_id = aws_efs_file_system.main[0].id

  posix_user {
    gid = 1000
    uid = 1000
  }

  root_directory {
    path = "/application-data"
    creation_info {
      owner_gid   = 1000
      owner_uid   = 1000
      permissions = "0755"
    }
  }

  tags = merge(var.tags, {
    Name = "${local.name}-efs-application-data"
  })
}

resource "aws_efs_access_point" "shared_storage" {
  count = var.enable_efs ? 1 : 0

  file_system_id = aws_efs_file_system.main[0].id

  posix_user {
    gid = 2000
    uid = 2000
  }

  root_directory {
    path = "/shared-storage"
    creation_info {
      owner_gid   = 2000
      owner_uid   = 2000
      permissions = "0755"
    }
  }

  tags = merge(var.tags, {
    Name = "${local.name}-efs-shared-storage"
  })
}

# Kubernetes Storage Classes
resource "kubernetes_storage_class" "gp3" {
  count = var.enable_ebs_csi_driver ? 1 : 0

  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = {
    type      = "gp3"
    encrypted = "true"
    fsType    = "ext4"
  }
}

resource "kubernetes_storage_class" "gp3_retain" {
  count = var.enable_ebs_csi_driver ? 1 : 0

  metadata {
    name = "gp3-retain"
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Retain"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = {
    type      = "gp3"
    encrypted = "true"
    fsType    = "ext4"
  }
}

resource "kubernetes_storage_class" "efs" {
  count = var.enable_efs ? 1 : 0

  metadata {
    name = "efs"
  }

  storage_provisioner = "efs.csi.aws.com"
  volume_binding_mode = "Immediate"

  parameters = {
    provisioningMode = "efs-ap"
    fileSystemId     = aws_efs_file_system.main[0].id
    directoryPerms   = "0755"
  }
}

# Kubernetes VolumeSnapshotClass for backups
resource "kubernetes_manifest" "volume_snapshot_class_ebs" {
  count = var.enable_ebs_csi_driver && var.enable_automated_backups ? 1 : 0

  manifest = {
    apiVersion = "snapshot.storage.k8s.io/v1"
    kind       = "VolumeSnapshotClass"
    metadata = {
      name = "ebs-csi-snapshots"
    }
    driver         = "ebs.csi.aws.com"
    deletionPolicy = "Delete"
    parameters = {
      encrypted = "true"
    }
  }
}

# EFS Backup Configuration
resource "aws_efs_backup_policy" "main" {
  count = var.enable_efs && var.enable_automated_backups ? 1 : 0

  file_system_id = aws_efs_file_system.main[0].id

  backup_policy {
    status = "ENABLED"
  }
}

# AWS Backup Vault for EFS and EBS snapshots
resource "aws_backup_vault" "main" {
  count = var.enable_automated_backups ? 1 : 0

  name        = "${local.name}-backup-vault"
  kms_key_arn = aws_kms_key.backup[0].arn

  tags = var.tags
}

# KMS Key for backup encryption
resource "aws_kms_key" "backup" {
  count = var.enable_automated_backups ? 1 : 0

  description             = "Backup Encryption Key for ${var.cluster_name}"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = merge(var.tags, {
    Name = "${local.name}-backup-encryption-key"
  })
}

resource "aws_kms_alias" "backup" {
  count = var.enable_automated_backups ? 1 : 0

  name          = "alias/${local.name}-backup-encryption-key"
  target_key_id = aws_kms_key.backup[0].key_id
}

# IAM Role for AWS Backup
resource "aws_iam_role" "backup" {
  count = var.enable_automated_backups ? 1 : 0

  name = "${local.name}-backup-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "backup.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "backup" {
  count = var.enable_automated_backups ? 1 : 0

  role       = aws_iam_role.backup[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

# AWS Backup Plan
resource "aws_backup_plan" "main" {
  count = var.enable_automated_backups ? 1 : 0

  name = "${local.name}-backup-plan"

  rule {
    rule_name         = "daily_backups"
    target_vault_name = aws_backup_vault.main[0].name
    schedule          = "cron(0 2 ? * * *)" # Daily at 2 AM

    lifecycle {
      cold_storage_after = 30
      delete_after       = var.backup_retention_days
    }

    recovery_point_tags = merge(var.tags, {
      BackupPlan = "${local.name}-backup-plan"
    })
  }

  rule {
    rule_name         = "weekly_backups"
    target_vault_name = aws_backup_vault.main[0].name
    schedule          = "cron(0 3 ? * SUN *)" # Weekly on Sunday at 3 AM

    lifecycle {
      cold_storage_after = 30
      delete_after       = var.backup_retention_days * 4 # Keep weekly backups 4x longer
    }

    recovery_point_tags = merge(var.tags, {
      BackupPlan = "${local.name}-backup-plan"
      BackupType = "weekly"
    })
  }

  tags = var.tags
}

# Backup Selection for EFS
resource "aws_backup_selection" "efs" {
  count = var.enable_efs && var.enable_automated_backups ? 1 : 0

  iam_role_arn = aws_iam_role.backup[0].arn
  name         = "${local.name}-efs-backup-selection"
  plan_id      = aws_backup_plan.main[0].id

  resources = [aws_efs_file_system.main[0].arn]

  condition {
    string_equals {
      key   = "aws:ResourceTag/Environment"
      value = var.environment
    }
  }
}

# CloudWatch Alarms for storage monitoring
resource "aws_cloudwatch_metric_alarm" "efs_burst_credit_balance" {
  count = var.enable_efs ? 1 : 0

  alarm_name          = "${local.name}-efs-burst-credit-balance-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "BurstCreditBalance"
  namespace           = "AWS/EFS"
  period              = "300"
  statistic           = "Average"
  threshold           = "1000000000" # 1 billion bytes
  alarm_description   = "This metric monitors EFS burst credit balance"
  alarm_actions       = var.sns_topic_arn != null ? [var.sns_topic_arn] : []

  dimensions = {
    FileSystemId = aws_efs_file_system.main[0].id
  }

  tags = var.tags
}

# EBS Volume Snapshots for critical volumes (manual backup strategy)
resource "aws_ebs_snapshot" "manual_snapshot" {
  count = length(var.manual_snapshot_volume_ids)

  volume_id   = var.manual_snapshot_volume_ids[count.index]
  description = "Manual snapshot for ${local.name} volume ${count.index}"

  tags = merge(var.tags, {
    Name       = "${local.name}-manual-snapshot-${count.index}"
    VolumeId   = var.manual_snapshot_volume_ids[count.index]
    SnapshotType = "manual"
  })
}

# Data Lifecycle Manager for automated EBS snapshots
resource "aws_dlm_lifecycle_policy" "ebs_snapshots" {
  count = var.enable_automated_backups ? 1 : 0

  description        = "EBS Snapshot Lifecycle Policy for ${local.name}"
  execution_role_arn = aws_iam_role.dlm[0].arn
  state              = "ENABLED"

  policy_details {
    resource_types   = ["VOLUME"]
    schedule {
      name = "Daily Snapshots"
      
      create_rule {
        interval      = 24
        interval_unit = "HOURS"
        times         = ["02:00"]
      }

      retain_rule {
        count = var.backup_retention_days
      }

      tags_to_add = merge(var.tags, {
        SnapshotCreator = "DLM"
        Environment     = var.environment
      })
    }

    target_tags = {
      Environment = var.environment
      Project     = var.project_name
    }
  }

  tags = var.tags
}

# IAM Role for Data Lifecycle Manager
resource "aws_iam_role" "dlm" {
  count = var.enable_automated_backups ? 1 : 0

  name = "${local.name}-dlm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "dlm.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "dlm" {
  count = var.enable_automated_backups ? 1 : 0

  role       = aws_iam_role.dlm[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSDataLifecycleManagerServiceRole"
}