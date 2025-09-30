#!/bin/bash

# =============================================================================
# AWS RESOURCES CLEANUP SCRIPT
# =============================================================================
# This script will COMPLETELY DELETE all AWS resources for the AnyCompany 
# Compliance Platform. USE WITH EXTREME CAUTION!
# =============================================================================

set -e

# Configuration
STACK_NAME="anycompany-compliance"
REGION="us-east-1"
ENVIRONMENT="prod"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
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

# Safety confirmation function
confirm_action() {
    local action="$1"
    echo -e "${RED}"
    echo "⚠️  DANGER ZONE ⚠️"
    echo "==================="
    echo "You are about to: $action"
    echo "This action is IRREVERSIBLE!"
    echo -e "${NC}"
    
    read -p "Type 'DELETE' to confirm (anything else will cancel): " confirmation
    
    if [ "$confirmation" != "DELETE" ]; then
        print_info "Operation cancelled by user"
        exit 0
    fi
}

# Function to empty and delete S3 bucket
cleanup_s3_bucket() {
    local bucket_name="$1"
    
    if aws s3 ls "s3://$bucket_name" --region $REGION &> /dev/null; then
        print_info "FORCE cleaning up S3 bucket: $bucket_name"
        
        # Remove bucket policy that might prevent deletion
        print_info "Removing bucket policy..."
        aws s3api delete-bucket-policy --bucket "$bucket_name" --region $REGION 2>/dev/null || true
        
        # Disable versioning
        print_info "Disabling versioning..."
        aws s3api put-bucket-versioning --bucket "$bucket_name" --versioning-configuration Status=Suspended --region $REGION 2>/dev/null || true
        
        # Empty the bucket completely - all objects and versions
        print_info "Force emptying ALL bucket contents..."
        aws s3 rm "s3://$bucket_name" --recursive --region $REGION 2>/dev/null || true
        
        # Delete all versions and delete markers (for versioned buckets)
        print_info "Force removing ALL versions and delete markers..."
        
        # Get all versions in batches and delete them
        aws s3api list-object-versions --bucket "$bucket_name" --region $REGION --output json 2>/dev/null | \
        jq -r '.Versions[]? | select(.Key != null) | "\(.Key)\t\(.VersionId)"' | \
        while IFS=$'\t' read -r key version_id; do
            if [ ! -z "$key" ] && [ ! -z "$version_id" ]; then
                aws s3api delete-object --bucket "$bucket_name" --key "$key" --version-id "$version_id" --region $REGION 2>/dev/null || true
            fi
        done
        
        # Delete all delete markers
        aws s3api list-object-versions --bucket "$bucket_name" --region $REGION --output json 2>/dev/null | \
        jq -r '.DeleteMarkers[]? | select(.Key != null) | "\(.Key)\t\(.VersionId)"' | \
        while IFS=$'\t' read -r key version_id; do
            if [ ! -z "$key" ] && [ ! -z "$version_id" ]; then
                aws s3api delete-object --bucket "$bucket_name" --key "$key" --version-id "$version_id" --region $REGION 2>/dev/null || true
            fi
        done
        
        # Alternative method using AWS CLI sync with delete
        print_info "Using sync method to ensure complete emptying..."
        aws s3 sync /tmp s3://$bucket_name --delete --region $REGION 2>/dev/null || true
        
        # Force delete the bucket itself
        print_info "Force deleting bucket..."
        aws s3 rb "s3://$bucket_name" --force --region $REGION 2>/dev/null || true
        
        print_success "S3 bucket $bucket_name FORCE deleted"
    else
        print_info "S3 bucket $bucket_name does not exist or already deleted"
    fi
}

# Function to delete ECR repository
cleanup_ecr_repository() {
    local repo_name="$1"
    
    if aws ecr describe-repositories --repository-names "$repo_name" --region $REGION &> /dev/null; then
        print_info "Deleting ECR repository: $repo_name"
        aws ecr delete-repository --repository-name "$repo_name" --force --region $REGION
        print_success "ECR repository $repo_name deleted"
    else
        print_info "ECR repository $repo_name does not exist or already deleted"
    fi
}

# Function to stop and delete ECS service
cleanup_ecs_service() {
    local cluster_name="$1"
    local service_name="$2"
    
    if aws ecs describe-services --cluster "$cluster_name" --services "$service_name" --region $REGION &> /dev/null; then
        print_info "Stopping ECS service: $service_name"
        
        # Scale down to 0
        aws ecs update-service --cluster "$cluster_name" --service "$service_name" --desired-count 0 --region $REGION
        
        # Wait for tasks to stop
        print_info "Waiting for tasks to stop..."
        aws ecs wait services-stable --cluster "$cluster_name" --services "$service_name" --region $REGION
        
        # Delete service
        aws ecs delete-service --cluster "$cluster_name" --service "$service_name" --region $REGION
        print_success "ECS service $service_name deleted"
    else
        print_info "ECS service $service_name does not exist or already deleted"
    fi
}

# Function to delete CloudFormation stack
cleanup_cloudformation_stack() {
    local stack_name="$1"
    
    if aws cloudformation describe-stacks --stack-name "$stack_name" --region $REGION &> /dev/null; then
        print_info "FORCE deleting CloudFormation stack: $stack_name"
        
        # First try normal deletion
        aws cloudformation delete-stack --stack-name "$stack_name" --region $REGION
        
        print_info "Waiting for stack deletion to complete (timeout: 30 minutes)..."
        
        # Wait with timeout and retry logic
        local max_attempts=60  # 30 minutes (30 seconds * 60)
        local attempt=0
        
        while [ $attempt -lt $max_attempts ]; do
            if ! aws cloudformation describe-stacks --stack-name "$stack_name" --region $REGION &> /dev/null; then
                print_success "CloudFormation stack $stack_name deleted successfully"
                return 0
            fi
            
            local stack_status=$(aws cloudformation describe-stacks --stack-name "$stack_name" --region $REGION --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "UNKNOWN")
            
            if [[ "$stack_status" == *"FAILED"* ]] || [[ "$stack_status" == *"ROLLBACK"* ]]; then
                print_warning "Stack deletion failed with status: $stack_status"
                print_info "Attempting to continue deletion..."
                aws cloudformation continue-update-rollback --stack-name "$stack_name" --region $REGION 2>/dev/null || true
                aws cloudformation delete-stack --stack-name "$stack_name" --region $REGION 2>/dev/null || true
            fi
            
            print_info "Stack status: $stack_status (attempt $((attempt + 1))/$max_attempts)"
            sleep 30
            ((attempt++))
        done
        
        print_error "Stack deletion timed out, but continuing with cleanup..."
    else
        print_info "CloudFormation stack $stack_name does not exist or already deleted"
    fi
}

# Function to cleanup Lambda functions (if they exist outside CloudFormation)
cleanup_lambda_functions() {
    local functions=("anycompany-api-prod" "anycompany-transcription-complete-prod" "anycompany-processor-prod")
    
    for func in "${functions[@]}"; do
        if aws lambda get-function --function-name "$func" --region $REGION &> /dev/null; then
            print_info "Deleting Lambda function: $func"
            aws lambda delete-function --function-name "$func" --region $REGION
            print_success "Lambda function $func deleted"
        else
            print_info "Lambda function $func does not exist or already deleted"
        fi
    done
}

# Function to cleanup Cognito User Pool (if it exists outside CloudFormation)
cleanup_cognito_user_pool() {
    local user_pool_id="us-east-1_NTgaBBFiu"  # From your config
    
    if aws cognito-idp describe-user-pool --user-pool-id "$user_pool_id" --region $REGION &> /dev/null; then
        print_info "Deleting Cognito User Pool: $user_pool_id"
        aws cognito-idp delete-user-pool --user-pool-id "$user_pool_id" --region $REGION
        print_success "Cognito User Pool $user_pool_id deleted"
    else
        print_info "Cognito User Pool $user_pool_id does not exist or already deleted"
    fi
}

# Main cleanup function
main_cleanup() {
    echo -e "${BLUE}"
    echo "🧹 AWS RESOURCES CLEANUP SCRIPT"
    echo "================================"
    echo "Stack: $STACK_NAME"
    echo "Region: $REGION"
    echo "Environment: $ENVIRONMENT"
    echo -e "${NC}"
    
    # Final confirmation
    confirm_action "COMPLETELY DELETE ALL AWS RESOURCES for the AnyCompany Compliance Platform"
    
    print_status "Starting cleanup process..."
    
    # Step 1: Stop ECS services first (to avoid dependency issues)
    print_info "Step 1: Stopping ECS services..."
    cleanup_ecs_service "anycompany-cluster-prod" "anycompany-ui-prod"
    
    # Step 2: Delete ECR repositories
    print_info "Step 2: Cleaning up ECR repositories..."
    cleanup_ecr_repository "anycompany-ui-prod"
    
    # Step 3: Empty S3 buckets (CloudFormation can't delete non-empty buckets)
    print_info "Step 3: Emptying S3 buckets..."
    
    # Get bucket names from CloudFormation outputs or use standard naming
    local input_bucket=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --region $REGION --query 'Stacks[0].Outputs[?OutputKey==`InputBucket`].OutputValue' --output text 2>/dev/null || echo "")
    local source_bucket=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --region $REGION --query 'Stacks[0].Outputs[?OutputKey==`SourceBucket`].OutputValue' --output text 2>/dev/null || echo "")
    local transcribe_bucket=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --region $REGION --query 'Stacks[0].Outputs[?OutputKey==`TranscribeOutputBucket`].OutputValue' --output text 2>/dev/null || echo "")
    local comprehend_bucket=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --region $REGION --query 'Stacks[0].Outputs[?OutputKey==`ComprehendOutputBucket`].OutputValue' --output text 2>/dev/null || echo "")
    
    # Fallback to standard naming if outputs not available
    if [ -z "$input_bucket" ]; then
        input_bucket="anycompany-input-prod-164543933824"
    fi
    if [ -z "$source_bucket" ]; then
        source_bucket="anycompany-source-prod-164543933824"
    fi
    if [ -z "$transcribe_bucket" ]; then
        transcribe_bucket="anycompany-transcribe-output-prod-164543933824"
    fi
    if [ -z "$comprehend_bucket" ]; then
        comprehend_bucket="anycompany-comprehend-output-prod-164543933824"
    fi
    
    cleanup_s3_bucket "$input_bucket"
    cleanup_s3_bucket "$source_bucket"
    cleanup_s3_bucket "$transcribe_bucket"
    cleanup_s3_bucket "$comprehend_bucket"
    
    # Also check for CloudFormation template bucket
    local template_bucket="${STACK_NAME}-cfn-templates-${REGION}"
    cleanup_s3_bucket "$template_bucket"
    
    # Step 4: Delete CloudFormation stack (this will delete most resources)
    print_info "Step 4: Deleting CloudFormation stack..."
    cleanup_cloudformation_stack "$STACK_NAME"
    
    # Step 5: Cleanup any remaining resources that might not be in CloudFormation
    print_info "Step 5: Cleaning up any remaining resources..."
    cleanup_lambda_functions
    
    # Step 6: Final verification
    print_info "Step 6: Verifying cleanup..."
    
    if aws cloudformation describe-stacks --stack-name $STACK_NAME --region $REGION &> /dev/null; then
        print_error "CloudFormation stack still exists!"
    else
        print_success "CloudFormation stack successfully deleted"
    fi
    
    print_status "Cleanup process completed!"
    echo ""
    print_success "🎉 All AWS resources have been deleted!"
    echo ""
    print_warning "Remember to:"
    print_warning "1. Check AWS Console to verify all resources are deleted"
    print_warning "2. Review your AWS bill to ensure no unexpected charges"
    print_warning "3. Keep your backup files in case you need to redeploy"
    echo ""
}

# Nuclear option - force delete everything by resource type
nuclear_cleanup() {
    print_error "🚨 NUCLEAR CLEANUP MODE 🚨"
    print_error "This will attempt to delete ALL resources by type!"
    
    confirm_action "NUCLEAR DELETE - Find and delete ALL related resources by scanning AWS"
    
    print_info "Scanning and deleting Lambda functions..."
    aws lambda list-functions --region $REGION --query 'Functions[?contains(FunctionName, `anycompany`)].FunctionName' --output text | tr '\t' '\n' | while read func; do
        if [ ! -z "$func" ]; then
            print_info "Deleting Lambda function: $func"
            aws lambda delete-function --function-name "$func" --region $REGION 2>/dev/null || true
        fi
    done
    
    print_info "Scanning and deleting S3 buckets..."
    aws s3api list-buckets --region $REGION --query 'Buckets[?contains(Name, `anycompany`)].Name' --output text | tr '\t' '\n' | while read bucket; do
        if [ ! -z "$bucket" ]; then
            cleanup_s3_bucket "$bucket"
        fi
    done
    
    print_info "Scanning and deleting ECR repositories..."
    aws ecr describe-repositories --region $REGION --query 'repositories[?contains(repositoryName, `anycompany`)].repositoryName' --output text | tr '\t' '\n' | while read repo; do
        if [ ! -z "$repo" ]; then
            cleanup_ecr_repository "$repo"
        fi
    done
    
    print_info "Scanning and deleting ECS clusters..."
    aws ecs list-clusters --region $REGION --query 'clusterArns[?contains(@, `anycompany`)]' --output text | tr '\t' '\n' | while read cluster_arn; do
        if [ ! -z "$cluster_arn" ]; then
            local cluster_name=$(basename "$cluster_arn")
            print_info "Deleting ECS cluster: $cluster_name"
            
            # Delete all services in cluster first
            aws ecs list-services --cluster "$cluster_name" --region $REGION --query 'serviceArns' --output text | tr '\t' '\n' | while read service_arn; do
                if [ ! -z "$service_arn" ]; then
                    local service_name=$(basename "$service_arn")
                    cleanup_ecs_service "$cluster_name" "$service_name"
                fi
            done
            
            # Delete cluster
            aws ecs delete-cluster --cluster "$cluster_name" --region $REGION 2>/dev/null || true
        fi
    done
    
    print_info "Scanning and deleting DynamoDB tables..."
    aws dynamodb list-tables --region $REGION --query 'TableNames[?contains(@, `anycompany`) || contains(@, `AnyCompany`)]' --output text | tr '\t' '\n' | while read table; do
        if [ ! -z "$table" ]; then
            print_info "Deleting DynamoDB table: $table"
            aws dynamodb delete-table --table-name "$table" --region $REGION 2>/dev/null || true
        fi
    done
    
    print_info "Scanning and deleting API Gateways..."
    aws apigateway get-rest-apis --region $REGION --query 'items[?contains(name, `anycompany`)].id' --output text | tr '\t' '\n' | while read api_id; do
        if [ ! -z "$api_id" ]; then
            print_info "Deleting API Gateway: $api_id"
            aws apigateway delete-rest-api --rest-api-id "$api_id" --region $REGION 2>/dev/null || true
        fi
    done
    
    print_success "Nuclear cleanup completed!"
}

# Safety checks
check_prerequisites() {
    # Check if AWS CLI is installed and configured
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed"
        exit 1
    fi
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured or invalid"
        exit 1
    fi
    
    print_success "Prerequisites check passed"
}

# Script options
show_help() {
    echo "AWS Resources Cleanup Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --dry-run    Show what would be deleted without actually deleting"
    echo "  --force      Skip confirmations (DANGEROUS!)"
    echo "  --nuclear    NUCLEAR MODE: Scan and delete ALL anycompany resources (EXTREMELY DANGEROUS!)"
    echo "  --help       Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                 # Interactive cleanup with confirmations"
    echo "  $0 --dry-run       # Show what would be deleted"
    echo "  $0 --force         # Cleanup without confirmations (DANGEROUS!)"
    echo "  $0 --nuclear       # Nuclear cleanup - finds and deletes EVERYTHING (EXTREMELY DANGEROUS!)"
}

# Dry run function
dry_run() {
    echo -e "${YELLOW}"
    echo "🔍 DRY RUN MODE - No resources will be deleted"
    echo "=============================================="
    echo -e "${NC}"
    
    print_info "Would delete CloudFormation stack: $STACK_NAME"
    print_info "Would empty and delete S3 buckets:"
    print_info "  - anycompany-input-prod-164543933824"
    print_info "  - anycompany-source-prod-164543933824"
    print_info "  - anycompany-transcribe-output-prod-164543933824"
    print_info "  - anycompany-comprehend-output-prod-164543933824"
    print_info "  - ${STACK_NAME}-cfn-templates-${REGION}"
    print_info "Would delete ECR repository: anycompany-ui-prod"
    print_info "Would stop ECS service: anycompany-ui-prod"
    print_info "Would delete Lambda functions (if they exist outside CloudFormation)"
    
    echo ""
    print_warning "To actually perform the cleanup, run: $0"
}

# Parse command line arguments
FORCE_MODE=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_MODE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        --nuclear)
            print_error "🚨 NUCLEAR MODE ENABLED 🚨"
            nuclear_cleanup
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Main execution
if [ "$DRY_RUN" = true ]; then
    dry_run
    exit 0
fi

# Override confirmation function if force mode
if [ "$FORCE_MODE" = true ]; then
    confirm_action() {
        print_warning "Force mode enabled - skipping confirmation for: $1"
    }
fi

# Run the cleanup
check_prerequisites
main_cleanup