import json
import boto3
import uuid
import os
import time
from datetime import datetime

def lambda_handler(event, context):
    s3 = boto3.client('s3')
    dynamodb = boto3.resource('dynamodb')
    calls_table = dynamodb.Table(os.environ['CALLS_TABLE'])
    
    for record in event['Records']:
        # Handle SQS messages containing S3 events
        if 'body' in record:
            message_body = json.loads(record['body'])
            if 'Records' in message_body:
                s3_records = message_body['Records']
            else:
                continue
        else:
            s3_records = [record]
        
        for s3_record in s3_records:
            bucket = s3_record['s3']['bucket']['name']
            key = s3_record['s3']['object']['key']
            
            if not key.endswith('.wav'):
                continue
            
            call_id = str(uuid.uuid4())
            filename = key.split('/')[-1]
            
            # Start async transcription
            try:
                job_name = start_transcription_async(bucket, key, call_id, filename)
                
                calls_table.put_item(Item={
                    'call_id': call_id,
                    'filename': filename,
                    'transcript': 'PROCESSING',
                    'violations': [],
                    'processed_at': datetime.utcnow().isoformat(),
                    'status': 'transcribing',
                    'transcription_job_name': job_name
                })
                
            except Exception as e:
                print(f"Failed to start transcription for {filename}: {str(e)}")
                calls_table.put_item(Item={
                    'call_id': call_id,
                    'filename': filename,
                    'transcript': 'PROCESSING ERROR',
                    'violations': [],
                    'processed_at': datetime.utcnow().isoformat(),
                    'error': str(e)
                })
    
    return {'statusCode': 200}

def start_transcription_async(bucket, key, call_id, filename):
    transcribe = boto3.client('transcribe')
    
    timestamp = int(time.time() * 1000)
    job_name = f"anycompany-{call_id}-{timestamp}"
    
    media_uri = f"s3://{bucket}/{key}"
    
    transcribe.start_transcription_job(
        TranscriptionJobName=job_name,
        Media={'MediaFileUri': media_uri},
        MediaFormat='wav',
        LanguageCode='en-US',
        OutputBucketName=os.environ['TRANSCRIBE_OUTPUT_BUCKET'],
        OutputKey=f"transcripts/{job_name}.json"
    )
    
    print(f'Started transcription job {job_name} for {filename}')
    return job_name