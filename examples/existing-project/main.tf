terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.50"
    }
  }
}

provider "aws" {
  alias  = "ses_receiving"
  region = "us-east-2"
}

module "ses_receiving" {
  source = "../.."

  providers = {
    aws = aws.ses_receiving
  }

  region         = "us-east-2"
  subdomain_fqdn = "mail.example.com"
  bucket_name    = "example-mail-inbound-prod"
  project_tag    = "example-mail-prod"
  project        = "example"
  environment    = "prod"

  create_receipt_rule_set   = true
  activate_receipt_rule_set = false

  trusted_reader_principal_arns = [
    "arn:aws:iam::123456789012:role/playwright-tests"
  ]
}

output "ses_email_client_env" {
  value = {
    SES_BUCKET_NAME        = module.ses_receiving.s3_bucket_name
    SES_S3_ACCESS_ROLE_ARN = module.ses_receiving.s3_access_role_arn
    SES_SUBDOMAIN          = module.ses_receiving.subdomain_fqdn
    AWS_REGION             = module.ses_receiving.region
  }
}
