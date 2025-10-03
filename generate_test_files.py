#!/usr/bin/env python3
import os
import json
import random
from datetime import datetime

# Test scenarios covering all 43 compliance rules
test_scenarios = [
    # Agent Identification Rules (LO1001.x)
    {
        "category": "agent_identification",
        "rule_codes": ["LO1001.04", "LO1001.05", "LO1001.08"],
        "transcripts": [
            "Hi, this is Mike calling from Alley servicing about your account.",
            "Hello, my name is Sarah and I'm calling regarding your overdue payment.",
            "This is Johnny from collections, I need to speak with Robert Williams.",
            "Good morning, this is Agent Smith calling about your car loan.",
            "Hi, my name is Lisa calling from the servicing department.",
        ]
    },
    
    # Company Identification Rules (LO1001.10, LO1001.12)
    {
        "category": "company_identification", 
        "rule_codes": ["LO1001.10", "LO1001.12"],
        "transcripts": [
            "Hello, this is John from AnyCompany Servicing calling about your account.",
            "Hi, I'm calling from Ally Servicing regarding your loan payment.",
            "This is Mike from Alley servicing, I need to discuss your account.",
            "Good afternoon, this is Sarah calling from the servicing department.",
            "Hello, I'm with AnyCompany Servicing and need to speak with you.",
        ]
    },
    
    # Legal Terms and Attorney Representation (LO1005.x)
    {
        "category": "legal_terms",
        "rule_codes": ["LO1005.04", "LO1005.05", "LO1005.06"],
        "transcripts": [
            "I understand you have an attorney representing you in this matter.",
            "We've been notified that you've filed for bankruptcy protection.",
            "Your lawyer contacted us about setting up a payment arrangement.",
            "We received notice from your attorney's office yesterday.",
            "I see here that you're represented by legal counsel.",
        ]
    },
    
    # Threatening Language (LO1007.05)
    {
        "category": "threatening_language",
        "rule_codes": ["LO1007.05"],
        "transcripts": [
            "If you don't pay immediately, we'll garnish your wages.",
            "We will take legal action and repossess your vehicle today.",
            "Pay now or we'll have you arrested for non-payment.",
            "We'll seize your assets if you don't pay this debt.",
            "You'll go to jail if you don't make this payment right now.",
        ]
    },
    
    # Medical Information (LO1006.x)
    {
        "category": "medical_terms",
        "rule_codes": ["LO1006.01", "LO1006.02"],
        "transcripts": [
            "I understand you've been in the hospital recently.",
            "We know about your medical bills and surgery costs.",
            "Your doctor bills are affecting your credit score.",
            "The medical treatment you received is expensive.",
            "We can work with you on these health-related expenses.",
        ]
    },
    
    # Financial Data Disclosure (LO1005.02, LO1005.24)
    {
        "category": "financial_data",
        "rule_codes": ["LO1005.02", "LO1005.24"],
        "transcripts": [
            "Your account balance is $2,847.50 and it's past due.",
            "The payment of $450 was not received on time.",
            "Account number 123456789 shows an overdue amount.",
            "You owe $1,200 on this debt and need to pay now.",
            "The balance due is $3,500 plus late fees.",
        ]
    },
    
    # Communication Methods (LO1005.12, LO1005.13)
    {
        "category": "communication_methods",
        "rule_codes": ["LO1005.12", "LO1005.13"],
        "transcripts": [
            "I'll send you a text message with the payment details.",
            "Please check your email for the settlement offer.",
            "I'm leaving this voicemail about your overdue account.",
            "We'll contact you via SMS with payment instructions.",
            "Call back at this number to discuss your account.",
        ]
    },
    
    # State-Specific Rules
    {
        "category": "state_references",
        "rule_codes": ["LO1001.03", "LO1001.04", "LO1001.10"],
        "transcripts": [
            "I'm calling about your Massachusetts account that's overdue.",
            "This debt is governed by Michigan state collection laws.",
            "As a Texas resident, you have certain rights regarding this debt.",
            "New Hampshire regulations require me to inform you of your rights.",
            "Arizona law mandates that I disclose this information to you.",
        ]
    },
    
    # Third Party Disclosure (LO1005.02)
    {
        "category": "third_party_disclosure",
        "rule_codes": ["LO1005.02", "LO1005.24"],
        "transcripts": [
            "Is this Robert Williams? I'm calling about his overdue car payment.",
            "I need to speak with Lisa about her account that's in collections.",
            "This is regarding David Miller's unpaid loan balance.",
            "I'm looking for Sarah Johnson about her debt situation.",
            "Can you tell Robert that his account is seriously delinquent?",
        ]
    },
    
    # Do Not Call Violations (LO1005.11)
    {
        "category": "dnc_violations",
        "rule_codes": ["LO1005.11"],
        "transcripts": [
            "I know you asked us not to call, but this is important.",
            "Despite your request to stop calling, we need to discuss this.",
            "You're on our do not call list, but we have to contact you.",
            "I'm calling even though you said not to call anymore.",
            "This call is exempt from your do not call request.",
        ]
    },
    
    # Customer Name Usage (LO1001.08, LO1001.09)
    {
        "category": "customer_names",
        "rule_codes": ["LO1001.08", "LO1001.09"],
        "transcripts": [
            "Hello, I'm leaving a message for Mr. Robert Williams Jr.",
            "This voicemail is for Lisa Marie Brown regarding her account.",
            "I need to speak with David Michael Miller about his loan.",
            "This message is for Sarah Elizabeth Johnson.",
            "Please have Robert Williams Sr. call us back immediately.",
        ]
    },
    
    # System Compliance (LO1009.x)
    {
        "category": "system_compliance",
        "rule_codes": ["LO1009.03", "LO1009.05", "LO1009.08", "LO1009.09"],
        "transcripts": [
            "I'm documenting this contact in our system as required.",
            "This call is being recorded for quality and compliance purposes.",
            "I'm updating your account with today's contact information.",
            "Our system shows this is your third contact this month.",
            "I'm logging this conversation per company policy.",
        ]
    },
    
    # Mixed Violations (Multiple Rules)
    {
        "category": "mixed_violations",
        "rule_codes": ["LO1001.12", "LO1005.02", "LO1007.05"],
        "transcripts": [
            "Hi, this is Mike calling about Robert's $2,500 debt. Pay now or we'll garnish wages.",
            "Sarah, your account is overdue $1,800. We'll take legal action immediately.",
            "This is collections calling. Lisa owes $3,200 and we'll repossess her car today.",
            "David's account shows $950 past due. We'll have him arrested if not paid.",
            "Robert Williams owes $2,100. We'll seize his assets and garnish wages.",
        ]
    },
    
    # Compliant Calls (No Violations)
    {
        "category": "compliant_calls",
        "rule_codes": [],
        "transcripts": [
            "Hello, this is John Smith from AnyCompany Servicing. May I speak with Robert Williams about his account?",
            "Good morning, this is Sarah from AnyCompany Servicing calling for Lisa Brown regarding her loan.",
            "Hi, my name is Mike Davis from AnyCompany Servicing. I'm calling for David Miller about his account.",
            "Hello, this is Jennifer from AnyCompany Servicing. May I speak with Sarah Johnson?",
            "Good afternoon, this is Tom Wilson from AnyCompany Servicing calling for Robert Williams.",
        ]
    },
]

def generate_test_files():
    """Generate 100 test transcript files covering all compliance scenarios"""
    
    # Create test directory
    test_dir = "/Users/shamakka/allay-eba-pca/test-transcripts"
    os.makedirs(test_dir, exist_ok=True)
    
    file_count = 0
    test_manifest = []
    
    # Generate files for each scenario
    for scenario in test_scenarios:
        category = scenario["category"]
        rule_codes = scenario["rule_codes"]
        transcripts = scenario["transcripts"]
        
        # Generate multiple files per scenario
        files_per_scenario = max(1, min(10, 100 // len(test_scenarios)))
        
        for i in range(files_per_scenario):
            if file_count >= 100:
                break
                
            file_count += 1
            
            # Select transcript (cycle through available ones)
            transcript = transcripts[i % len(transcripts)]
            
            # Create variations
            if i > 0:
                transcript = add_variations(transcript, i)
            
            # Generate filename
            filename = f"test_{file_count:03d}_{category}_{i+1}.json"
            filepath = os.path.join(test_dir, filename)
            
            # Create transcript file in AWS Transcribe format
            transcript_data = {
                "jobName": f"test-job-{file_count}",
                "accountId": "123456789",
                "results": {
                    "transcripts": [
                        {
                            "transcript": transcript
                        }
                    ],
                    "items": create_transcript_items(transcript)
                },
                "status": "COMPLETED"
            }
            
            # Write transcript file
            with open(filepath, 'w') as f:
                json.dump(transcript_data, f, indent=2)
            
            # Add to manifest
            test_manifest.append({
                "file": filename,
                "category": category,
                "expected_rules": rule_codes,
                "transcript": transcript,
                "expected_entities": get_expected_entities(transcript, category),
                "expected_violations": len(rule_codes) > 0
            })
    
    # Generate additional random combinations to reach 100
    while file_count < 100:
        file_count += 1
        
        # Pick random scenario and transcript
        scenario = random.choice(test_scenarios)
        transcript = random.choice(scenario["transcripts"])
        transcript = add_variations(transcript, file_count)
        
        filename = f"test_{file_count:03d}_random_{scenario['category']}.json"
        filepath = os.path.join(test_dir, filename)
        
        transcript_data = {
            "jobName": f"test-job-{file_count}",
            "accountId": "123456789", 
            "results": {
                "transcripts": [{"transcript": transcript}],
                "items": create_transcript_items(transcript)
            },
            "status": "COMPLETED"
        }
        
        with open(filepath, 'w') as f:
            json.dump(transcript_data, f, indent=2)
        
        test_manifest.append({
            "file": filename,
            "category": scenario["category"],
            "expected_rules": scenario["rule_codes"],
            "transcript": transcript,
            "expected_entities": get_expected_entities(transcript, scenario["category"]),
            "expected_violations": len(scenario["rule_codes"]) > 0
        })
    
    # Write test manifest
    manifest_path = os.path.join(test_dir, "test_manifest.json")
    with open(manifest_path, 'w') as f:
        json.dump({
            "generated_at": datetime.now().isoformat(),
            "total_files": len(test_manifest),
            "categories": list(set(item["category"] for item in test_manifest)),
            "files": test_manifest
        }, f, indent=2)
    
    print(f"✅ Generated {file_count} test transcript files in {test_dir}")
    print(f"📋 Test manifest created: {manifest_path}")
    
    # Create upload script
    create_upload_script(test_dir)
    
    return test_dir, manifest_path

def add_variations(transcript, variation_num):
    """Add variations to transcripts to make them unique"""
    
    # Name variations
    names = ["Robert Williams", "Lisa Brown", "David Miller", "Sarah Johnson", "Michael Davis"]
    amounts = ["$1,200", "$2,500", "$850", "$3,400", "$1,750"]
    agents = ["Mike", "Sarah", "John", "Lisa", "Tom"]
    
    # Replace with variations
    if "Robert Williams" in transcript:
        transcript = transcript.replace("Robert Williams", random.choice(names))
    
    if "$" in transcript:
        import re
        transcript = re.sub(r'\$[\d,]+(?:\.\d{2})?', random.choice(amounts), transcript)
    
    # Add variation-specific elements
    if variation_num % 3 == 0:
        transcript += " This is urgent and requires immediate attention."
    elif variation_num % 3 == 1:
        transcript += " Please call us back at your earliest convenience."
    else:
        transcript += " We need to resolve this matter today."
    
    return transcript

def create_transcript_items(transcript):
    """Create AWS Transcribe items format"""
    words = transcript.split()
    items = []
    
    start_time = 0.0
    for word in words:
        items.append({
            "start_time": str(start_time),
            "end_time": str(start_time + 0.5),
            "alternatives": [
                {
                    "confidence": "0.99",
                    "content": word
                }
            ],
            "type": "pronunciation"
        })
        start_time += 0.6
    
    return items

def get_expected_entities(transcript, category):
    """Get expected entities for a transcript based on category"""
    expected = {
        "persons": [],
        "organizations": [],
        "pii_entities": [],
        "compliance_entities": {
            "agent_names": [],
            "customer_names": [],
            "company_identification": [],
            "legal_terms": [],
            "threatening_language": [],
            "medical_terms": [],
            "financial_data": [],
            "communication_methods": [],
            "state_references": []
        }
    }
    
    transcript_lower = transcript.lower()
    
    # Agent names
    if any(phrase in transcript_lower for phrase in ["my name is", "this is"]):
        expected["compliance_entities"]["agent_names"].append("detected")
    
    # Company identification
    if any(company in transcript_lower for company in ["anycompany servicing", "alley servicing", "ally servicing"]):
        expected["compliance_entities"]["company_identification"].append("detected")
    
    # Legal terms
    if any(term in transcript_lower for term in ["attorney", "lawyer", "bankruptcy", "legal action"]):
        expected["compliance_entities"]["legal_terms"].append("detected")
    
    # Threatening language
    if any(threat in transcript_lower for threat in ["garnish", "repossess", "arrest", "jail"]):
        expected["compliance_entities"]["threatening_language"].append("detected")
    
    # Medical terms
    if any(term in transcript_lower for term in ["medical", "hospital", "doctor", "surgery"]):
        expected["compliance_entities"]["medical_terms"].append("detected")
    
    # Financial data
    if "$" in transcript or any(term in transcript_lower for term in ["balance", "payment", "account"]):
        expected["compliance_entities"]["financial_data"].append("detected")
    
    # Communication methods
    if any(method in transcript_lower for method in ["text message", "email", "voicemail", "sms"]):
        expected["compliance_entities"]["communication_methods"].append("detected")
    
    # State references
    if any(state in transcript_lower for state in ["massachusetts", "michigan", "texas", "arizona"]):
        expected["compliance_entities"]["state_references"].append("detected")
    
    return expected

def create_upload_script(test_dir):
    """Create script to upload test files to S3 for processing"""
    
    upload_script = f"""#!/bin/bash

# Upload test transcript files to S3 for processing
BUCKET="anycompany-transcribe-output-prod-164543933824"
TEST_DIR="{test_dir}"

echo "🚀 Uploading test transcript files to S3..."

# Upload all test files to transcripts/ prefix
for file in $TEST_DIR/test_*.json; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        echo "Uploading $filename..."
        aws s3 cp "$file" "s3://$BUCKET/transcripts/$filename"
        
        # Small delay to avoid overwhelming the system
        sleep 0.5
    fi
done

echo "✅ Upload complete! Check DynamoDB and UI for results."
echo "📊 Monitor processing with: aws logs tail /aws/lambda/anycompany-transcription-complete-prod --follow"
"""
    
    script_path = os.path.join(test_dir, "upload_tests.sh")
    with open(script_path, 'w') as f:
        f.write(upload_script)
    
    os.chmod(script_path, 0o755)
    print(f"📤 Upload script created: {script_path}")

if __name__ == "__main__":
    test_dir, manifest_path = generate_test_files()
    
    print("\n🎯 Test Files Generated:")
    print(f"   📁 Directory: {test_dir}")
    print(f"   📋 Manifest: {manifest_path}")
    print(f"   📤 Upload script: {test_dir}/upload_tests.sh")
    print("\n🚀 To test:")
    print(f"   cd {test_dir}")
    print("   ./upload_tests.sh")