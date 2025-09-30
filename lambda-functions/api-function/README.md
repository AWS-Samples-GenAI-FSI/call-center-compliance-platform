# API Function

## Purpose
Provides REST API endpoints for the compliance platform:
- `/rules` - Get compliance rules grouped by category
- `/results` - Get call analysis results with violations
- `/upload-url` - Generate S3 presigned URLs for file uploads
- `/entity-metrics` - Get entity detection performance metrics

## Key Features
- ✅ DecimalEncoder for proper JSON serialization
- ✅ CORS configuration for web app access
- ✅ Proper rules grouping by category
- ✅ S3 presigned URL generation
- ✅ Error handling and logging

## Deployment
```bash
# From project root:
./lambda-functions/api-function/deploy.sh
```

## Environment Variables
- `CALLS_TABLE_NAME`: DynamoDB table for call records
- `RULES_TABLE_NAME`: DynamoDB table for compliance rules
- `INPUT_BUCKET_NAME`: S3 bucket for audio file uploads

## Trigger
API Gateway HTTP requests