bucket         = "${bucket_name}"
key            = "environments/${workspace}/terraform.tfstate"
region         = "${region}"
encrypt        = true
dynamodb_table = "${dynamodb_table}"
kms_key_id     = "${kms_key_id}"