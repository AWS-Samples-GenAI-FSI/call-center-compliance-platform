import json
import boto3
import os
import time
from datetime import datetime
from decimal import Decimal

def lambda_handler(event, context):
    s3 = boto3.client('s3')
    dynamodb = boto3.resource('dynamodb')
    calls_table = dynamodb.Table(os.environ['CALLS_TABLE'])
    
    for record in event['Records']:
        bucket = record['s3']['bucket']['name']
        key = record['s3']['object']['key']
        
        if not key.startswith('transcripts/') or not key.endswith('.json'):
            continue
        
        # Extract job name from key
        job_name = key.replace('transcripts/', '').replace('.json', '')
        
        try:
            print(f'🔍 Processing transcription completion for job: {job_name}')
            
            # Process transcription file directly from S3 (job may already be deleted)
            try:
                # Get transcript from S3
                transcript_obj = s3.get_object(Bucket=bucket, Key=key)
                transcript_data = json.loads(transcript_obj['Body'].read())
                transcript_text = transcript_data['results']['transcripts'][0]['transcript']
                
                print(f'📝 Retrieved transcript: {transcript_text[:100]}...')
                
                # Extract call_id from job name (format: anycompany-{call_id}-{timestamp})
                job_parts = job_name.split('-')
                if len(job_parts) >= 3:
                    call_id = '-'.join(job_parts[1:-1])  # Handle UUIDs with dashes
                else:
                    call_id = 'unknown'
                
                # Find the call record
                response = calls_table.scan(
                    FilterExpression='call_id = :call_id',
                    ExpressionAttributeValues={':call_id': call_id}
                )
                
                if response['Items']:
                    call_record = response['Items'][0]
                    filename = call_record['filename']
                    
                    # Extract entities using Comprehend
                    entities = extract_compliance_entities(transcript_text)
                    
                    # Process with rule engine
                    print(f'🔧 Processing rules for call {call_id} with transcript length: {len(transcript_text)}')
                    violations = process_with_rule_engine(transcript_text, call_id, filename)
                    print(f'⚠️ Found {len(violations)} violations for call {call_id}')
                    
                    # Update call record
                    calls_table.update_item(
                        Key={'call_id': call_id},
                        UpdateExpression='SET transcript = :transcript, entities = :entities, violations = :violations, #status = :status, processed_at = :processed_at',
                        ExpressionAttributeNames={'#status': 'status'},
                        ExpressionAttributeValues={
                            ':transcript': transcript_text,
                            ':entities': entities,
                            ':violations': violations,
                            ':status': 'completed',
                            ':processed_at': datetime.utcnow().isoformat()
                        }
                    )
                    
                    print(f'✅ Successfully processed transcription for {filename}')
                else:
                    print(f'❌ No call record found for call_id: {call_id}')
            
            except Exception as transcript_error:
                print(f'❌ Error processing transcript file {key}: {str(transcript_error)}')
                
                # Try to extract call_id and mark as failed
                job_parts = job_name.split('-')
                if len(job_parts) >= 3:
                    call_id = '-'.join(job_parts[1:-1])
                    try:
                        calls_table.update_item(
                            Key={'call_id': call_id},
                            UpdateExpression='SET transcript = :transcript, #status = :status, #error = :error, processed_at = :processed_at',
                            ExpressionAttributeNames={'#status': 'status', '#error': 'error'},
                            ExpressionAttributeValues={
                                ':transcript': 'TRANSCRIPTION_FAILED',
                                ':status': 'failed',
                                ':error': str(transcript_error),
                                ':processed_at': datetime.utcnow().isoformat()
                            }
                        )
                    except Exception as db_error:
                        print(f'❌ Failed to update DB for failed transcription: {str(db_error)}')
        
        except Exception as e:
            print(f'Error processing transcription completion: {str(e)}')
    
    return {'statusCode': 200}

def extract_compliance_entities(transcript):
    comprehend = boto3.client('comprehend')
    s3 = boto3.client('s3')
    
    entities = {
        'persons': [],
        'organizations': [],
        'financial': [],
        'medical': [],
        'legal': [],
        'communication': [],
        'pii_entities': []
    }
    
    try:
        # Handle long transcripts by chunking
        chunks = chunk_text(transcript, 4500)  # Leave buffer for 5000 char limit
        
        for i, chunk in enumerate(chunks):
            try:
                # Add delay between API calls to avoid rate limiting
                if i > 0:
                    time.sleep(0.1)
                
                # Batch Comprehend calls
                entities_response = comprehend.detect_entities(Text=chunk, LanguageCode='en')
                phrases_response = comprehend.detect_key_phrases(Text=chunk, LanguageCode='en')
                pii_response = comprehend.detect_pii_entities(Text=chunk, LanguageCode='en')
                
                # Process entities
                for entity in entities_response['Entities']:
                    if entity['Score'] > 0.7:
                        entity_type = entity['Type']
                        entity_text = entity['Text']
                        
                        if entity_type == 'PERSON':
                            entities['persons'].append({
                                'text': entity_text,
                                'confidence': Decimal(str(entity['Score']))
                            })
                        elif entity_type == 'ORGANIZATION':
                            entities['organizations'].append({
                                'text': entity_text,
                                'confidence': Decimal(str(entity['Score']))
                            })
                
                # Process key phrases
                for phrase_data in phrases_response['KeyPhrases']:
                    if phrase_data['Score'] > 0.7:
                        phrase = phrase_data['Text'].lower()
                        
                        if any(term in phrase for term in ['dollar', 'payment', 'amount', 'balance', 'account']):
                            entities['financial'].append({
                                'text': phrase,
                                'confidence': Decimal(str(phrase_data['Score']))
                            })
                        elif any(term in phrase for term in ['medical', 'hospital', 'doctor', 'surgery', 'illness', 'medication']):
                            entities['medical'].append({
                                'text': phrase,
                                'confidence': Decimal(str(phrase_data['Score']))
                            })
                        elif any(term in phrase for term in ['attorney', 'lawyer', 'bankruptcy', 'legal action', 'garnish', 'repossess']):
                            entities['legal'].append({
                                'text': phrase,
                                'confidence': Decimal(str(phrase_data['Score']))
                            })
                        elif any(term in phrase for term in ['text message', 'sms', 'email', 'voicemail']):
                            entities['communication'].append({
                                'text': phrase,
                                'confidence': Decimal(str(phrase_data['Score']))
                            })
                
                # Process PII entities
                for pii_entity in pii_response['Entities']:
                    if pii_entity['Score'] > 0.8:  # Higher threshold for PII
                        entities['pii_entities'].append({
                            'text': pii_entity['Text'],
                            'type': pii_entity['Type'],
                            'confidence': Decimal(str(pii_entity['Score']))
                        })
            
            except Exception as chunk_error:
                print(f'Error processing chunk {i}: {str(chunk_error)}')
                continue
        
        # Save entities to Comprehend output bucket
        try:
            entities_json = json.dumps(entities, indent=2)
            timestamp = datetime.utcnow().strftime('%Y%m%d_%H%M%S')
            s3.put_object(
                Bucket=os.environ['COMPREHEND_OUTPUT_BUCKET'],
                Key=f"entities/{timestamp}_entities.json",
                Body=entities_json,
                ContentType='application/json'
            )
        except Exception as s3_error:
            print(f'Failed to save entities to S3: {str(s3_error)}')
        
        return entities
        
    except Exception as e:
        print(f'Entity extraction error: {str(e)}')
        # Return fallback entities on error
        return {
            'persons': [],
            'organizations': [],
            'financial': [],
            'medical': [],
            'legal': [],
            'communication': [],
            'pii_entities': [],
            'error': str(e)
        }

def chunk_text(text, max_length):
    """Split text into chunks that fit Comprehend limits"""
    if len(text) <= max_length:
        return [text]
    
    chunks = []
    words = text.split()
    current_chunk = []
    current_length = 0
    
    for word in words:
        word_length = len(word) + 1  # +1 for space
        if current_length + word_length > max_length:
            if current_chunk:
                chunks.append(' '.join(current_chunk))
                current_chunk = [word]
                current_length = len(word)
            else:
                # Single word longer than max_length, truncate it
                chunks.append(word[:max_length])
        else:
            current_chunk.append(word)
            current_length += word_length
    
    if current_chunk:
        chunks.append(' '.join(current_chunk))
    
    return chunks

def process_with_rule_engine(transcript, call_id, filename):
    dynamodb = boto3.resource('dynamodb')
    rules_table = dynamodb.Table(os.environ['RULES_TABLE'])
    
    violations = []
    transcript_lower = transcript.lower()
    
    try:
        # Get active rules from DynamoDB
        response = rules_table.scan(
            FilterExpression='active = :active',
            ExpressionAttributeValues={':active': True}
        )
        rules = response.get('Items', [])
        print(f'📜 Loaded {len(rules)} active rules from database')
        
        # Process each rule
        for rule in rules:
            try:
                violation = evaluate_rule_simple(rule, transcript_lower, call_id)
                if violation:
                    violations.append(violation)
            except Exception as rule_error:
                print(f'Error evaluating rule {rule.get("rule_id", "unknown")}: {str(rule_error)}')
        
    except Exception as e:
        print(f'Rule engine error: {str(e)}')
        # No fallback rules - return empty violations on error
    
    return violations

def evaluate_rule_simple(rule, transcript, call_id):
    """Simplified rule evaluation for transcription complete handler"""
    logic = rule.get('logic', {})
    patterns = logic.get('patterns', [])
    required = logic.get('required', True)
    
    # Basic pattern matching
    found = any(pattern.lower() in transcript for pattern in patterns)
    
    # If required=True and not found, it's a violation
    # If required=False and found, it's a violation
    violation_detected = (required and not found) or (not required and found)
    
    if violation_detected:
        return {
            'date': datetime.now().strftime('%m/%d/%Y %I:%M:%S %p'),
            'severity': rule.get('severity', 'minor'),
            'code': rule.get('rule_id', 'UNKNOWN'),
            'rule_code': rule.get('rule_id', 'UNKNOWN'),
            'comment': rule.get('description', 'Rule violation detected'),
            'call_id': call_id
        }
    
    return None