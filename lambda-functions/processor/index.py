import json
import boto3
import os
from datetime import datetime
import uuid

def lambda_handler(event, context):
    s3 = boto3.client('s3')
    transcribe = boto3.client('transcribe')
    dynamodb = boto3.resource('dynamodb')
    calls_table = dynamodb.Table(os.environ['CALLS_TABLE_NAME'])
    
    for record in event['Records']:
        bucket = record['s3']['bucket']['name']
        key = record['s3']['object']['key']
        
        if not key.startswith('audio/') or not key.endswith('.wav'):
            continue
        
        filename = key.replace('audio/', '')
        call_id = str(uuid.uuid4())
        
        try:
            # Create call record in DynamoDB
            calls_table.put_item(
                Item={
                    'call_id': call_id,
                    'filename': filename,
                    'status': 'processing',
                    'created_at': datetime.utcnow().isoformat(),
                    'processing_status': 'transcribing'
                }
            )
            
            # Start transcription job
            job_name = f"anycompany-{call_id}-{int(datetime.utcnow().timestamp() * 1000)}"
            
            transcribe.start_transcription_job(
                TranscriptionJobName=job_name,
                Media={'MediaFileUri': f's3://{bucket}/{key}'},
                MediaFormat='wav',
                LanguageCode='en-US',
                OutputBucketName=os.environ['TRANSCRIBE_OUTPUT_BUCKET']
            )
            
            print(f'Started transcription job {job_name} for {filename}')
            
        except Exception as e:
            print(f'Error processing {filename}: {str(e)}')
            # Mark as failed
            try:
                calls_table.update_item(
                    Key={'call_id': call_id},
                    UpdateExpression='SET #status = :status, #error = :error',
                    ExpressionAttributeNames={'#status': 'status', '#error': 'error'},
                    ExpressionAttributeValues={
                        ':status': 'failed',
                        ':error': str(e)
                    }
                )
            except:
                pass
    
    return {'statusCode': 200}