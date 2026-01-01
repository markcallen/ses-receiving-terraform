output "mx_record" {
  value = "10 inbound-smtp.${var.region}.amazonaws.com"
}

output "s3_bucket_arn" {
  value = aws_s3_bucket.emails.arn
}

output "sns_topic_arn" {
  value = aws_sns_topic.s3_events.arn
}

output "sqs_queue_url" {
  value = aws_sqs_queue.events_queue.id
}

output "ses_rule_arn" {
  value = aws_ses_receipt_rule.store_and_move.arn
}

output "subdomain_fqdn" {
  value = var.subdomain_fqdn
}

output "s3_bucket_name" {
  value = aws_s3_bucket.emails.id
}

output "lambda_function_name" {
  value = aws_lambda_function.move_to_recipient_folder.function_name
}

output "ses_receipt_rule_set_name" {
  description = "Name of the SES receipt rule set (use this to activate the rule set)"
  value       = aws_ses_receipt_rule_set.main.rule_set_name
}

output "ses_verification_token" {
  description = "TXT record value for SES domain verification"
  value       = aws_ses_domain_identity.main.verification_token
}

output "ses_dkim_tokens" {
  description = "CNAME records for DKIM verification (improves email deliverability)"
  value = [
    for token in aws_ses_domain_dkim.main.dkim_tokens : {
      name  = "${token}._domainkey.${var.subdomain_fqdn}"
      type  = "CNAME"
      value = "${token}.dkim.amazonses.com"
    }
  ]
}

output "dns_records_summary" {
  description = "All DNS records needed for SES"
  value       = <<-EOT

    DNS Records Required:

    1. MX Record (for receiving email):
       Type: MX
       Name: ${var.subdomain_fqdn}
       Value: 10 inbound-smtp.${var.region}.amazonaws.com

    2. TXT Record (for domain verification):
       Type: TXT
       Name: _amazonses.${var.subdomain_fqdn}
       Value: ${aws_ses_domain_identity.main.verification_token}

    3. DKIM CNAME Records (for email authentication - 3 records):
       ${join("\n       ", [for token in aws_ses_domain_dkim.main.dkim_tokens : "CNAME: ${token}._domainkey.${var.subdomain_fqdn} -> ${token}.dkim.amazonses.com"])}
  EOT
}

output "cloudwatch_log_group_name" {
  description = "CloudWatch Logs group name for Lambda function (use with 'aws logs tail')"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "rule_set_activation_command" {
  description = "AWS CLI command to manually activate the SES receipt rule set if needed"
  value       = "aws ses set-active-receipt-rule-set --rule-set-name ${aws_ses_receipt_rule_set.main.rule_set_name}"
}
