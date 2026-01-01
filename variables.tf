variable "region" {
  description = "AWS region that supports SES Receiving (us-east-1, us-east-2, us-west-2, eu-west-1)"
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
