terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.50"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.0"
    }
  }
}

locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
  }

  receipt_rule_set_name = var.create_receipt_rule_set ? aws_ses_receipt_rule_set.main[0].rule_set_name : var.receipt_rule_set_name
  s3_sse_algorithm      = var.s3_kms_key_arn == null ? "AES256" : "aws:kms"
  receipt_rule_set_name_for_resource = (
    local.receipt_rule_set_name == null || trimspace(local.receipt_rule_set_name) == ""
    ? "invalid-receipt-rule-set-name"
    : local.receipt_rule_set_name
  )
  ses_from_address_for_resource = (
    var.ses_from_address == null || trimspace(var.ses_from_address) == ""
    ? "invalid@example.com"
    : var.ses_from_address
  )
  ses_sending_identity_arns = (
    length(var.ses_sending_identity_arns) > 0
    ? var.ses_sending_identity_arns
    : ["arn:aws:ses:${var.region}:${data.aws_caller_identity.me.account_id}:identity/${local.ses_from_address_for_resource}"]
  )
}

resource "aws_s3_bucket" "emails" {
  bucket = var.bucket_name
  tags   = local.common_tags
}

resource "aws_s3_bucket_public_access_block" "emails" {
  bucket                  = aws_s3_bucket.emails.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "emails" {
  bucket = aws_s3_bucket.emails.id
  versioning_configuration { status = var.enable_bucket_versioning ? "Enabled" : "Suspended" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "emails" {
  bucket = aws_s3_bucket.emails.id
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.s3_kms_key_arn
      sse_algorithm     = local.s3_sse_algorithm
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "emails" {
  count = var.email_retention_days > 0 ? 1 : 0

  bucket = aws_s3_bucket.emails.id

  rule {
    id     = "expire-emails"
    status = "Enabled"

    filter {}

    expiration {
      days = var.email_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = var.email_retention_days
    }
  }
}

resource "aws_sns_topic" "s3_events" {
  name = "${var.project_tag}-topic"
  tags = local.common_tags
}

resource "aws_sqs_queue" "dlq" {
  name                       = "${var.project_tag}-dlq"
  message_retention_seconds  = var.sqs_message_retention_seconds
  visibility_timeout_seconds = var.sqs_visibility_timeout_seconds
  tags                       = local.common_tags
}

resource "aws_sqs_queue" "events_queue" {
  name                       = "${var.project_tag}-queue"
  visibility_timeout_seconds = var.sqs_visibility_timeout_seconds
  message_retention_seconds  = var.sqs_message_retention_seconds
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 5
  })
  tags = local.common_tags
}

resource "aws_sqs_queue_policy" "allow_sns" {
  queue_url = aws_sqs_queue.events_queue.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Sid       = "Allow-SNS-SendMessage",
      Effect    = "Allow",
      Principal = { Service = "sns.amazonaws.com" },
      Action    = "sqs:SendMessage",
      Resource  = aws_sqs_queue.events_queue.arn,
      Condition = {
        ArnEquals = { "aws:SourceArn" = aws_sns_topic.s3_events.arn }
      }
    }]
  })
}

resource "aws_sns_topic_subscription" "sqs_sub" {
  topic_arn            = aws_sns_topic.s3_events.arn
  protocol             = "sqs"
  endpoint             = aws_sqs_queue.events_queue.arn
  raw_message_delivery = true
}

resource "aws_sns_topic_policy" "allow_s3" {
  arn = aws_sns_topic.s3_events.arn
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Sid       = "AllowS3Publish",
      Effect    = "Allow",
      Principal = { Service = "s3.amazonaws.com" },
      Action    = "SNS:Publish",
      Resource  = aws_sns_topic.s3_events.arn,
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.me.account_id
        },
        ArnLike = {
          "aws:SourceArn" = aws_s3_bucket.emails.arn
        }
      }
    }]
  })
}

data "aws_caller_identity" "me" {}

resource "aws_s3_bucket_notification" "notify" {
  bucket = aws_s3_bucket.emails.id
  topic {
    topic_arn = aws_sns_topic.s3_events.arn
    events    = ["s3:ObjectCreated:*"]
  }
  depends_on = [aws_sns_topic_policy.allow_s3]
}

resource "aws_ses_domain_identity" "main" {
  domain = var.subdomain_fqdn
}

resource "aws_ses_domain_dkim" "main" {
  domain = aws_ses_domain_identity.main.domain
}

resource "aws_ses_email_identity" "from_address" {
  count = var.create_ses_sending_user ? 1 : 0

  email = local.ses_from_address_for_resource

  lifecycle {
    precondition {
      condition     = var.ses_from_address == null ? false : trimspace(var.ses_from_address) != ""
      error_message = "Set ses_from_address when create_ses_sending_user is true."
    }
  }
}

resource "aws_ses_receipt_rule_set" "main" {
  count = var.create_receipt_rule_set ? 1 : 0

  rule_set_name = "${var.project_tag}-rule-set"
}

resource "aws_ses_active_receipt_rule_set" "main" {
  count = var.activate_receipt_rule_set ? 1 : 0

  rule_set_name = local.receipt_rule_set_name_for_resource

  lifecycle {
    precondition {
      condition     = local.receipt_rule_set_name == null ? false : trimspace(local.receipt_rule_set_name) != ""
      error_message = "Set create_receipt_rule_set = true or provide receipt_rule_set_name before activating a receipt rule set."
    }
  }
}

resource "aws_iam_role" "ses_s3_role" {
  name = "${var.project_tag}-ses-s3-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "ses.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
  tags = local.common_tags
}

resource "aws_iam_role_policy" "ses_s3_role_policy" {
  name = "${var.project_tag}-ses-s3-policy"
  role = aws_iam_role.ses_s3_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["s3:PutObject"],
        Resource = "${aws_s3_bucket.emails.arn}/*"
      },
      {
        Effect   = "Allow",
        Action   = ["sns:Publish"],
        Resource = aws_sns_topic.s3_events.arn
      }
    ]
  })
}

resource "aws_s3_bucket_policy" "allow_ses_put" {
  bucket = aws_s3_bucket.emails.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Sid       = "AllowSESPutObject",
      Effect    = "Allow",
      Principal = { Service = "ses.amazonaws.com" },
      Action    = "s3:PutObject",
      Resource  = "${aws_s3_bucket.emails.arn}/*",
      Condition = {
        StringEquals = {
          "aws:Referer" = data.aws_caller_identity.me.account_id
        }
      }
    }]
  })
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/lambda.zip"
}

resource "aws_iam_role" "lambda_role" {
  name = "${var.project_tag}-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "lambda.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_s3_rw" {
  name = "${var.project_tag}-lambda-s3-rw"
  role = aws_iam_role.lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect   = "Allow",
      Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
      Resource = ["${aws_s3_bucket.emails.arn}/*"]
    }]
  })
}

resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${var.project_tag}-move"
  retention_in_days = var.log_retention_days
  tags              = local.common_tags
}

resource "aws_lambda_function" "move_to_recipient_folder" {
  function_name    = "${var.project_tag}-move"
  role             = aws_iam_role.lambda_role.arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  timeout          = var.lambda_timeout_seconds
  environment {
    variables = {
      BUCKET = aws_s3_bucket.emails.bucket
      PREFIX = "incoming/"
    }
  }
  tags       = local.common_tags
  depends_on = [aws_cloudwatch_log_group.lambda_logs]
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${var.project_tag}-lambda-errors"
  alarm_description   = "Lambda errors for SES inbound email organizer"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.ok_actions

  dimensions = {
    FunctionName = aws_lambda_function.move_to_recipient_folder.function_name
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "dlq_messages" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${var.project_tag}-dlq-messages"
  alarm_description   = "Messages visible in the SES inbound email DLQ"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Maximum"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.ok_actions

  dimensions = {
    QueueName = aws_sqs_queue.dlq.name
  }

  tags = local.common_tags
}

resource "aws_lambda_permission" "allow_ses" {
  statement_id   = "AllowExecutionFromSES"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.move_to_recipient_folder.function_name
  principal      = "ses.amazonaws.com"
  source_account = data.aws_caller_identity.me.account_id
}

resource "aws_ses_receipt_rule" "store_and_move" {
  name          = "${var.project_tag}-rule"
  rule_set_name = local.receipt_rule_set_name_for_resource
  enabled       = true
  scan_enabled  = true
  recipients    = [var.subdomain_fqdn]
  tls_policy    = var.tls_policy

  s3_action {
    bucket_name       = aws_s3_bucket.emails.bucket
    object_key_prefix = "incoming/"
    topic_arn         = aws_sns_topic.s3_events.arn
    position          = 1
    iam_role_arn      = aws_iam_role.ses_s3_role.arn
  }

  lambda_action {
    function_arn = aws_lambda_function.move_to_recipient_folder.arn
    position     = 2
  }

  depends_on = [
    aws_iam_role_policy.ses_s3_role_policy,
    aws_lambda_function.move_to_recipient_folder,
    aws_lambda_permission.allow_ses
  ]

  lifecycle {
    precondition {
      condition     = local.receipt_rule_set_name == null ? false : trimspace(local.receipt_rule_set_name) != ""
      error_message = "Set create_receipt_rule_set = true or provide receipt_rule_set_name."
    }
  }
}

# Convert user identifiers to ARNs and extract user names
locals {
  s3_access_user_arns = [
    for user in var.s3_access_iam_users : (
      startswith(user, "arn:aws:iam::") ? user : "arn:aws:iam::${data.aws_caller_identity.me.account_id}:user/${user}"
    )
  ]
  iam_user_names = [
    for user in var.s3_access_iam_users : (
      startswith(user, "arn:aws:iam::") ? split("/", user)[length(split("/", user)) - 1] : user
    )
  ]
  s3_access_trusted_principal_arns = distinct(concat(var.trusted_reader_principal_arns, local.s3_access_user_arns))
  s3_access_role_trust_principals = (
    length(var.s3_access_iam_groups) > 0 || length(local.s3_access_trusted_principal_arns) == 0
    ? ["arn:aws:iam::${data.aws_caller_identity.me.account_id}:root"]
    : local.s3_access_trusted_principal_arns
  )
}

# IAM role for users to assume to access S3 bucket
resource "aws_iam_role" "s3_access_role" {
  name = "${var.project_tag}-s3-access-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = local.s3_access_role_trust_principals
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
  tags = local.common_tags
}

resource "aws_iam_role_policy" "s3_access_role_policy" {
  name = "${var.project_tag}-s3-access-policy"
  role = aws_iam_role.s3_access_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.emails.arn,
          "${aws_s3_bucket.emails.arn}/*"
        ]
      }
    ]
  })
}

# IAM policies attached to users to allow them to assume the role
resource "aws_iam_user_policy" "s3_access_assume_role" {
  for_each = toset(local.iam_user_names)
  name     = "${var.project_tag}-assume-s3-access-role"
  user     = each.value
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "sts:AssumeRole"
        Resource = aws_iam_role.s3_access_role.arn
      }
    ]
  })
}

# IAM policies attached to groups to allow members to assume the role
resource "aws_iam_group_policy" "s3_access_assume_role" {
  for_each = toset(var.s3_access_iam_groups)
  name     = "${var.project_tag}-assume-s3-access-role"
  group    = each.value
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "sts:AssumeRole"
        Resource = aws_iam_role.s3_access_role.arn
      }
    ]
  })
}

# IAM user for SES sending (e.g., magic link emails from lynkgo-app)
resource "aws_iam_user" "ses_sending" {
  count = var.create_ses_sending_user ? 1 : 0

  name = "${var.project_tag}-ses-sending"
  path = "/"
  tags = local.common_tags
}

resource "aws_iam_user_policy" "ses_sending" {
  count = var.create_ses_sending_user ? 1 : 0

  name = "${var.project_tag}-ses-send-policy"
  user = aws_iam_user.ses_sending[0].name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ses:SendEmail", "ses:SendRawEmail"]
        Resource = local.ses_sending_identity_arns
      }
    ]
  })
}
