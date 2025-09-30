# Terraform Infrastructure

This directory contains the Terraform configuration for the AnyCompany Compliance Platform.

## Quick Start

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
./deploy-terraform.sh
```

## Files

- `main.tf` - Core infrastructure (VPC, S3, DynamoDB)
- `lambda.tf` - Lambda functions and IAM
- `api_gateway.tf` - API Gateway configuration
- `cognito_ecs.tf` - Cognito, ECS, ALB setup
- `notifications.tf` - S3 notifications, WAF, CodeBuild
- `aws_services.tf` - AWS service configurations
- `deploy-terraform.sh` - Deployment script
- `TERRAFORM.md` - Detailed documentation

## Architecture

Creates 75+ AWS resources including:
- VPC with public/private subnets
- S3 buckets for audio processing
- Lambda functions for compliance processing
- API Gateway for REST endpoints
- Cognito for authentication
- ECS for containerized frontend
- SQS for bulk processing
- WAF for security

See `TERRAFORM.md` for complete documentation.