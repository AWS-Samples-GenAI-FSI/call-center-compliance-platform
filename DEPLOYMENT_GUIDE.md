# AnyCompany Call Center Compliance Platform - Deployment Guide

## 🚀 Quick Start (5 Minutes)

Deploy a complete AI-powered compliance validation platform with AWS Transcribe, Comprehend, and 43 pre-configured compliance rules.

### Prerequisites
- AWS CLI configured with appropriate permissions
- AWS account with sufficient limits for Lambda, DynamoDB, S3, ECS

### One-Command Deployment

```bash
git clone https://github.com/AWS-Samples-GenAI-FSI/call-center-compliance-platform.git
cd call-center-compliance-platform
./deploy.sh
```

## 📋 Step-by-Step Deployment

### Step 1: Clone Repository
```bash
git clone https://github.com/AWS-Samples-GenAI-FSI/call-center-compliance-platform.git
cd call-center-compliance-platform
```

### Step 2: Deploy Infrastructure
```bash
aws cloudformation create-stack \
  --stack-name anycompany-compliance \
  --template-body file://infrastructure.yaml \
  --capabilities CAPABILITY_IAM \
  --parameters ParameterKey=Environment,ParameterValue=prod
```

### Step 3: Wait for Stack Creation (10-15 minutes)
```bash
aws cloudformation wait stack-create-complete --stack-name anycompany-compliance
```

### Step 4: Upload Source Code
```bash
# Get source bucket name
SOURCE_BUCKET=$(aws cloudformation describe-stacks \
  --stack-name anycompany-compliance \
  --query 'Stacks[0].Outputs[?OutputKey==`SourceBucket`].OutputValue' \
  --output text)

# Create and upload source code
cd anycompany-compliance-react
zip -r ../anycompany-ui-source.zip . -x "node_modules/*" ".git/*"
cd ..
aws s3 cp anycompany-ui-source.zip s3://$SOURCE_BUCKET/source/
```

### Step 5: Build and Deploy React App
```bash
# Get CodeBuild project name
BUILD_PROJECT=$(aws cloudformation describe-stacks \
  --stack-name anycompany-compliance \
  --query 'Stacks[0].Outputs[?OutputKey==`CodeBuildProject`].OutputValue' \
  --output text)

# Start build
aws codebuild start-build --project-name $BUILD_PROJECT
```

### Step 6: Enable ECS Service (After Build Completes)
```bash
# Wait for build to complete (5-10 minutes)
aws cloudformation update-stack \
  --stack-name anycompany-compliance \
  --template-body file://infrastructure.yaml \
  --capabilities CAPABILITY_IAM \
  --parameters ParameterKey=Environment,ParameterValue=prod \
               ParameterKey=DeployECS,ParameterValue=true
```

### Step 7: Get Application URL
```bash
aws cloudformation describe-stacks \
  --stack-name anycompany-compliance \
  --query 'Stacks[0].Outputs[?OutputKey==`ApplicationURL`].OutputValue' \
  --output text
```

## 🔐 Access Information

### Demo Login Credentials
- **Usernames**: `compliancemanager`, `auditreviewer`, `qualityanalyst`
- **Password**: `AnyCompanyDemo2024!`

### API Endpoint
```bash
aws cloudformation describe-stacks \
  --stack-name anycompany-compliance \
  --query 'Stacks[0].Outputs[?OutputKey==`ApiEndpoint`].OutputValue' \
  --output text
```

## 📊 What Gets Deployed

### Core Infrastructure
- **VPC** with public/private subnets across 2 AZs
- **S3 Buckets** for audio input, transcripts, and entities
- **DynamoDB Tables** for calls and compliance rules
- **Lambda Functions** for processing and API
- **API Gateway** with CORS configuration
- **Cognito User Pool** with demo users

### AI/ML Services
- **AWS Transcribe** for audio-to-text conversion
- **AWS Comprehend** for entity extraction and PII detection
- **43 Pre-configured Rules** across 4 compliance categories

### Web Application
- **React TypeScript** frontend with authentication
- **ECS Fargate** container deployment
- **Application Load Balancer** with WAF protection
- **ECR Repository** for container images

## 🧪 Testing the Platform

### 1. Upload Test Audio Files
```bash
# Get input bucket name
INPUT_BUCKET=$(aws cloudformation describe-stacks \
  --stack-name anycompany-compliance \
  --query 'Stacks[0].Outputs[?OutputKey==`InputBucket`].OutputValue' \
  --output text)

# Upload sample audio files
aws s3 cp test-data/audio/ s3://$INPUT_BUCKET/audio/ --recursive
```

### 2. Upload Reference Data
```bash
# Upload master reference file
aws s3 cp test-data/master_reference.json s3://$INPUT_BUCKET/reference/
```

### 3. Monitor Processing
- Check DynamoDB `anycompany-calls-prod` table for processing status
- View CloudWatch logs for Lambda functions
- Access web dashboard to see results

## 📁 Project Structure

```
call-center-compliance-platform/
├── deploy.sh                    # One-command deployment script
├── infrastructure.yaml          # Complete CloudFormation template
├── DEPLOYMENT_GUIDE.md         # This file
├── anycompany-compliance-react/ # React frontend application
│   ├── src/App.tsx             # Main application component
│   ├── Dockerfile              # Container configuration
│   └── buildspec.yml           # CodeBuild configuration
├── lambda-functions/            # AWS Lambda source code
│   ├── api-function/           # REST API endpoints
│   └── transcription-handler/  # Processing functions
└── test-data/                  # Sample audio and reference files
    ├── audio/                  # Sample WAV files
    └── master_reference.json   # Reference data
```

## 🔧 Compliance Rules (43 Total)

### 🆔 Identification Rules (9 rules)
- Agent name requirements (state-specific)
- Company identification compliance
- Customer name usage validation

### 📞 Communication Rules (19 rules)
- Do Not Call compliance
- Third-party disclosure restrictions
- SMS and email communication rules
- Attorney representation handling

### ⚖️ Policy Rules (10 rules)
- Cure period compliance
- Medical information handling
- Threat and harassment prevention
- Fraudulent representation detection

### 💻 System Rules (4 rules)
- Contact documentation requirements
- Activity code accuracy validation

## 🚨 Troubleshooting

### Build Failures
```bash
# Check build logs
aws logs describe-log-groups --log-group-name-prefix "/aws/codebuild/anycompany"
```

### Lambda Function Errors
```bash
# Check function logs
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/anycompany"
```

### Rules Not Loading
- Verify API Gateway endpoint is accessible
- Check DynamoDB `anycompany-rules-prod` table has 43 rules
- Confirm React app environment variables are set correctly

### Audio Processing Issues
- Ensure WAV files are valid format
- Check S3 bucket permissions
- Verify reference data is uploaded to `reference/` folder

## 🧹 Cleanup

```bash
# Delete ECS service first
aws cloudformation update-stack \
  --stack-name anycompany-compliance \
  --template-body file://infrastructure.yaml \
  --capabilities CAPABILITY_IAM \
  --parameters ParameterKey=Environment,ParameterValue=prod \
               ParameterKey=DeployECS,ParameterValue=false

# Wait for update to complete
aws cloudformation wait stack-update-complete --stack-name anycompany-compliance

# Delete the stack
aws cloudformation delete-stack --stack-name anycompany-compliance

# Empty S3 buckets if needed
aws s3 rm s3://anycompany-source-prod-$(aws sts get-caller-identity --query Account --output text) --recursive
```

## 💰 Cost Estimation

**Monthly costs for moderate usage (100 calls/month):**
- Lambda: ~$5
- DynamoDB: ~$2
- S3: ~$3
- Transcribe: ~$10
- Comprehend: ~$5
- ECS Fargate: ~$15
- **Total: ~$40/month**

## 🔒 Security Features

- **WAF Protection** with rate limiting and common attack prevention
- **VPC Isolation** with private subnets for containers
- **IAM Roles** with least-privilege access
- **Cognito Authentication** with demo users
- **S3 Encryption** at rest
- **HTTPS/TLS** for all communications

## 📞 Support

For issues or questions:
1. Check CloudWatch logs for error details
2. Verify all prerequisites are met
3. Ensure AWS CLI has sufficient permissions
4. Review the troubleshooting section above

---

**🎉 Congratulations! Your AI-powered compliance validation platform is now deployed and ready for production use.**