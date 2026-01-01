# SES Receiving Terraform

This Terraform configuration stands up an AWS SES inbound email pipeline: incoming messages for a subdomain are accepted by SES, written to an encrypted S3 bucket, optionally fanned out via SNS/SQS, and finally organized per-recipient by a Lambda function.

## What It Provisions

- Secure, versioned S3 bucket used as the landing zone for raw `.eml` files.
- SNS topic and SQS queue pair for event fan-out and downstream processing, including a DLQ.
- IAM roles and policies that grant SES write access and let the Lambda manipulate objects in the bucket.
- Lambda function (`lambda/handler.py`) that moves each message into a folder named after the recipient.
- SES receipt rule set and rule that trigger the S3 store action and Lambda invocation.

## Prerequisites

- Terraform `>= 1.6.0`
- AWS provider `>= 5.50`
- An SES-supported AWS region with inbound email receiving enabled.
- Access to manage DNS for the target domain (e.g., Route53 hosted zone, third-party DNS provider).

## Usage

1. Ensure your AWS credentials are configured (e.g., via `aws configure` or environment variables).
2. Copy `terraform.tfvars.example` to `terraform.tfvars` and fill in your values:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```
   Then edit `terraform.tfvars` with your specific configuration. The file is git-ignored and will not be committed.
3. Initialize and deploy:
   ```bash
   terraform init
   terraform apply
   ```

4. **Configure DNS records** - After the initial deployment, retrieve the required DNS records:
   ```bash
   terraform output dns_records_summary
   ```

   This will display all DNS records you need to create in your DNS provider. You must add:
   - **1 MX record** - Directs incoming email to AWS SES
   - **1 TXT record** - Verifies domain ownership with SES
   - **3 CNAME records** - Enables DKIM email authentication

5. **Add the DNS records** to your DNS provider (Route53, Cloudflare, etc.):
   - If using Route53, you can add these records via the AWS console or CLI
   - If using a third-party DNS provider, add them through their interface
   - DNS propagation typically takes 5-15 minutes but can take up to 48 hours

6. **Verify domain identity** - Check that SES has verified your domain:
   ```bash
   aws ses get-identity-verification-attributes --identities $(terraform output -raw subdomain_fqdn)
   ```

   Wait until the verification status shows `"Success"`. This usually takes a few minutes after DNS propagation.

7. **Verify the SES receipt rule set is active** (automatically activated by Terraform):
   ```bash
   aws ses describe-active-receipt-rule-set
   ```

   The active rule set name should match:
   ```bash
   terraform output -raw ses_receipt_rule_set_name
   ```

   If you need to manually activate it (e.g., after deactivation):
   ```bash
   aws ses set-active-receipt-rule-set --rule-set-name $(terraform output -raw ses_receipt_rule_set_name)
   ```

## Testing the Pipeline

After deployment and DNS propagation, verify the email pipeline is working:

1. **Set environment variables from Terraform outputs**:
   ```bash
   export SUBDOMAIN=$(terraform output -raw subdomain_fqdn)
   export BUCKET=$(terraform output -raw s3_bucket_name)
   export LAMBDA_NAME=$(terraform output -raw lambda_function_name)
   ```

2. **Send a test email** to `test@<your-subdomain>`:
   ```bash
   # Using the mail command (macOS/Linux)
   echo "This is a test message" | mail -s "Test Subject" test@$SUBDOMAIN

   # Or use any email client to send to test@$SUBDOMAIN
   ```

3. **List the S3 bucket contents** to verify the email was received:
   ```bash
   # View all objects in the bucket
   aws s3 ls s3://$BUCKET/ --recursive

   # Expected output shows files organized by recipient:
   # 2026-01-01 12:34:56    1234 test@yourdomain.com/abc123def456.eml
   ```

4. **Download and view a specific email file**:
   ```bash
   # Copy the email file to your local machine (replace MESSAGE_ID with actual value from step 3)
   aws s3 cp s3://$BUCKET/test@$SUBDOMAIN/MESSAGE_ID.eml ./test-email.eml

   # View the raw email content
   cat ./test-email.eml
   ```

5. **Check Lambda execution logs** (optional):
   ```bash
   # View recent Lambda logs to verify processing
   aws logs tail /aws/lambda/$LAMBDA_NAME --follow
   ```

**Note:** SES may take a few minutes to process incoming emails. If you don't see files immediately, wait 2-3 minutes and check again. Also ensure your AWS account is out of SES sandbox mode, or that the sender email is verified.

### Example `terraform.tfvars`

```hcl
region         = "us-east-2"
subdomain_fqdn = "app.markcallen.dev"
bucket_name    = "ses-inbound-app-markcallen-dev"
project_tag    = "ses-receive-app-markcallen-dev"
project        = "ses-inbound"
environment    = "dev"
```

## Inputs

| Variable         | Description                                        | Default                          |
| ---------------- | -------------------------------------------------- | -------------------------------- |
| `region`         | AWS region that supports SES receiving             | `us-east-2`                      |
| `subdomain_fqdn` | SES inbound subdomain (also used as the recipient) | `app.markcallen.dev`             |
| `bucket_name`    | Name of the S3 bucket storing inbound messages     | `ses-inbound-app-markcallen-dev` |
| `project_tag`    | Base tag applied to created resources              | `ses-receive-app-markcallen-dev` |

## Outputs

| Output          | Description                        |
| --------------- | ---------------------------------- |
| `mx_record`     | MX record value to publish         |
| `s3_bucket_arn` | ARN of the inbound email bucket    |
| `sns_topic_arn` | ARN of the SNS topic for S3 events |
| `sqs_queue_url` | URL of the primary SQS queue       |
| `ses_rule_arn`  | ARN of the SES receipt rule        |

## Lambda Behavior

The Lambda at `lambda/handler.py` copies each raw message from the `incoming/` prefix into a folder named after each recipient (`recipient@example.com/messageId.eml`) and deletes the original object. This keeps the bucket tidy while preserving message data per mailbox.

## Development

### Prerequisites

- [Terraform](https://www.terraform.io/downloads) >= 1.6.0
- [TFLint](https://github.com/terraform-linters/tflint) for Terraform linting
- [pre-commit](https://pre-commit.com/) for automated code quality checks
- AWS CLI configured with appropriate credentials
- Python 3.12 (for Lambda development)

### Setting Up Pre-Commit Hooks

This project uses pre-commit hooks to automatically check code quality before commits. The hooks run:
- General file checks (JSON, YAML validation, trailing whitespace, large files, private keys)
- Terraform formatting (`terraform fmt`)
- Terraform validation (`terraform validate`)
- TFLint checks (`terraform_tflint`)

1. **Install pre-commit** (if not already installed):
   ```bash
   # macOS
   brew install pre-commit

   # Linux/WSL
   pip install pre-commit

   # Windows
   pip install pre-commit
   ```

2. **Install the git hooks** in your local repository:
   ```bash
   pre-commit install
   ```

3. **Run hooks manually** on all files (optional, but recommended for first-time setup):
   ```bash
   pre-commit run --all-files
   ```

Once installed, the hooks will automatically run on `git commit`. If any hook fails, the commit will be blocked until you fix the issues.

**Manual execution:**
```bash
# Run on all files
pre-commit run --all-files

# Run on staged files only
pre-commit run

# Run a specific hook
pre-commit run terraform_fmt
```

### Setting Up TFLint

TFLint helps catch errors and enforce best practices in your Terraform code.

1. **Install TFLint** (if not already installed):
   ```bash
   # macOS
   brew install tflint

   # Linux
   curl -s https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | bash

   # Windows
   choco install tflint
   ```

2. **Initialize TFLint** (downloads required plugins):
   ```bash
   tflint --init
   ```

**Note:** TFLint is automatically run by pre-commit hooks if you've set them up (see above).

### Development Workflow

When modifying Terraform configuration files:

1. **Make your changes** to `.tf` files
2. **Format the code**:
   ```bash
   terraform fmt
   ```
3. **Run TFLint** to check for errors and best practices:
   ```bash
   tflint
   ```
4. **Validate the configuration**:
   ```bash
   terraform validate
   ```
5. **Review the execution plan**:
   ```bash
   terraform plan
   ```
6. **Apply changes** (if plan looks correct):
   ```bash
   terraform apply
   ```

**Important:** Always run `tflint` after modifying any `.tf` file before committing or applying changes.

### Modifying the Lambda Function

1. Edit `lambda/handler.py`
2. Test your changes locally if possible
3. Run `terraform apply` to deploy (automatically packages and uploads the Lambda)
4. Monitor logs for errors:
   ```bash
   aws logs tail /aws/lambda/$(terraform output -raw lambda_function_name) --follow
   ```

## Cleanup

To tear down all provisioned resources, run:

```bash
terraform destroy
```

Remember to empty the S3 bucket or enable `force_destroy` if you modify the configuration.
