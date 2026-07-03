terraform {
  required_version = "~> 1.15.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"

      # aws            → regional cert for the ALB (aws_region)
      # aws.us_east_1  → cert for CloudFront (must be us-east-1)
      configuration_aliases = [aws.us_east_1]
    }
  }
}
