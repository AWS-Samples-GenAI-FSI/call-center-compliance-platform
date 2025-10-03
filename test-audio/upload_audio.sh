#!/bin/bash

# Upload test audio files to S3 for processing
BUCKET="anycompany-input-prod-164543933824"
AUDIO_DIR="/Users/shamakka/allay-eba-pca/test-audio"

echo "🚀 Uploading test audio files to S3..."

# Upload all audio files to audio/ prefix
for file in $AUDIO_DIR/test_*.wav; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        echo "Uploading $filename..."
        aws s3 cp "$file" "s3://$BUCKET/audio/$filename"
        
        # Delay to avoid overwhelming transcription service
        sleep 2
    fi
done

echo "✅ Upload complete! Files will be processed automatically."
echo "📊 Monitor transcription jobs: aws transcribe list-transcription-jobs --status IN_PROGRESS"
echo "📊 Monitor processing: aws logs tail /aws/lambda/anycompany-processor-prod --follow"
