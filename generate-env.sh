#!/bin/bash

# Script to generate .env file content from Terraform outputs
# Usage: ./generate-env.sh
# Outputs .env format to stdout (can be redirected: ./generate-env.sh > .env)

set -e

# Check if terraform is initialized
if ! terraform output &>/dev/null; then
    echo "Error: Terraform not initialized or no outputs available. Run 'terraform init' and 'terraform apply' first." >&2
    exit 1
fi

# Get Terraform outputs
SES_BUCKET_NAME=$(terraform output -raw s3_bucket_name 2>/dev/null || echo "")
SES_S3_ACCESS_ROLE_ARN=$(terraform output -raw s3_access_role_arn 2>/dev/null || echo "")
SES_SUBDOMAIN=$(terraform output -raw subdomain_fqdn 2>/dev/null || echo "")

# Validate outputs
if [ -z "$SES_BUCKET_NAME" ] || [ -z "$SES_S3_ACCESS_ROLE_ARN" ] || [ -z "$SES_SUBDOMAIN" ]; then
    echo "Error: Failed to retrieve one or more Terraform outputs." >&2
    echo "Make sure you have run 'terraform apply' and the outputs are available." >&2
    exit 1
fi

# Get AWS region
# Try to get from terraform.tfvars first
if [ -f "terraform.tfvars" ]; then
    AWS_REGION=$(awk '/^[[:space:]]*region[[:space:]]*=/ {gsub(/^[[:space:]]*region[[:space:]]*=[[:space:]]*["'\'']?/, ""); gsub(/["'\'']?[[:space:]]*$/, ""); print}' terraform.tfvars)
fi

# If not found in tfvars, try to get from terraform show
if [ -z "$AWS_REGION" ]; then
    AWS_REGION=$(terraform show -json 2>/dev/null | jq -r '.values.root_module.provider_configs.aws.expressions.region.constant_value // empty' 2>/dev/null || echo "")
fi

# If still not found, try to get from terraform console
if [ -z "$AWS_REGION" ]; then
    AWS_REGION=$(echo 'var.region' | terraform console 2>/dev/null | tr -d '"' || echo "")
fi

# If still not found, use default from variables.tf
if [ -z "$AWS_REGION" ]; then
    AWS_REGION="us-east-2"
    echo "Warning: Could not determine AWS region from Terraform. Using default: $AWS_REGION" >&2
fi

# Print .env format to stdout
cat << EOF
SES_BUCKET_NAME=$SES_BUCKET_NAME
SES_S3_ACCESS_ROLE_ARN=$SES_S3_ACCESS_ROLE_ARN
SES_SUBDOMAIN=$SES_SUBDOMAIN
AWS_REGION=$AWS_REGION
EOF
