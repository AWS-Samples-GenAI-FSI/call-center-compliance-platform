# AnyCompany Compliance Platform - Terraform Configuration

This directory contains the Terraform configuration to deploy the AnyCompany Compliance Platform infrastructure, converted from the original CloudFormation template.

## Files Structure

```
├── main.tf                    # Main infrastructure (VPC, S3, DynamoDB)
├── lambda.tf                  # Lambda functions and IAM roles
├── api_gateway.tf             # API Gateway configuration
├── cognito_ecs.tf             # Cognito, ECS, and ALB configuration
├── notifications.tf           # S3 notifications, WAF, and CodeBuild
├── terraform.tfvars.example   # Example variables file
└── TERRAFORM.md               # This documentation
```

## Prerequisites

1. **Terraform installed** (version >= 1.0)
2. **AWS CLI configured** with appropriate credentials
3. **Lambda function code** - The current configuration uses placeholder code

## Deployment Steps

### 1. Initialize Terraform
```bash
terraform init
```

### 2. Configure Variables
```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your specific values
```

### 3. Plan Deployment
```bash
terraform plan
```

### 4. Deploy Infrastructure
```bash
terraform apply
```

## Important Notes

### Lambda Functions
The current Terraform configuration includes placeholder Lambda function code. You need to:

1. Extract the actual Lambda function code from your CloudFormation template
2. Create proper zip files for each function:
   - `api_function.zip`
   - `processor_function.zip` 
   - `transcription_complete_function.zip`

### ECS Deployment
Set `deploy_ecs = false` initially. After building and pushing your Docker image to ECR, set `deploy_ecs = true` and run `terraform apply` again.

### Missing Components
Some CloudFormation features that need manual implementation:

1. **Rules Seeder Lambda** - Custom resource to populate DynamoDB rules
2. **Cognito User Creator Lambda** - Custom resource to create demo users
3. **S3 Notification Custom Resources** - Some complex S3 notifications

## Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `environment` | Environment name | `prod` |
| `aws_region` | AWS region | `us-east-1` |
| `allowed_ip` | IP address allowed to access the application | `136.57.32.30/32` |
| `deploy_ecs` | Whether to deploy ECS service | `false` |

## Outputs

After deployment, Terraform will output:
- API Gateway endpoint
- S3 bucket names
- DynamoDB table names
- Application Load Balancer URL

## Migration from CloudFormation

If you're migrating from the existing CloudFormation stack:

1. **Export data** from existing DynamoDB tables
2. **Backup S3 buckets** 
3. **Import existing resources** using `terraform import` where possible
4. **Update DNS/routing** to point to new infrastructure

## Cleanup

To destroy all resources:
```bash
terraform destroy
```

**Warning**: This will delete all data. Ensure you have backups before running destroy.

## Differences from CloudFormation

1. **Simplified structure** - Split into logical files
2. **Variables** - More flexible configuration
3. **Missing custom resources** - Some Lambda-based custom resources need manual implementation
4. **State management** - Terraform state file needs to be managed (consider remote state)

## Next Steps

1. Implement missing Lambda function code
2. Add custom resources for rules seeding and user creation
3. Set up remote state backend (S3 + DynamoDB)
4. Add proper CI/CD pipeline for Terraform deployments