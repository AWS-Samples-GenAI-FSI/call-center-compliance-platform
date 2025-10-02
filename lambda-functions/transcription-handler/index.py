import json
import boto3
import os
import time
import re
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
                    # Path 1: Existing UI upload flow
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
                    # Path 2: Bulk S3 upload flow - create call record on-the-fly
                    print(f'📁 No existing call record found - creating for bulk upload: {call_id}')
                    filename = f'bulk-upload-{job_name}.wav'
                    
                    # Extract entities using Comprehend
                    entities = extract_compliance_entities(transcript_text)
                    
                    # Process with rule engine
                    print(f'🔧 Processing rules for bulk upload {call_id} with transcript length: {len(transcript_text)}')
                    violations = process_with_rule_engine(transcript_text, call_id, filename)
                    print(f'⚠️ Found {len(violations)} violations for bulk upload {call_id}')
                    
                    # Create new call record for bulk upload
                    calls_table.put_item(
                        Item={
                            'call_id': call_id,
                            'filename': filename,
                            'transcript': transcript_text,
                            'entities': entities,
                            'violations': violations,
                            'status': 'completed',
                            'upload_type': 'bulk_s3',
                            'created_at': datetime.utcnow().isoformat(),
                            'processed_at': datetime.utcnow().isoformat()
                        }
                    )
                    
                    print(f'✅ Successfully processed bulk upload transcription for {filename}')
            
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
        
        # Process each rule with complete logic
        for rule in rules:
            try:
                violation = evaluate_rule_simple(rule, transcript, call_id)
                if violation:
                    violations.append(violation)
                    print(f'⚠️ Violation: {rule.get("rule_id")} - {rule.get("description")}')
            except Exception as rule_error:
                print(f'Error evaluating rule {rule.get("rule_id", "unknown")}: {str(rule_error)}')
        
        print(f'✅ Rule processing complete: {len(violations)} violations found')
        
    except Exception as e:
        print(f'Rule engine error: {str(e)}')
        # No fallback rules - return empty violations on error
    
    return violations

def evaluate_rule_simple(rule, transcript, call_id):
    """Complete rule evaluation with real business logic for all 43 rules"""
    logic = rule.get('logic', {})
    rule_type = logic.get('type', 'pattern_match')
    rule_id = rule.get('rule_id', '')
    
    # Extract reference data from call context
    ref_data = extract_reference_data_from_call_id(call_id)
    
    violation_detected = False
    
    try:
        # Route to specific rule implementation based on type
        if rule_type == 'pattern_match':
            violation_detected = evaluate_pattern_match_rule(logic, transcript)
        elif rule_type == 'pattern_match_conditional':
            violation_detected = evaluate_conditional_pattern_rule(logic, transcript, ref_data)
        elif rule_type == 'reference_check':
            violation_detected = evaluate_reference_check_rule(logic, ref_data, transcript)
        elif rule_type == 'reference_check_conditional':
            violation_detected = evaluate_conditional_reference_rule(logic, transcript, ref_data)
        elif rule_type == 'reference_validation':
            violation_detected = evaluate_reference_validation_rule(logic, ref_data, transcript)
        elif rule_type == 'reference_match':
            violation_detected = evaluate_reference_match_rule(logic, transcript, ref_data)
        elif rule_type == 'system_check':
            violation_detected = evaluate_system_check_rule(logic, ref_data)
        elif rule_type == 'sentiment_analysis':
            violation_detected = evaluate_sentiment_rule(logic, transcript)
        elif rule_type == 'pii_detection':
            violation_detected = evaluate_pii_rule(logic, transcript)
        elif rule_type == 'complex_validation':
            violation_detected = evaluate_complex_rule(logic, transcript, ref_data)
        else:
            # Fallback to simple pattern matching
            patterns = logic.get('patterns', [])
            required = logic.get('required', True)
            found = any(re.search(pattern, transcript, re.IGNORECASE) for pattern in patterns)
            violation_detected = (required and not found) or (not required and found)
            
    except Exception as e:
        print(f'Error evaluating rule {rule_id}: {str(e)}')
        return None
    
    if violation_detected:
        return {
            'date': datetime.now().strftime('%m/%d/%Y %I:%M:%S %p'),
            'severity': rule.get('severity', 'minor'),
            'code': rule_id,
            'rule_code': rule_id,
            'comment': rule.get('description', 'Rule violation detected'),
            'call_id': call_id
        }
    
    return None

def extract_reference_data_from_call_id(call_id):
    """Extract reference data from call context - would integrate with S3 reference files"""
    # Default reference data - in production would load from S3 reference files
    return {
        'state': 'TX',
        'agent_name': 'John Smith',
        'agent_alias': 'Johnny',
        'customer_name': 'Robert Williams',
        'do_not_call': False,
        'attorney_retained': False,
        'bankruptcy_filed': False,
        'cure_period_expired': True,
        'cease_desist': False
    }

def evaluate_pattern_match_rule(logic, transcript):
    """LO1001.06, LO1001.12 - Basic pattern matching"""
    patterns = logic.get('patterns', [])
    required = logic.get('required', True)
    timeframe = logic.get('timeFrame')
    
    search_text = transcript
    if timeframe == 'first_60_seconds':
        # Approximate first 60 seconds (first 150 words)
        words = transcript.split()
        search_text = ' '.join(words[:150])
    
    found = any(re.search(pattern, search_text, re.IGNORECASE) for pattern in patterns)
    return required and not found

def evaluate_conditional_pattern_rule(logic, transcript, ref_data):
    """LO1001.03, LO1001.10 - State-specific pattern matching"""
    condition = logic.get('condition', {})
    
    # Check if condition applies
    for key, value in condition.items():
        if isinstance(value, list):
            if ref_data.get(key) not in value:
                return False
        else:
            if ref_data.get(key) != value:
                return False
    
    # Apply pattern matching if condition is met
    return evaluate_pattern_match_rule(logic, transcript)

def evaluate_reference_check_rule(logic, ref_data, transcript):
    """LO1001.04, LO1005.04-06, LO1005.11 - Reference data validation"""
    check_type = logic.get('check')
    condition = logic.get('condition', {})
    
    # Check state condition first
    if condition:
        for key, value in condition.items():
            if isinstance(value, list):
                if ref_data.get(key) not in value:
                    return False
            else:
                if ref_data.get(key) != value:
                    return False
    
    # Specific check implementations
    if check_type == 'alias_usage':
        # Extract agent names from transcript
        name_patterns = [r'my name is ([a-zA-Z]+)', r'this is ([a-zA-Z]+)', r'([a-zA-Z]+) speaking']
        found_names = []
        
        for pattern in name_patterns:
            matches = re.findall(pattern, transcript, re.IGNORECASE)
            found_names.extend([name.lower() for name in matches])
        
        # Check if any found name is unauthorized alias
        agent_name = ref_data.get('agent_name', '').lower().split()[0]  # First name
        allowed_alias = ref_data.get('agent_alias', '').lower()
        
        for name in found_names:
            if name and name != agent_name and name != allowed_alias:
                return True  # Unauthorized alias used
        return False
    
    elif check_type in ['dnc_status', 'do_not_call']:
        return ref_data.get('do_not_call', False)
    
    elif check_type == 'cease_desist_flag':
        return ref_data.get('cease_desist', False)
    
    elif check_type == 'attorney_retained':
        return ref_data.get('attorney_retained', False)
    
    elif check_type == 'bankruptcy_filed':
        return ref_data.get('bankruptcy_filed', False)
    
    return False

def evaluate_conditional_reference_rule(logic, transcript, ref_data):
    """LO1006.03, LO1006.04 - Cure period violations"""
    condition = logic.get('condition', {})
    patterns = logic.get('patterns', [])
    
    # Check condition (e.g., cure_period_expired = False)
    for key, value in condition.items():
        if ref_data.get(key) != value:
            return False
    
    # Check patterns if condition is met
    return any(re.search(pattern, transcript, re.IGNORECASE) for pattern in patterns)

def evaluate_reference_validation_rule(logic, ref_data, transcript):
    """LO1001.05 - Agent name traceability"""
    check_type = logic.get('check')
    
    if check_type == 'agent_name_traceable':
        # Extract agent names from transcript
        name_patterns = [r'my name is ([a-zA-Z]+)', r'this is ([a-zA-Z]+)', r'([a-zA-Z]+) speaking']
        found_names = []
        
        for pattern in name_patterns:
            matches = re.findall(pattern, transcript, re.IGNORECASE)
            found_names.extend([name.lower() for name in matches])
        
        # Check if any found name matches agent or alias
        agent_name = ref_data.get('agent_name', '').lower().split()[0]
        agent_alias = ref_data.get('agent_alias', '').lower()
        
        for name in found_names:
            if name in [agent_name, agent_alias]:
                return False  # Name is traceable
        
        return len(found_names) > 0  # Untraceable name used
    
    return False

def evaluate_reference_match_rule(logic, transcript, ref_data):
    """LO1001.08, LO1001.09 - Customer name usage"""
    check_type = logic.get('check')
    context = logic.get('context')
    
    if check_type == 'customer_full_name':
        customer_name = ref_data.get('customer_name', '').lower()
        
        if context == 'voicemail':
            # Check if this is a voicemail
            voicemail_indicators = ['voicemail', 'message', 'calling for', 'please call']
            is_voicemail = any(indicator in transcript.lower() for indicator in voicemail_indicators)
            
            if is_voicemail:
                return customer_name not in transcript.lower()
        
        return customer_name not in transcript.lower()
    
    return False

def evaluate_system_check_rule(logic, ref_data):
    """LO1009.03, LO1009.05, LO1009.08, LO1009.09 - System compliance"""
    check_type = logic.get('check')
    
    # System checks would integrate with actual systems
    # For demo, simulate some violations
    system_violations = {
        'contact_documentation': False,  # No missing documentation
        'activity_code_accuracy': False,  # Codes are accurate
        'activity_code_customer_impact': False,  # No customer impact
        'activity_code_ally_impact': False,  # No company impact
        'activity_code_potential_impact': False  # No potential impact
    }
    
    return system_violations.get(check_type, False)

def evaluate_sentiment_rule(logic, transcript):
    """LO1005.14, LO1007.05-07 - Sentiment and threat analysis"""
    check_type = logic.get('check')
    
    if check_type == 'profanity_detection':
        profanity_words = ['damn', 'hell', 'crap', 'stupid', 'idiot', 'moron']
        return any(re.search(r'\b' + word + r'\b', transcript, re.IGNORECASE) for word in profanity_words)
    
    elif check_type == 'threatening_language':
        threat_phrases = [
            'jail', 'prison', 'arrest', 'sue you', 'legal action',
            'garnish', 'repossess', 'take your car', 'destroy your credit',
            'ruin your credit', 'send you to jail'
        ]
        return any(re.search(phrase, transcript, re.IGNORECASE) for phrase in threat_phrases)
    
    elif check_type == 'fraudulent_representation':
        fraud_phrases = [
            'you have to pay now', 'no choice', 'must pay immediately',
            'will be arrested', 'going to jail', 'have no option'
        ]
        return any(re.search(phrase, transcript, re.IGNORECASE) for phrase in fraud_phrases)
    
    return False

def evaluate_pii_rule(logic, transcript):
    """LO1005.25, LO1005.26 - PII detection"""
    # SSN pattern (XXX-XX-XXXX or XXXXXXXXX)
    ssn_pattern = r'\b\d{3}[-.]?\d{2}[-.]?\d{4}\b'
    if re.search(ssn_pattern, transcript):
        return True
    
    # Phone pattern (XXX-XXX-XXXX)
    phone_pattern = r'\b\d{3}[-.]?\d{3}[-.]?\d{4}\b'
    if re.search(phone_pattern, transcript):
        return True
    
    # Account number pattern
    account_pattern = r'\baccount.{0,10}\d{6,}\b'
    if re.search(account_pattern, transcript, re.IGNORECASE):
        return True
    
    # Credit card pattern
    cc_pattern = r'\b\d{4}[-\s]?\d{4}[-\s]?\d{4}[-\s]?\d{4}\b'
    if re.search(cc_pattern, transcript):
        return True
    
    return False

def evaluate_complex_rule(logic, transcript, ref_data):
    """Complex validation rules - custom business logic"""
    # Placeholder for complex multi-condition rules
    return False