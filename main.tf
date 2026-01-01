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
  region = var.region
}

locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
  }
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
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "emails" {
  bucket = aws_s3_bucket.emails.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_sns_topic" "s3_events" {
  name = "${var.project_tag}-topic"
  tags = local.common_tags
}

resource "aws_sqs_queue" "dlq" {
  name                       = "${var.project_tag}-dlq"
  message_retention_seconds  = 1209600
  visibility_timeout_seconds = 60
  tags                       = local.common_tags
}

resource "aws_sqs_queue" "events_queue" {
  name                       = "${var.project_tag}-queue"
  visibility_timeout_seconds = 60
  message_retention_seconds  = 1209600
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

resource "aws_ses_receipt_rule_set" "main" {
  rule_set_name = "${var.project_tag}-rule-set"
}

resource "aws_ses_active_receipt_rule_set" "main" {
  rule_set_name = aws_ses_receipt_rule_set.main.rule_set_name
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
      Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:CopyObject"],
      Resource = ["${aws_s3_bucket.emails.arn}/*"]
    }]
  })
}

resource "aws_lambda_function" "move_to_recipient_folder" {
  function_name    = "${var.project_tag}-move"
  role             = aws_iam_role.lambda_role.arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  timeout          = 30
  environment {
    variables = {
      BUCKET = aws_s3_bucket.emails.bucket
      PREFIX = "incoming/"
    }
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
  rule_set_name = aws_ses_receipt_rule_set.main.rule_set_name
  enabled       = true
  scan_enabled  = true
  recipients    = [var.subdomain_fqdn]
  tls_policy    = "Optional"

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
    aws_lambda_function.move_to_recipient_folder
  ]
}
