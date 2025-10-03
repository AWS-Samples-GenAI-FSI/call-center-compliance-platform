#!/bin/bash

# =============================================================================
# TERRAFORM CLEANUP SCRIPT
# =============================================================================
# This script will COMPLETELY DELETE all Terraform-managed AWS resources
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_error() {
    echo -e "${RED}❌ ERROR: $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  WARNING: $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  INFO: $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ SUCCESS: $1${NC}"
}

print_status() {
    echo -e "${GREEN}🎯 $1${NC}"
}

# Safety confirmation
confirm_action() {
    echo -e "${RED}"
    echo "⚠️  DANGER ZONE ⚠️"
    echo "==================="
    echo "You are about to DESTROY all Terraform-managed AWS resources!"
    echo "This action is IRREVERSIBLE!"
    echo -e "${NC}"
    
    read -p "Type 'DESTROY' to confirm (anything else will cancel): " confirmation
    
    if [ "$confirmation" != "DESTROY" ]; then
        print_info "Operation cancelled by user"
        exit 0
    fi
}

# Aggressively empty and delete S3 buckets
empty_s3_buckets() {
    print_info "FORCE emptying and deleting ALL S3 buckets..."
    
    # Get bucket names from Terraform state AND scan for anycompany buckets
    BUCKETS=$(terraform show -json 2>/dev/null | jq -r '.values.root_module.resources[] | select(.type == "aws_s3_bucket") | .values.id' 2>/dev/null || echo "")
    
    # Also scan for any remaining anycompany buckets
    SCAN_BUCKETS=$(aws s3api list-buckets --query 'Buckets[?contains(Name, `anycompany`)].Name' --output text 2>/dev/null || echo "")
    
    # Combine both lists
    ALL_BUCKETS="$BUCKETS $SCAN_BUCKETS"
    
    if [ -n "$ALL_BUCKETS" ]; then
        for bucket in $ALL_BUCKETS; do
            if [ -z "$bucket" ] || [ "$bucket" = "None" ]; then
                continue
            fi
            
            if aws s3 ls "s3://$bucket" &>/dev/null; then
                print_info "FORCE processing bucket: $bucket"
                
                # Remove bucket policy that might prevent deletion
                aws s3api delete-bucket-policy --bucket "$bucket" 2>/dev/null || true
                
                # Disable versioning
                aws s3api put-bucket-versioning --bucket "$bucket" --versioning-configuration Status=Suspended 2>/dev/null || true
                
                # Force empty ALL contents
                aws s3 rm "s3://$bucket" --recursive --quiet 2>/dev/null || true
                
                # Remove ALL versions and delete markers (multiple attempts)
                for attempt in {1..3}; do
                    print_info "Attempt $attempt: Removing versions from $bucket"
                    
                    # Delete all versions
                    aws s3api list-object-versions --bucket "$bucket" --output json 2>/dev/null | \
                    jq -r '.Versions[]? | select(.Key != null) | "\(.Key)\t\(.VersionId)"' | \
                    while IFS=$'\t' read -r key version_id; do
                        if [ ! -z "$key" ] && [ ! -z "$version_id" ]; then
                            aws s3api delete-object --bucket "$bucket" --key "$key" --version-id "$version_id" 2>/dev/null || true
                        fi
                    done
                    
                    # Delete all delete markers
                    aws s3api list-object-versions --bucket "$bucket" --output json 2>/dev/null | \
                    jq -r '.DeleteMarkers[]? | select(.Key != null) | "\(.Key)\t\(.VersionId)"' | \
                    while IFS=$'\t' read -r key version_id; do
                        if [ ! -z "$key" ] && [ ! -z "$version_id" ]; then
                            aws s3api delete-object --bucket "$bucket" --key "$key" --version-id "$version_id" 2>/dev/null || true
                        fi
                    done
                    
                    # Check if bucket is empty
                    OBJECT_COUNT=$(aws s3api list-object-versions --bucket "$bucket" --query 'length(Versions)' --output text 2>/dev/null || echo "0")
                    if [ "$OBJECT_COUNT" = "0" ] || [ "$OBJECT_COUNT" = "None" ]; then
                        break
                    fi
                    sleep 2
                done
                
                # Alternative sync method to ensure complete emptying
                mkdir -p /tmp/empty_dir
                aws s3 sync /tmp/empty_dir s3://$bucket --delete --quiet 2>/dev/null || true
                rmdir /tmp/empty_dir 2>/dev/null || true
                
                # Force delete the bucket itself
                aws s3 rb "s3://$bucket" --force 2>/dev/null || true
                
                print_success "Bucket $bucket FORCE deleted"
            else
                print_info "Bucket $bucket does not exist or already deleted"
            fi
        done
    else
        print_info "No S3 buckets found"
    fi
}

# Stop ECS services before destroy
stop_ecs_services() {
    print_info "Stopping ECS services..."
    
    # Get ECS service info from Terraform state
    SERVICES=$(terraform show -json 2>/dev/null | jq -r '.values.root_module.resources[] | select(.type == "aws_ecs_service") | "\(.values.cluster)|\(.values.name)"' 2>/dev/null || echo "")
    
    if [ -n "$SERVICES" ]; then
        for service_info in $SERVICES; do
            IFS='|' read -r cluster service <<< "$service_info"
            if [ ! -z "$cluster" ] && [ ! -z "$service" ]; then
                print_info "Stopping ECS service: $service in cluster: $cluster"
                aws ecs update-service --cluster "$cluster" --service "$service" --desired-count 0 --quiet 2>/dev/null || true
                print_success "ECS service $service stopped"
            fi
        done
    else
        print_info "No ECS services found in Terraform state"
    fi
}

# Main cleanup function
main_cleanup() {
    echo -e "${BLUE}"
    echo "🧹 TERRAFORM CLEANUP SCRIPT"
    echo "============================"
    echo "This will destroy ALL Terraform-managed resources"
    echo -e "${NC}"
    
    # Check if we're in the terraform directory
    if [ ! -f "main.tf" ]; then
        print_error "Not in terraform directory. Please run from terraform/ folder"
        exit 1
    fi
    
    # Check if Terraform is initialized
    if [ ! -d ".terraform" ]; then
        print_error "Terraform not initialized. Run 'terraform init' first"
        exit 1
    fi
    
    # Final confirmation
    confirm_action
    
    print_status "Starting Terraform cleanup process..."
    
    # Step 1: Pre-cleanup - empty S3 buckets and stop ECS services
    print_info "Step 1: Pre-cleanup tasks..."
    empty_s3_buckets
    stop_ecs_services
    
    # Step 2: Terraform destroy with retries
    print_info "Step 2: Running terraform destroy..."
    
    # Try terraform destroy up to 3 times
    for attempt in {1..3}; do
        print_info "Terraform destroy attempt $attempt/3"
        
        if terraform destroy -auto-approve; then
            print_success "Terraform destroy completed successfully"
            break
        else
            print_warning "Terraform destroy attempt $attempt failed"
            if [ $attempt -eq 3 ]; then
                print_error "All terraform destroy attempts failed"
                print_warning "Continuing with nuclear cleanup..."
            else
                print_info "Retrying in 10 seconds..."
                sleep 10
            fi
        fi
    done
    
    # Step 3: Nuclear cleanup - scan and delete any remaining resources
    print_info "Step 3: Nuclear cleanup - scanning for remaining resources..."
    
    # Delete any remaining ECR repositories
    print_info "Cleaning up ECR repositories..."
    aws ecr describe-repositories --query 'repositories[?contains(repositoryName, `anycompany`)].repositoryName' --output text 2>/dev/null | tr '\t' '\n' | while read repo; do
        if [ ! -z "$repo" ] && [ "$repo" != "None" ]; then
            print_info "Force deleting ECR repository: $repo"
            aws ecr delete-repository --repository-name "$repo" --force 2>/dev/null || true
        fi
    done
    
    # Delete any remaining Lambda functions
    print_info "Cleaning up Lambda functions..."
    aws lambda list-functions --query 'Functions[?contains(FunctionName, `anycompany`)].FunctionName' --output text 2>/dev/null | tr '\t' '\n' | while read func; do
        if [ ! -z "$func" ] && [ "$func" != "None" ]; then
            print_info "Force deleting Lambda function: $func"
            aws lambda delete-function --function-name "$func" 2>/dev/null || true
        fi
    done
    
    # Delete any remaining DynamoDB tables
    print_info "Cleaning up DynamoDB tables..."
    aws dynamodb list-tables --query 'TableNames[?contains(@, `anycompany`)]' --output text 2>/dev/null | tr '\t' '\n' | while read table; do
        if [ ! -z "$table" ] && [ "$table" != "None" ]; then
            print_info "Force deleting DynamoDB table: $table"
            aws dynamodb delete-table --table-name "$table" 2>/dev/null || true
        fi
    done
    
    # Delete any remaining API Gateways
    print_info "Cleaning up API Gateways..."
    aws apigateway get-rest-apis --query 'items[?contains(name, `anycompany`)].id' --output text 2>/dev/null | tr '\t' '\n' | while read api_id; do
        if [ ! -z "$api_id" ] && [ "$api_id" != "None" ]; then
            print_info "Force deleting API Gateway: $api_id"
            aws apigateway delete-rest-api --rest-api-id "$api_id" 2>/dev/null || true
        fi
    done
    
    # Delete any remaining ECS clusters
    print_info "Cleaning up ECS clusters..."
    aws ecs list-clusters --query 'clusterArns[?contains(@, `anycompany`)]' --output text 2>/dev/null | tr '\t' '\n' | while read cluster_arn; do
        if [ ! -z "$cluster_arn" ] && [ "$cluster_arn" != "None" ]; then
            local cluster_name=$(basename "$cluster_arn")
            print_info "Force deleting ECS cluster: $cluster_name"
            
            # Delete all services in cluster first
            aws ecs list-services --cluster "$cluster_name" --query 'serviceArns' --output text 2>/dev/null | tr '\t' '\n' | while read service_arn; do
                if [ ! -z "$service_arn" ] && [ "$service_arn" != "None" ]; then
                    local service_name=$(basename "$service_arn")
                    aws ecs update-service --cluster "$cluster_name" --service "$service_name" --desired-count 0 2>/dev/null || true
                    aws ecs delete-service --cluster "$cluster_name" --service "$service_name" 2>/dev/null || true
                fi
            done
            
            # Delete cluster
            aws ecs delete-cluster --cluster "$cluster_name" 2>/dev/null || true
        fi
    done
    
    # Delete CloudWatch Log Groups
    print_info "Cleaning up CloudWatch Log Groups..."
    aws logs describe-log-groups --query 'logGroups[?contains(logGroupName, `anycompany`) || contains(logGroupName, `/ecs/anycompany`)].logGroupName' --output text 2>/dev/null | tr '\t' '\n' | while read log_group; do
        if [ ! -z "$log_group" ] && [ "$log_group" != "None" ]; then
            print_info "Force deleting CloudWatch Log Group: $log_group"
            aws logs delete-log-group --log-group-name "$log_group" 2>/dev/null || true
        fi
    done
    
    # Delete Load Balancers
    print_info "Cleaning up Load Balancers..."
    aws elbv2 describe-load-balancers --query 'LoadBalancers[?contains(LoadBalancerName, `anycompany`)].LoadBalancerArn' --output text 2>/dev/null | tr '\t' '\n' | while read lb_arn; do
        if [ ! -z "$lb_arn" ] && [ "$lb_arn" != "None" ]; then
            print_info "Force deleting Load Balancer: $lb_arn"
            aws elbv2 delete-load-balancer --load-balancer-arn "$lb_arn" 2>/dev/null || true
        fi
    done
    
    # Delete Target Groups
    print_info "Cleaning up Target Groups..."
    aws elbv2 describe-target-groups --query 'TargetGroups[?contains(TargetGroupName, `anycompany`)].TargetGroupArn' --output text 2>/dev/null | tr '\t' '\n' | while read tg_arn; do
        if [ ! -z "$tg_arn" ] && [ "$tg_arn" != "None" ]; then
            print_info "Force deleting Target Group: $tg_arn"
            aws elbv2 delete-target-group --target-group-arn "$tg_arn" 2>/dev/null || true
        fi
    done
    
    # Delete IAM Roles
    print_info "Cleaning up IAM Roles..."
    aws iam list-roles --query 'Roles[?contains(RoleName, `anycompany`)].RoleName' --output text 2>/dev/null | tr '\t' '\n' | while read role_name; do
        if [ ! -z "$role_name" ] && [ "$role_name" != "None" ]; then
            print_info "Force deleting IAM Role: $role_name"
            
            # Detach all policies first
            aws iam list-attached-role-policies --role-name "$role_name" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null | tr '\t' '\n' | while read policy_arn; do
                if [ ! -z "$policy_arn" ] && [ "$policy_arn" != "None" ]; then
                    aws iam detach-role-policy --role-name "$role_name" --policy-arn "$policy_arn" 2>/dev/null || true
                fi
            done
            
            # Delete inline policies
            aws iam list-role-policies --role-name "$role_name" --query 'PolicyNames' --output text 2>/dev/null | tr '\t' '\n' | while read policy_name; do
                if [ ! -z "$policy_name" ] && [ "$policy_name" != "None" ]; then
                    aws iam delete-role-policy --role-name "$role_name" --policy-name "$policy_name" 2>/dev/null || true
                fi
            done
            
            # Delete role
            aws iam delete-role --role-name "$role_name" 2>/dev/null || true
        fi
    done
    
    # Delete WAF Web ACLs
    print_info "Cleaning up WAF Web ACLs..."
    aws wafv2 list-web-acls --scope REGIONAL --query 'WebACLs[?contains(Name, `anycompany`)].{Name:Name,Id:Id}' --output text 2>/dev/null | while read name id; do
        if [ ! -z "$name" ] && [ "$name" != "None" ] && [ ! -z "$id" ] && [ "$id" != "None" ]; then
            print_info "Force deleting WAF Web ACL: $name"
            
            # Get lock token
            LOCK_TOKEN=$(aws wafv2 get-web-acl --scope REGIONAL --id "$id" --name "$name" --query 'LockToken' --output text 2>/dev/null || echo "")
            if [ ! -z "$LOCK_TOKEN" ] && [ "$LOCK_TOKEN" != "None" ]; then
                aws wafv2 delete-web-acl --scope REGIONAL --id "$id" --name "$name" --lock-token "$LOCK_TOKEN" 2>/dev/null || true
            fi
        fi
    done
    
    # Step 4: Wait for resources to be deleted
    print_info "Step 4: Waiting for resources to be fully deleted..."
    sleep 10
    
    # Step 5: Clean up local files
    print_info "Step 5: Cleaning up local Terraform files..."
    
    rm -f terraform.tfstate terraform.tfstate.backup 2>/dev/null || true
    rm -f ../anycompany-ui-source.zip 2>/dev/null || true
    rm -f ../populate-rules.py 2>/dev/null || true
    rm -rf .terraform/terraform.tfstate 2>/dev/null || true
    
    print_success "Local files cleaned up"
    
    print_status "Cleanup process completed!"
    echo ""
    print_success "🎉 All Terraform-managed AWS resources have been destroyed!"
    echo ""
    print_warning "Remember to:"
    print_warning "1. Check AWS Console to verify all resources are deleted"
    print_warning "2. Review your AWS bill to ensure no unexpected charges"
    print_warning "3. Run 'terraform init' if you want to deploy again"
    echo ""
}

# Script options
show_help() {
    echo "Terraform Cleanup Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --force      Skip confirmations (DANGEROUS!)"
    echo "  --help       Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0           # Interactive cleanup with confirmations"
    echo "  $0 --force   # Cleanup without confirmations (DANGEROUS!)"
}

# Parse command line arguments
FORCE_MODE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_MODE=true
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Override confirmation function if force mode
if [ "$FORCE_MODE" = true ]; then
    confirm_action() {
        print_warning "Force mode enabled - skipping confirmation"
    }
fi

# Run the cleanup
main_cleanup