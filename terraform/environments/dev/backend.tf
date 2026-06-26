# Replace 882282737240 with your 12-digit AWS account ID before running
# terraform init. The bucket and DynamoDB table must be created first via
# terraform/bootstrap/.
terraform {
  backend "s3" {
    bucket       = "starflix-tfstate-882282737240-ap-south-1"
    key          = "dev/terraform.tfstate"
    region       = "ap-south-1"
    use_lockfile = true
    encrypt      = true
  }
}
