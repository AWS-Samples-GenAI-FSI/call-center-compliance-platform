# AnyCompany Compliance Platform - Deployment Guide

## 🚀 Quick Start

### One-Command Deployment
```bash
./deploy.sh
```

The script will guide you through deployment options:

1. **Full deployment** - Infrastructure + Lambda + Frontend (first time)
2. **Infrastructure only** - CloudFormation stack only
3. **Lambda functions only** - Update function code
4. **Frontend only** - React app build and deploy
5. **Quick fix deployment** - Lambda + Frontend (recommended for updates)

## 📋 Prerequisites

### Required Tools
- AWS CLI (configured with credentials)
- Node.js and npm
- Bash shell
- zip utility

### AWS Permissions
Your AWS credentials need permissions for:
- CloudFormation (create/update stacks)
- Lambda (update function code)
- S3 (upload files)
- CodeBuild (start builds)
- ECS (update services)

## 🎯 Deployment Scenarios

### First Time Deployment
```bash
./deploy.sh
# Select option 1: Full deployment
```

### Update Lambda Functions Only
```bash
./deploy.sh
# Select option 3: Lambda functions only
```

### Update Frontend Only
```bash
./deploy.sh
# Select option 4: Frontend only
```

### Apply Fixes (Recommended)
```bash
./deploy.sh
# Select option 5: Quick fix deployment
```

## 🔧 Manual Deployment

### Infrastructure
```bash
aws cloudformation deploy \
  --template-file infrastructure.yaml \
  --stack-name anycompany-compliance \
  --capabilities CAPABILITY_IAM \
  --parameter-overrides Environment=prod DeployECS=true
```

### Lambda Functions
```bash
cd lambda-functions
./deploy-all.sh
```

### Frontend
```bash
cd anycompany-compliance-react
npm install
npm run build
# Upload to S3 and trigger CodeBuild
```

## 🎛️ Configuration

### Environment Variables
The deployment script uses these defaults:
- `STACK_NAME="anycompany-compliance"`
- `ENVIRONMENT="prod"`
- `REGION="us-east-1"`

### Customization
Edit the top of `deploy.sh` to change defaults:
```bash
STACK_NAME="your-stack-name"
ENVIRONMENT="dev"
REGION="us-west-2"
```

## 🔍 Troubleshooting

### Common Issues

**AWS CLI not configured**
```bash
aws configure
# Enter your AWS Access Key ID, Secret, Region, and Output format
```

**Node.js not found**
```bash
# Install Node.js from https://nodejs.org/
# Or use package manager:
brew install node  # macOS
```

**CloudFormation stack exists**
- The script automatically detects and updates existing stacks
- For clean deployment, delete the stack first:
```bash
aws cloudformation delete-stack --stack-name anycompany-compliance
```

**CodeBuild fails**
- Check CodeBuild logs in AWS Console
- Ensure source code is properly uploaded to S3
- Verify IAM permissions

### Verification

After deployment, verify:
1. **Application URL** - Should return HTTP 200
2. **Login** - Use demo credentials to access dashboard
3. **API Endpoints** - Check `/rules` and `/results` endpoints
4. **Lambda Functions** - Verify latest code is deployed

## 📊 Monitoring

### Check Deployment Status
```bash
# CloudFormation stack status
aws cloudformation describe-stacks --stack-name anycompany-compliance

# Lambda function versions
aws lambda get-function --function-name anycompany-api-prod
aws lambda get-function --function-name anycompany-transcription-complete-prod

# ECS service status
aws ecs describe-services --cluster anycompany-cluster-prod --services anycompany-ui-prod
```

### Application Health
- Visit the application URL
- Check API Gateway endpoints
- Monitor CloudWatch logs for errors

## 🎉 Success Indicators

After successful deployment:
- ✅ Application accessible via web browser
- ✅ Demo login works with provided credentials
- ✅ Rules tab shows 43 compliance rules
- ✅ Upload functionality available
- ✅ Results dashboard displays processed calls

## 🆘 Support

If deployment fails:
1. Check the error message in the deployment script output
2. Verify AWS credentials and permissions
3. Check CloudFormation events in AWS Console
4. Review CodeBuild logs for frontend deployment issues
5. Ensure all prerequisites are installed and configured