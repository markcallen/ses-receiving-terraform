# TODO - Future Improvements

This document tracks future improvements and enhancements for the SES Receiving Terraform project.

## High Priority

### Documentation

- [ ] **Add Architecture Diagram to README**
  - Add ASCII/text diagram showing: SES → S3 → SNS → SQS + Lambda
  - Include data flow explanation

- [ ] **Expand README Troubleshooting Section**
  - Common issue: Emails not arriving (check MX records, SES verification, active rule set)
  - Common issue: Lambda not executing (check CloudWatch logs, permissions)
  - Add command to check rule set status: `aws ses describe-active-receipt-rule-set`
  - Add command to activate rule set: `aws ses set-active-receipt-rule-set --rule-set-name <name>`
  - Note about MX record DNS propagation time (can take up to 48 hours)

- [ ] **Add Security Considerations Section to README**
  - Note that TLS policy is "Optional" (consider making it "Require" for production)
  - Mention SES sandbox mode restrictions for new AWS accounts
  - Note that bucket has no lifecycle policy (emails are retained indefinitely)
  - Recommend setting up CloudWatch alarms for Lambda errors

- [ ] **Add Post-Deployment Steps to README**
  - How to test: Send email to subdomain and verify it arrives in S3
  - How to view emails: `aws s3 ls s3://<bucket>/ --recursive`
  - How to download an email: `aws s3 cp s3://<bucket>/<path> ./email.eml`
  - Verify Lambda execution in CloudWatch logs

- [ ] **Add Cost Estimate Section to README**
  - SES receiving: Free (first 1,000 emails/month, then $0.10/1,000)
  - S3 storage: ~$0.023/GB/month
  - Lambda: Free tier covers most use cases
  - SNS/SQS: Minimal costs for low volume

### Infrastructure

- [ ] **Add CloudWatch Log Group with Retention**

  ```hcl
  resource "aws_cloudwatch_log_group" "lambda_logs" {
    name              = "/aws/lambda/${aws_lambda_function.move_to_recipient_folder.function_name}"
    retention_in_days = 14  # Or make this a variable
    tags              = { Project = var.project_tag }
  }
  ```

- [ ] **Add More Outputs to outputs.tf**
  - Lambda function name (for easier CloudWatch access)
  - S3 bucket name (not just ARN)
  - CloudWatch log group path
  - Rule set activation command

- [ ] **Add Tags to IAM Roles and Policies**
  - Currently only some resources have the Project tag
  - Add `tags = { Project = var.project_tag }` to all IAM roles

### Configuration

- [ ] **Create terraform.tfvars.example**

  ```hcl
  # Copy this file to terraform.tfvars and fill in your values
  region         = "us-east-2"
  subdomain_fqdn = "mail.example.com"
  bucket_name    = "ses-inbound-example-com"
  project_tag    = "ses-receive-example"
  ```

- [ ] **Create .gitignore**
  ```
  *.tfstate
  *.tfstate.*
  .terraform/
  .terraform.lock.hcl
  terraform.tfvars
  lambda.zip
  response.json
  ```

## Medium Priority

### Lambda Improvements

- [ ] **Add Lambda Requirements File**
  - Create `lambda/requirements.txt` (even if empty for now)
  - Documents that boto3 is the only dependency (provided by Lambda runtime)

- [ ] **Add Lambda Unit Tests**
  - Create `lambda/test_handler.py` with pytest
  - Test cases:
    - Successful message processing
    - Missing event fields
    - S3 operation failures
    - Multiple recipients

- [ ] **Add Message Metadata to S3 Object Tags**
  - Tag objects with sender, subject, timestamp
  - Makes searching and organization easier
  - Example: `s3.put_object_tagging()` after copy

- [ ] **Handle Edge Cases in Lambda**
  - What if recipient email is invalid/contains special characters?
  - What if message_id is missing?
  - Consider sanitizing folder names

### Infrastructure Enhancements

- [ ] **Add S3 Lifecycle Policy (Optional)**
  - Make configurable via variable
  - Example: Archive to Glacier after 90 days, delete after 365 days

  ```hcl
  variable "email_retention_days" {
    description = "Days to retain emails (0 = forever)"
    type        = number
    default     = 0
  }
  ```

- [ ] **Make TLS Policy Configurable**
  - Add variable for `tls_policy` (Optional vs Require)
  - Default to "Require" for better security

- [ ] **Add More Configurable Variables**
  - `lambda_timeout` (currently hardcoded to 30)
  - `enable_bucket_versioning` (currently hardcoded to true)
  - `sqs_message_retention_days` (currently hardcoded to 14 days)
  - `sqs_visibility_timeout` (currently hardcoded to 60 seconds)

- [ ] **Add CloudWatch Alarms**
  - Alert on Lambda errors
  - Alert on DLQ messages
  - Alert on SES bounce rate (if applicable)

### Security

- [ ] **Add KMS Encryption for S3 (Optional)**
  - Currently using AES256 (SSE-S3)
  - Consider adding option for KMS encryption
  - Would allow more granular access control

- [ ] **Restrict S3 Bucket Policy Further**
  - Currently allows all SES in the account
  - Could restrict to specific SES rule set ARN

- [ ] **Add IAM Policy for Human Access**
  - Document how to grant developers read-only access to emails
  - Example IAM policy snippet in README

## Low Priority

### Developer Experience

- [ ] **Add Makefile**

  ```makefile
  .PHONY: init plan apply destroy fmt validate

  init:
      terraform init

  plan:
      terraform plan

  apply:
      terraform apply

  destroy:
      terraform destroy

  fmt:
      terraform fmt -recursive

  validate:
      terraform validate
  ```

- [ ] **Add Pre-commit Hooks**
  - Auto-format Terraform files
  - Validate Terraform syntax
  - Run security scanning (tfsec, checkov)

- [ ] **Add CI/CD Pipeline**
  - GitHub Actions workflow for terraform validate/plan
  - Automated testing if tests are added

### Advanced Features

- [ ] **Support Multiple Domains/Subdomains**
  - Make `subdomain_fqdn` accept a list
  - Create multiple SES rules if needed

- [ ] **Add Email Forwarding Option**
  - Lambda could optionally forward emails to another address
  - Add SES send permissions to Lambda role

- [ ] **Add Spam/Virus Scanning Integration**
  - Could integrate with third-party scanning service
  - Add SNS notification for blocked emails

- [ ] **Add S3 Event Notifications for Recipient Folders**
  - Allow downstream systems to process emails per-recipient
  - Would need separate SNS topics or filtering

### Documentation

- [ ] **Add Contributing Guide**
  - How to submit issues/PRs
  - Code style guidelines
  - Testing requirements

- [ ] **Add Examples Directory**
  - Example of processing emails from SQS
  - Example of reading emails from S3
  - Example Lambda function for forwarding

- [ ] **Add FAQ Section**
  - How to change from sandbox mode to production?
  - How to handle bounces and complaints?
  - What regions support SES receiving?
  - How much does this cost to run?

## Completed

- [x] Add `aws_lambda_permission` resource for SES to invoke Lambda
- [x] Add `source_code_hash` to Lambda function
- [x] Add error handling and logging to Lambda function
- [x] Remove hardcoded defaults from variables.tf (for user-specific values)
- [x] Add validation to bucket_name variable
- [x] Create AGENTS.md for AI coding assistants

---

## Notes

- This project currently does not use a remote Terraform backend. For team environments, consider:

  ```hcl
  terraform {
    backend "s3" {
      bucket = "my-terraform-state"
      key    = "ses-receiving/terraform.tfstate"
      region = "us-east-2"
      dynamodb_table = "terraform-locks"
      encrypt = true
    }
  }
  ```

- The Lambda function processes only the first record in the event. SES typically sends one email per invocation, but this should be verified/documented.

- Consider whether the SNS/SQS infrastructure is actually being used. If not, it could be removed or made optional via a variable.
