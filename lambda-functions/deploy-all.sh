#!/bin/bash

echo "🚀 Deploying All Lambda Functions..."
echo ""

# Make scripts executable
chmod +x transcription-handler/deploy.sh
chmod +x api-function/deploy.sh

# Deploy transcription handler
echo "1️⃣ Deploying Transcription Handler..."
cd transcription-handler
./deploy.sh
cd ..

echo ""

# Deploy API function
echo "2️⃣ Deploying API Function..."
cd api-function
./deploy.sh
cd ..

echo ""
echo "✅ All Lambda functions deployed successfully!"
echo ""
echo "🎯 Updated Functions:"
echo "   ✅ Transcription completion handler (S3 processing, Decimal handling)"
echo "   ✅ API function (Decimal serialization, rules grouping)"
echo ""
echo "🚀 Platform is ready for production use!"