# Replace REPLACE_ACCOUNT_ID with your 12-digit AWS account ID before running
# terraform init. The bucket and DynamoDB table must be created first via
# terraform/bootstrap/.
terraform {
  backend "s3" {
    bucket         = "starflix-tfstate-REPLACE_ACCOUNT_ID-us-east-1"
    key            = "dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "starflix-tfstate-locks"
    encrypt        = true
  }
}
