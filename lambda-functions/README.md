# Lambda Functions

This directory contains all AWS Lambda functions for the AnyCompany Compliance Platform.

## Structure

```
lambda-functions/
├── transcription-handler/    # Processes completed transcriptions
│   ├── index.py             # Main handler code
│   ├── deploy.sh            # Deployment script
│   └── README.md            # Function documentation
├── api-function/            # REST API endpoints
│   ├── index.py             # Main handler code
│   ├── deploy.sh            # Deployment script
│   └── README.md            # Function documentation
├── processor/               # Audio processing (future)
├── deploy-all.sh            # Deploy all functions
└── README.md                # This file
```

## Quick Deployment

### Deploy All Functions
```bash
cd lambda-functions
./deploy-all.sh
```

### Deploy Individual Functions
```bash
# Transcription handler only
cd lambda-functions/transcription-handler
./deploy.sh

# API function only
cd lambda-functions/api-function
./deploy.sh
```

## Function Overview

### 1. Transcription Handler
- **Purpose**: Process completed AWS Transcribe jobs
- **Trigger**: S3 ObjectCreated events on transcription output
- **Features**: Entity extraction, compliance checking, DynamoDB updates

### 2. API Function
- **Purpose**: Provide REST API for web application
- **Trigger**: API Gateway HTTP requests
- **Features**: Rules management, results retrieval, file uploads

### 3. Processor (Future)
- **Purpose**: Initial audio file processing
- **Trigger**: S3 ObjectCreated events on audio uploads
- **Features**: Transcription job initiation, metadata extraction

## Development

### Adding New Functions
1. Create new directory under `lambda-functions/`
2. Add `index.py` with handler code
3. Create `deploy.sh` script
4. Add documentation in `README.md`
5. Update `deploy-all.sh` to include new function

### Best Practices
- Keep functions focused on single responsibility
- Use environment variables for configuration
- Include proper error handling and logging
- Write deployment scripts for easy updates
- Document function purpose and usage