# Bootstrap Outputs

output "terraform_state_bucket" {
  description = "Name of the Terraform state S3 bucket"
  value       = aws_s3_bucket.terraform_state.bucket
}

output "terraform_state_bucket_arn" {
  description = "ARN of the Terraform state S3 bucket"
  value       = aws_s3_bucket.terraform_state.arn
}

output "terraform_state_lock_table" {
  description = "Name of the Terraform state lock DynamoDB table"
  value       = aws_dynamodb_table.terraform_state_lock.name
}

output "terraform_state_lock_table_arn" {
  description = "ARN of the Terraform state lock DynamoDB table"
  value       = aws_dynamodb_table.terraform_state_lock.arn
}

output "terraform_state_kms_key_id" {
  description = "ID of the KMS key for Terraform state encryption"
  value       = aws_kms_key.terraform_state.key_id
}

output "terraform_state_kms_key_arn" {
  description = "ARN of the KMS key for Terraform state encryption"
  value       = aws_kms_key.terraform_state.arn
}

output "terraform_state_policy_arn" {
  description = "ARN of the IAM policy for Terraform state access"
  value       = aws_iam_policy.terraform_state_policy.arn
}

output "backend_config_file" {
  description = "Path to the generated backend config file"
  value       = local_file.backend_config.filename
}

output "workspace_backend_configs" {
  description = "Paths to workspace-specific backend config files"
  value       = { for k, v in local_file.workspace_backend_configs : k => v.filename }
}

# Configuration snippets for easy copy-paste
output "backend_configuration" {
  description = "Backend configuration for terraform block"
  value = {
    bucket         = aws_s3_bucket.terraform_state.bucket
    key            = "terraform.tfstate"
    region         = var.aws_region
    encrypt        = true
    dynamodb_table = aws_dynamodb_table.terraform_state_lock.name
    kms_key_id     = aws_kms_key.terraform_state.arn
  }
}

output "next_steps" {
  description = "Next steps after bootstrap"
  value = <<-EOT
    Bootstrap completed successfully! 

    Next steps:
    1. Configure your main terraform configuration to use this backend:
       
       terraform {
         backend "s3" {
           bucket         = "${aws_s3_bucket.terraform_state.bucket}"
           key            = "environments/ENVIRONMENT/terraform.tfstate"
           region         = "${var.aws_region}"
           encrypt        = true
           dynamodb_table = "${aws_dynamodb_table.terraform_state_lock.name}"
           kms_key_id     = "${aws_kms_key.terraform_state.arn}"
         }
       }

    2. Initialize your main terraform configuration:
       terraform init -backend-config=backend-config.hcl

    3. Create workspaces for each environment:
       terraform workspace new dev
       terraform workspace new staging
       terraform workspace new prod

    4. Switch to desired workspace and apply:
       terraform workspace select dev
       terraform plan -var-file=environments/dev.tfvars
       terraform apply -var-file=environments/dev.tfvars

    Backend config files generated:
    - backend-config.hcl (main config)
    - environments/*/backend.hcl (workspace-specific configs)
  EOT
}