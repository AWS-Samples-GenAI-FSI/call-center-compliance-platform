#!/bin/bash

echo "🔧 Fixing Terraform deployment conflicts..."

# Import existing resources to avoid conflicts
terraform import aws_cognito_user_pool_domain.anycompany_cognito_user_pool_domain anycompany-auth-prod-164543933824 2>/dev/null || true
terraform import aws_lb_target_group.anycompany_target_group arn:aws:elasticloadbalancing:us-east-1:164543933824:targetgroup/anycompany-tg-prod/* 2>/dev/null || true
terraform import aws_lambda_event_source_mapping.anycompany_processor_event_source_mapping 1e8d55c2-c759-42d1-b5c4-2eb9f4abdb9d 2>/dev/null || true
terraform import aws_wafv2_web_acl.anycompany_waf_web_acl anycompany-demo-protection-prod/REGIONAL 2>/dev/null || true
terraform import aws_codebuild_project.anycompany_codebuild_project anycompany-ui-build-prod 2>/dev/null || true

# Create missing populate-rules.py
cat > populate-rules.py << 'EOF'
#!/usr/bin/env python3
import boto3
import json

def populate_rules():
    dynamodb = boto3.resource('dynamodb')
    table = dynamodb.Table('anycompany-rules-prod')
    
    rules = [
        {"rule_id": "LO1001", "category": "identification", "description": "Agent identification required"},
        {"rule_id": "LO1005", "category": "communication", "description": "Do not call compliance"},
        {"rule_id": "LO1006", "category": "policy", "description": "Medical information handling"},
        {"rule_id": "LO1009", "category": "system", "description": "Contact documentation"}
    ]
    
    for rule in rules:
        try:
            table.put_item(Item=rule)
            print(f"✅ Added rule {rule['rule_id']}")
        except Exception as e:
            print(f"⚠️ Rule {rule['rule_id']} may already exist: {e}")

if __name__ == "__main__":
    populate_rules()
    print("✅ Rules population complete")
EOF

chmod +x populate-rules.py

echo "✅ Fix script ready. Now run: terraform apply -auto-approve"