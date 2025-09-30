#!/bin/bash

echo "🔗 Deploying API Function..."

# Create deployment package
zip -r api-function.zip index.py

# Update Lambda function
aws lambda update-function-code \
  --function-name anycompany-api-prod \
  --zip-file fileb://api-function.zip

# Clean up
rm api-function.zip

echo "✅ API function deployed successfully!"