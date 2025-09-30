# Transcription Completion Handler

## Purpose
Processes completed AWS Transcribe jobs and performs:
- Entity extraction using AWS Comprehend
- Compliance rule evaluation
- DynamoDB record updates

## Key Features
- ✅ Processes transcription files directly from S3 (no job dependency)
- ✅ Handles Decimal types for DynamoDB compatibility
- ✅ Comprehensive entity extraction (persons, financial, legal, PII)
- ✅ Rule-based compliance violation detection
- ✅ Error handling and logging

## Deployment
```bash
# From project root:
./lambda-functions/transcription-handler/deploy.sh
```

## Environment Variables
- `CALLS_TABLE`: DynamoDB table for call records
- `RULES_TABLE`: DynamoDB table for compliance rules
- `INPUT_BUCKET_NAME`: S3 bucket for audio files
- `TRANSCRIBE_OUTPUT_BUCKET`: S3 bucket for transcription results
- `COMPREHEND_OUTPUT_BUCKET`: S3 bucket for entity analysis results

## Trigger
S3 ObjectCreated events on transcription output bucket (*.json files)