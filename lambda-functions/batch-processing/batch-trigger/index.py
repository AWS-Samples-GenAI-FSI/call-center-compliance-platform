import json
import boto3
import uuid
from datetime import datetime

def lambda_handler(event, context):
    """
    Batch Trigger Lambda - Connects Step Functions to existing processing flow
    Input: Single call object from Step Functions Map state
    Output: Triggers existing SQS → Lambda flow without breaking anything
    """
    
    try:
        # Extract call information from Step Functions
        filename = event.get('filename')
        s3_key = event.get('s3_key')
        bucket = event.get('bucket')
        genesys_id = event.get('genesys_id')
        
        print(f"🔄 Processing batch call: {filename} -> {genesys_id}")
        
        # Initialize AWS clients
        s3 = boto3.client('s3')
        dynamodb = boto3.resource('dynamodb')
        calls_table = dynamodb.Table('anycompany-calls-prod')
        
        # Generate unique call_id for this batch processing
        call_id = str(uuid.uuid4())
        
        print(f"📝 Generated call_id: {call_id}")
        
        # Create DynamoDB record (same as existing processor Lambda)
        calls_table.put_item(
            Item={
                'call_id': call_id,
                'filename': filename,
                'genesys_call_id': genesys_id,
                'processing_status': 'transcribing',
                'upload_type': 'batch_stepfunctions',
                'batch_processing': True,
                'created_at': datetime.utcnow().isoformat(),
                's3_bucket': bucket,
                's3_key': s3_key
            }
        )
        
        print(f"✅ Created DynamoDB record for batch call")
        
        # Copy file to audio/ folder to trigger existing flow
        # This mimics the UI upload process
        audio_key = f"audio/{filename}"
        
        copy_source = {
            'Bucket': bucket,
            'Key': s3_key
        }
        
        s3.copy_object(
            CopySource=copy_source,
            Bucket=bucket,
            Key=audio_key
        )
        
        print(f"📁 Copied {s3_key} -> {audio_key}")
        print(f"🚀 Triggered existing processing flow via S3 upload")
        
        # Return success response for Step Functions
        return {
            'statusCode': 200,
            'call_id': call_id,
            'filename': filename,
            'genesys_id': genesys_id,
            'processing_status': 'triggered',
            'audio_key': audio_key,
            'timestamp': datetime.utcnow().isoformat()
        }
        
    except Exception as e:
        print(f"❌ Error processing batch call: {str(e)}")
        return {
            'statusCode': 500,
            'error': str(e),
            'filename': event.get('filename', 'unknown'),
            'genesys_id': event.get('genesys_id', 'unknown')
        }