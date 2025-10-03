# AnyCompany Compliance Platform - Terraform

## 🚀 Automated Deployment

### One-Command Deployment
```bash
./deploy-automated.sh
```

### Interactive Deployment
```bash
./deploy.sh
```

## ✅ Features

- **Enhanced Rules Library**: Displays detailed rule logic (type, patterns, conditions)
- **43 Compliance Rules**: Complete rule engine with AI-powered detection
- **Real-time Processing**: AWS Transcribe + Comprehend integration
- **Entity Metrics**: Confidence scoring and performance analysis

## 🏗️ Infrastructure

- **Lambda Functions**: API, Processor, Transcription Complete
- **Storage**: S3 buckets for audio, transcripts, entities
- **Database**: DynamoDB for calls and rules
- **Compute**: ECS Fargate with load balancer
- **AI Services**: Transcribe, Comprehend

## 📊 Enhanced UI

The Terraform version now includes the same enhanced Rules Library tab as CloudFormation:
- Rule logic details (patterns, conditions, checks)
- Complete rule metadata
- Proper JSON serialization with DecimalEncoder

## 🔧 Manual Steps (if needed)

1. **Configure AWS CLI**: `aws configure`
2. **Deploy**: `./deploy-automated.sh`
3. **Access**: Use the Application URL from output

## 🎯 Next Deployment

Everything is now automated - just run `./deploy-automated.sh` for complete deployment.