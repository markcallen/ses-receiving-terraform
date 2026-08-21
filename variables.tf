variable "region" {
  description = "AWS region that supports SES Receiving. Configure the AWS provider in the calling project; this value is also used for DNS output and optional SES sending identity ARNs."
  type        = string
  default     = "us-east-2"
}

variable "subdomain_fqdn" {
  description = "Subdomain for inbound mail (e.g., mail.example.com)"
  type        = string
}

variable "bucket_name" {
  description = "S3 bucket to store inbound emails (must be globally unique)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.bucket_name)) && length(var.bucket_name) >= 3 && length(var.bucket_name) <= 63
    error_message = "Bucket name must be 3-63 characters, lowercase letters, numbers, and hyphens only, and cannot start or end with a hyphen."
  }
}

variable "project_tag" {
  description = "Tag for grouping resources (used as prefix for resource names)"
  type        = string
}

variable "project" {
  description = "Project name for resource labeling"
  type        = string
}

variable "environment" {
  description = "Environment name (e.g., production, staging, dev)"
  type        = string
}

variable "log_retention_days" {
  description = "Number of days to retain Lambda CloudWatch logs (0 = never expire)"
  type        = number
  default     = 14

  validation {
    condition     = contains([0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch Logs retention value: 0 (never expire), 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, or 3653."
  }
}

variable "lambda_timeout_seconds" {
  description = "Lambda timeout in seconds for moving inbound emails into recipient folders."
  type        = number
  default     = 30

  validation {
    condition     = var.lambda_timeout_seconds >= 1 && var.lambda_timeout_seconds <= 900
    error_message = "lambda_timeout_seconds must be between 1 and 900."
  }
}

variable "sqs_message_retention_seconds" {
  description = "Number of seconds to retain SQS messages."
  type        = number
  default     = 1209600

  validation {
    condition     = var.sqs_message_retention_seconds >= 60 && var.sqs_message_retention_seconds <= 1209600
    error_message = "sqs_message_retention_seconds must be between 60 and 1209600."
  }
}

variable "sqs_visibility_timeout_seconds" {
  description = "SQS visibility timeout in seconds."
  type        = number
  default     = 60

  validation {
    condition     = var.sqs_visibility_timeout_seconds >= 0 && var.sqs_visibility_timeout_seconds <= 43200
    error_message = "sqs_visibility_timeout_seconds must be between 0 and 43200."
  }
}

variable "enable_bucket_versioning" {
  description = "Whether to enable versioning on the inbound email S3 bucket."
  type        = bool
  default     = true
}

variable "email_retention_days" {
  description = "Days to retain email objects in S3. Set 0 to retain indefinitely."
  type        = number
  default     = 0

  validation {
    condition     = var.email_retention_days >= 0
    error_message = "email_retention_days must be 0 or greater."
  }
}

variable "s3_kms_key_arn" {
  description = "Optional KMS key ARN for S3 server-side encryption. When null, SSE-S3 AES256 is used."
  type        = string
  default     = null
}

variable "enable_cloudwatch_alarms" {
  description = "Whether to create CloudWatch alarms for Lambda errors and DLQ depth."
  type        = bool
  default     = false
}

variable "alarm_actions" {
  description = "List of ARNs to notify when CloudWatch alarms enter ALARM state."
  type        = list(string)
  default     = []
}

variable "ok_actions" {
  description = "List of ARNs to notify when CloudWatch alarms return to OK state."
  type        = list(string)
  default     = []
}

variable "s3_access_iam_users" {
  description = "List of IAM user ARNs or user names that should be granted access to assume the S3 bucket access role"
  type        = list(string)
  default     = []
}

variable "s3_access_iam_groups" {
  description = "List of IAM group names that should be granted access to assume the S3 bucket access role (policies will be attached to these groups)"
  type        = list(string)
  default     = []
}

variable "trusted_reader_principal_arns" {
  description = "IAM principal ARNs, such as roles or users, trusted to assume the S3 bucket read role. Prefer this for existing Terraform projects."
  type        = list(string)
  default     = []
}

variable "create_receipt_rule_set" {
  description = "Whether to create a new SES receipt rule set. Set false to add the receipt rule to an existing rule set."
  type        = bool
  default     = true
}

variable "receipt_rule_set_name" {
  description = "Existing SES receipt rule set name to add the receipt rule to when create_receipt_rule_set is false."
  type        = string
  default     = null

  validation {
    condition     = var.receipt_rule_set_name == null ? true : trimspace(var.receipt_rule_set_name) != ""
    error_message = "receipt_rule_set_name must be null or a non-empty string."
  }
}

variable "activate_receipt_rule_set" {
  description = "Whether to make this receipt rule set active. SES allows one active receipt rule set per account/region, so this defaults to false for safer module use."
  type        = bool
  default     = false
}

variable "tls_policy" {
  description = "SES receipt rule TLS policy. Use Require for stricter inbound transport security or Optional for maximum deliverability."
  type        = string
  default     = "Optional"

  validation {
    condition     = contains(["Optional", "Require"], var.tls_policy)
    error_message = "tls_policy must be either Optional or Require."
  }
}

variable "create_ses_sending_user" {
  description = "Whether to create an IAM user that can send email through SES. Disabled by default because receiving and client reads do not require it."
  type        = bool
  default     = false
}

variable "ses_from_address" {
  description = "Email address to verify for outbound email when create_ses_sending_user is true."
  type        = string
  default     = null

  validation {
    condition     = var.ses_from_address == null ? true : trimspace(var.ses_from_address) != ""
    error_message = "ses_from_address must be null or a non-empty string."
  }
}

variable "ses_sending_identity_arns" {
  description = "SES identity ARNs that the optional sending user can send from. When empty, the module scopes sending to ses_from_address."
  type        = list(string)
  default     = []
}
