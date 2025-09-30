import json
import boto3
import os
from decimal import Decimal

class DecimalEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, Decimal):
            return float(obj)
        return super(DecimalEncoder, self).default(obj)

def lambda_handler(event, context):
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type,Authorization,X-Amz-Date,X-Api-Key,X-Amz-Security-Token',
        'Access-Control-Allow-Methods': 'GET,POST,PUT,OPTIONS',
        'Access-Control-Allow-Credentials': 'true'
    }
    
    if event['httpMethod'] == 'OPTIONS':
        return {'statusCode': 200, 'headers': headers}
    
    path = event.get('path', '')
    
    try:
        if path == '/rules':
            return get_rules(headers)
        elif path == '/results':
            return get_results(headers)
        elif path == '/upload' or path == '/upload-url':
            return get_upload_url(event, headers)
        elif path == '/entity-metrics':
            return get_entity_metrics(headers)
        else:
            return {'statusCode': 200, 'headers': headers, 'body': json.dumps({'message': 'API working', 'path': path})}
    except Exception as e:
        return {'statusCode': 500, 'headers': headers, 'body': json.dumps({'error': str(e)})}

def get_results(headers):
    dynamodb = boto3.resource('dynamodb')
    s3_client = boto3.client('s3')
    table = dynamodb.Table(os.environ['CALLS_TABLE_NAME'])
    
    response = table.scan()
    calls = response.get('Items', [])
    
    for call in calls:
        if 'filename' in call:
            try:
                call['audio_url'] = s3_client.generate_presigned_url(
                    'get_object',
                    Params={
                        'Bucket': os.environ['INPUT_BUCKET_NAME'],
                        'Key': f"audio/{call['filename']}"
                    },
                    ExpiresIn=3600
                )
            except:
                call['audio_url'] = None
    
    total_violations = sum(len(call.get('violations', [])) for call in calls)
    compliance_rate = ((len(calls) * 3 - total_violations) / (len(calls) * 3)) * 100 if calls else 100
    
    return {
        'statusCode': 200,
        'headers': headers,
        'body': json.dumps({
            'total_calls': len(calls),
            'total_violations': total_violations,
            'compliance_rate': round(compliance_rate, 1),
            'calls': calls
        }, cls=DecimalEncoder)
    }

def get_upload_url(event, headers):
    s3_client = boto3.client('s3')
    
    body = json.loads(event.get('body', '{}'))
    filename = body.get('filename', 'audio.wav')
    
    # Handle reference files
    if filename.startswith('reference/'):
        content_type = 'application/json' if filename.endswith('.json') else 'text/csv'
        key = filename
    else:
        content_type = 'audio/wav'
        key = f"audio/{filename}"
    
    url = s3_client.generate_presigned_url(
        'put_object',
        Params={
            'Bucket': os.environ['INPUT_BUCKET_NAME'],
            'Key': key,
            'ContentType': content_type
        },
        ExpiresIn=3600
    )
    
    return {
        'statusCode': 200,
        'headers': headers,
        'body': json.dumps({'upload_url': url})
    }

def get_entity_metrics(headers):
    dynamodb = boto3.resource('dynamodb')
    calls_table = dynamodb.Table(os.environ['CALLS_TABLE_NAME'])
    
    try:
        response = calls_table.scan()
        calls = response.get('Items', [])
        
        if not calls:
            return {
                'statusCode': 200,
                'headers': headers,
                'body': json.dumps({
                    'message': 'No processed calls found. Upload audio files to see entity analysis.',
                    'total_calls': 0,
                    'total_entities': 0,
                    'overall_accuracy': 0,
                    'avg_confidence': 0
                })
            }
        
        # Filter out failed calls
        successful_calls = [c for c in calls if c.get('transcript') not in ['TRANSCRIPTION_FAILED', 'PROCESSING', None, '']]
        failed_calls = [c for c in calls if c.get('transcript') in ['TRANSCRIPTION_FAILED', 'PROCESSING']]
        
        if not successful_calls:
            return {
                'statusCode': 200,
                'headers': headers,
                'body': json.dumps({
                    'message': f'No successful transcriptions found. {len(failed_calls)} call(s) failed processing.',
                    'total_calls': len(calls),
                    'failed_calls': len(failed_calls),
                    'total_entities': 0,
                    'overall_accuracy': 0,
                    'avg_confidence': 0
                })
            }
        
        # Calculate aggregated entity metrics for business analysis
        entity_analysis = {
            'ssn': {'total': 0, 'confidences': [], 'low_conf_count': 0},
            'person_names': {'total': 0, 'confidences': [], 'low_conf_count': 0},
            'phone': {'total': 0, 'confidences': [], 'low_conf_count': 0},
            'account_numbers': {'total': 0, 'confidences': [], 'low_conf_count': 0},
            'financial_terms': {'total': 0, 'confidences': [], 'low_conf_count': 0},
            'medical_terms': {'total': 0, 'confidences': [], 'low_conf_count': 0}
        }
        
        low_confidence_threshold = 0.80
        
        for call in successful_calls:
            entities = call.get('entities', {})
            if isinstance(entities, dict):
                # Process persons (names)
                if 'persons' in entities and isinstance(entities['persons'], list):
                    for entity in entities['persons']:
                        if isinstance(entity, dict) and 'confidence' in entity:
                            conf = float(entity['confidence']) if isinstance(entity['confidence'], Decimal) else entity['confidence']
                            entity_analysis['person_names']['total'] += 1
                            entity_analysis['person_names']['confidences'].append(conf)
                            if conf < low_confidence_threshold:
                                entity_analysis['person_names']['low_conf_count'] += 1
                
                # Process financial entities
                if 'financial' in entities and isinstance(entities['financial'], list):
                    for entity in entities['financial']:
                        if isinstance(entity, dict) and 'confidence' in entity:
                            conf = float(entity['confidence']) if isinstance(entity['confidence'], Decimal) else entity['confidence']
                            entity_analysis['financial_terms']['total'] += 1
                            entity_analysis['financial_terms']['confidences'].append(conf)
                            if conf < low_confidence_threshold:
                                entity_analysis['financial_terms']['low_conf_count'] += 1
        
        # Calculate summary statistics
        summary_stats = {}
        for entity_type, data in entity_analysis.items():
            if data['confidences']:
                avg_conf = sum(data['confidences']) / len(data['confidences'])
                low_conf_pct = (data['low_conf_count'] / data['total']) * 100 if data['total'] > 0 else 0
                
                summary_stats[entity_type] = {
                    'total_detected': data['total'],
                    'avg_confidence': round(avg_conf * 100, 1),
                    'low_confidence_count': data['low_conf_count'],
                    'low_confidence_pct': round(low_conf_pct, 1),
                    'action_needed': 'Review' if low_conf_pct > 20 else 'Monitor' if low_conf_pct > 10 else 'Good'
                }
            else:
                summary_stats[entity_type] = {
                    'total_detected': 0,
                    'avg_confidence': 0,
                    'low_confidence_count': 0,
                    'low_confidence_pct': 0,
                    'action_needed': 'No Data'
                }
        
        total_entities = sum(stats['total_detected'] for stats in summary_stats.values())
        overall_avg_conf = sum(conf for data in entity_analysis.values() for conf in data['confidences'])
        overall_avg_conf = (overall_avg_conf / total_entities * 100) if total_entities > 0 else 0
        
        # Map entity types to business-friendly names
        entity_type_mapping = {
            'person_names': 'persons',
            'financial_terms': 'financial',
            'medical_terms': 'medical',
            'ssn': 'financial',
            'phone': 'communication',
            'account_numbers': 'financial'
        }
        
        # Group by business categories
        business_summary = {
            'persons': {'total_detected': 0, 'avg_confidence': 0, 'low_confidence_count': 0, 'low_confidence_pct': 0, 'action_needed': 'No Data'},
            'organizations': {'total_detected': 0, 'avg_confidence': 0, 'low_confidence_count': 0, 'low_confidence_pct': 0, 'action_needed': 'No Data'},
            'financial': {'total_detected': 0, 'avg_confidence': 0, 'low_confidence_count': 0, 'low_confidence_pct': 0, 'action_needed': 'No Data'},
            'medical': {'total_detected': 0, 'avg_confidence': 0, 'low_confidence_count': 0, 'low_confidence_pct': 0, 'action_needed': 'No Data'},
            'legal': {'total_detected': 0, 'avg_confidence': 0, 'low_confidence_count': 0, 'low_confidence_pct': 0, 'action_needed': 'No Data'},
            'communication': {'total_detected': 0, 'avg_confidence': 0, 'low_confidence_count': 0, 'low_confidence_pct': 0, 'action_needed': 'No Data'}
        }
        
        # Map technical entity types to business categories
        for tech_type, stats in summary_stats.items():
            business_type = entity_type_mapping.get(tech_type, 'communication')
            if business_type in business_summary:
                business_summary[business_type]['total_detected'] += stats['total_detected']
                if stats['avg_confidence'] > 0:
                    business_summary[business_type]['avg_confidence'] = max(business_summary[business_type]['avg_confidence'], stats['avg_confidence'])
                business_summary[business_type]['low_confidence_count'] += stats['low_confidence_count']
                if business_summary[business_type]['total_detected'] > 0:
                    business_summary[business_type]['low_confidence_pct'] = (business_summary[business_type]['low_confidence_count'] / business_summary[business_type]['total_detected']) * 100
                    business_summary[business_type]['action_needed'] = 'Review' if business_summary[business_type]['low_confidence_pct'] > 20 else 'Monitor' if business_summary[business_type]['low_confidence_pct'] > 10 else 'Good'
        
        return {
            'statusCode': 200,
            'headers': headers,
            'body': json.dumps({
                'total_calls': len(successful_calls),
                'total_entities': total_entities,
                'overall_accuracy': round(overall_avg_conf, 1),
                'avg_confidence': round(overall_avg_conf, 1),
                'entity_summary': business_summary
            }, cls=DecimalEncoder)
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': headers,
            'body': json.dumps({'error': f'Entity metrics error: {str(e)}'})
        }

def get_rules(headers):
    dynamodb = boto3.resource('dynamodb')
    rules_table = dynamodb.Table(os.environ['RULES_TABLE_NAME'])
    
    try:
        response = rules_table.scan()
        rules = response.get('Items', [])
        
        # Group rules by category
        grouped_rules = {
            'identification': [],
            'communication': [],
            'policy': [],
            'system': []
        }
        
        for rule in rules:
            category = rule.get('category', 'system')
            if category in grouped_rules:
                grouped_rules[category].append({
                    'code': rule.get('rule_id', ''),
                    'desc': rule.get('description', ''),
                    'severity': rule.get('severity', 'minor')
                })
        
        return {
            'statusCode': 200,
            'headers': headers,
            'body': json.dumps({'rules': grouped_rules}, cls=DecimalEncoder)
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': headers,
            'body': json.dumps({'error': f'Rules error: {str(e)}'})
        }