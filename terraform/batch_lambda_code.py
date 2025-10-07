import json
import boto3
import re
import uuid
from datetime import datetime

def batch_prep_handler(event, context):
    """
    Batch Preparation Lambda - Production Version
    Input: S3 folder path with audio files
    Output: Array of call objects for Step Functions processing
    """
    
    try:
        # Get input parameters
        batch_folder = event.get('batch_folder', '')
        max_files = event.get('max_files', 15000)  # Production limit
        
        print(f"🔍 Processing batch folder: {batch_folder}")
        print(f"📊 Max files limit: {max_files} (production mode)")
        
        # Parse S3 path
        if not batch_folder.startswith('s3://'):
            return {
                'statusCode': 400,
                'error': 'Invalid S3 path format. Expected: s3://bucket/folder/'
            }
        
        # Extract bucket and prefix
        s3_parts = batch_folder.replace('s3://', '').split('/', 1)
        bucket_name = s3_parts[0]
        prefix = s3_parts[1] if len(s3_parts) > 1 else ''
        
        print(f"📁 Bucket: {bucket_name}, Prefix: {prefix}")
        
        # Initialize S3 client
        s3 = boto3.client('s3')
        
        # List audio files in the folder
        calls = []
        paginator = s3.get_paginator('list_objects_v2')
        
        for page in paginator.paginate(Bucket=bucket_name, Prefix=prefix):
            if 'Contents' not in page:
                continue
                
            for obj in page['Contents']:
                key = obj['Key']
                
                # Only process .wav files
                if not key.lower().endswith('.wav'):
                    continue
                
                # Stop if we hit max files limit
                if len(calls) >= max_files:
                    break
                
                # Extract filename
                filename = key.split('/')[-1]
                
                # Extract Genesys ID from filename
                genesys_id = extract_genesys_id_from_filename(filename)
                
                # Create call object
                call_obj = {
                    'filename': filename,
                    's3_key': key,
                    'bucket': bucket_name,
                    'genesys_id': genesys_id,
                    'file_size': obj['Size'],
                    'last_modified': obj['LastModified'].isoformat()
                }
                
                calls.append(call_obj)
                print(f"📄 Added: {filename} -> {genesys_id}")
            
            # Break outer loop if max reached
            if len(calls) >= max_files:
                break
        
        # Prepare response
        response = {
            'statusCode': 200,
            'batch_info': {
                'batch_folder': batch_folder,
                'total_files_found': len(calls),
                'processing_timestamp': datetime.utcnow().isoformat(),
                'max_files_limit': max_files
            },
            'calls': calls
        }
        
        print(f"✅ Batch preparation complete: {len(calls)} files ready for processing")
        return response
        
    except Exception as e:
        print(f"❌ Error in batch preparation: {str(e)}")
        return {
            'statusCode': 500,
            'error': str(e),
            'batch_folder': event.get('batch_folder', 'unknown')
        }

def batch_trigger_handler(event, context):
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

def extract_genesys_id_from_filename(filename):
    """Extract Genesys Call ID from various filename patterns"""
    
    # Pattern 1: voicemail_XXX_VM_2024_XXXXXX.wav -> VM-2024-XXXXXX
    voicemail_match = re.search(r'voicemail_\d+_VM_(\d{4})_(\d{6})\.wav', filename)
    if voicemail_match:
        year, number = voicemail_match.groups()
        return f'VM-{year}-{number}'
    
    # Pattern 2: agent_call_XXX_GEN_2024_XXXXXX.wav -> GEN-2024-XXXXXX
    agent_match = re.search(r'agent_call_\d+_GEN_(\d{4})_(\d{6})\.wav', filename)
    if agent_match:
        year, number = agent_match.groups()
        return f'GEN-{year}-{number}'
    
    # Pattern 3: Direct VM-YYYY-XXXXXX or GEN-YYYY-XXXXXX in filename
    id_match = re.search(r'(VM|GEN)-\d{4}-\d{6}', filename)
    if id_match:
        return id_match.group()
    
    # Fallback: Generate consistent ID based on filename
    import hashlib
    file_hash = hashlib.md5(filename.encode()).hexdigest()[:6]
    prefix = 'VM' if 'voicemail' in filename.lower() else 'GEN'
    return f'{prefix}-2024-{file_hash.upper()}'