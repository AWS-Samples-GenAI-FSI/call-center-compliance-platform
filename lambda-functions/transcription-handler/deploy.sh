#!/bin/bash

echo "📝 Deploying Transcription Completion Handler..."

# Create deployment package
zip -r transcription-handler.zip index.py

# Update Lambda function
aws lambda update-function-code \
  --function-name anycompany-transcription-complete-prod \
  --zip-file fileb://transcription-handler.zip

# Clean up
rm transcription-handler.zip

echo "✅ Transcription handler deployed successfully!"