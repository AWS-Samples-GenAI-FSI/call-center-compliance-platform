#!/bin/bash

# =============================================================================
# INTERACTIVE TERRAFORM DEPLOYMENT SCRIPT
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${CYAN}"
    echo "🚀 AnyCompany Compliance Platform Deployment"
    echo "============================================="
    echo -e "${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_step() {
    echo -e "${CYAN}🎯 $1${NC}"
}

# Check prerequisites
check_prerequisites() {
    print_step "Checking prerequisites..."
    
    # Check if we're in terraform directory
    if [ ! -f "main.tf" ]; then
        print_error "Not in terraform directory. Please run from terraform/ folder"
        exit 1
    fi
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI not found. Please install AWS CLI"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured. Run 'aws configure'"
        exit 1
    fi
    
    # Check Terraform
    if ! command -v terraform &> /dev/null; then
        print_error "Terraform not found. Please install Terraform"
        exit 1
    fi
    
    print_success "Prerequisites check passed"
}

# Show deployment options
show_deployment_options() {
    echo ""
    print_step "Deployment Options:"
    echo ""
    echo "1. 🏗️  Full Deployment (Infrastructure + Lambda + Container + ECS)"
    echo "2. 🔧 Infrastructure Only (No Lambda updates or container builds)"
    echo "3. 🤖 Lambda Functions Only (Update compliance rules)"
    echo "4. 🐳 Container Build Only (Rebuild and deploy UI)"
    echo "5. 📊 Rules Population Only (Populate DynamoDB with 43 rules)"
    echo "6. 🔍 Plan Only (Show what will be created/changed)"
    echo "7. ❌ Cancel"
    echo ""
}

# Get user choice
get_user_choice() {
    while true; do
        read -p "Select deployment option (1-7): " choice
        case $choice in
            [1-7]) break;;
            *) print_warning "Please enter a number between 1-7";;
        esac
    done
    echo $choice
}

# Initialize Terraform
init_terraform() {
    print_step "Initializing Terraform..."
    
    if [ ! -d ".terraform" ]; then
        terraform init
    else
        terraform init -upgrade
    fi
    
    print_success "Terraform initialized"
}

# Show deployment plan
show_plan() {
    print_step "Generating deployment plan..."
    terraform plan
}

# Deploy infrastructure only
deploy_infrastructure() {
    print_step "Deploying infrastructure only..."
    terraform apply -target=aws_vpc.anycompany_vpc \
                   -target=aws_s3_bucket.anycompany_input_bucket \
                   -target=aws_s3_bucket.anycompany_source_bucket \
                   -target=aws_s3_bucket.anycompany_transcribe_output_bucket \
                   -target=aws_s3_bucket.anycompany_comprehend_output_bucket \
                   -target=aws_dynamodb_table.anycompany_calls_table \
                   -target=aws_dynamodb_table.anycompany_rules_table \
                   -target=aws_lambda_function.anycompany_api_function \
                   -target=aws_lambda_function.anycompany_processor_function \
                   -target=aws_lambda_function.anycompany_transcription_complete_function \
                   -target=aws_api_gateway_rest_api.anycompany_rest_api \
                   -target=aws_ecs_cluster.anycompany_ecs_cluster \
                   -target=aws_lb.anycompany_alb
}

# Deploy Lambda functions only
deploy_lambda_only() {
    print_step "Deploying Lambda functions only..."
    terraform apply -target=null_resource.deploy_lambda_functions
}

# Deploy container only
deploy_container_only() {
    print_step "Building and deploying container only..."
    terraform apply -target=null_resource.build_container \
                   -target=null_resource.update_ecs_service
}

# Populate rules only
populate_rules_only() {
    print_step "Populating rules only..."
    terraform apply -target=null_resource.populate_rules
}

# Full deployment
deploy_full() {
    print_step "Starting full deployment..."
    
    echo ""
    print_warning "This will deploy:"
    print_info "• Complete AWS infrastructure (75+ resources)"
    print_info "• AI-powered Lambda functions with 43 compliance rules"
    print_info "• React UI container with proper API configuration"
    print_info "• ECS service with load balancer"
    print_info "• DynamoDB populated with compliance rules"
    echo ""
    
    read -p "Continue with full deployment? (y/N): " confirm
    if [[ $confirm =~ ^[Yy]$ ]]; then
        terraform apply
    else
        print_info "Deployment cancelled"
        exit 0
    fi
}

# Show deployment summary
show_summary() {
    print_step "Deployment Summary:"
    echo ""
    
    # Get outputs
    API_ENDPOINT=$(terraform output -raw api_endpoint 2>/dev/null || echo "Not available")
    APP_URL=$(terraform output -raw application_url 2>/dev/null || echo "Not available")
    INPUT_BUCKET=$(terraform output -raw input_bucket 2>/dev/null || echo "Not available")
    
    print_success "🌐 API Endpoint: $API_ENDPOINT"
    print_success "🖥️  Application URL: $APP_URL"
    print_success "📦 Input Bucket: $INPUT_BUCKET"
    
    echo ""
    print_info "Next steps:"
    print_info "1. Visit the application URL to access the compliance dashboard"
    print_info "2. Upload audio files to test AI-powered compliance detection"
    print_info "3. View real-time AI quality metrics and confidence scores"
    echo ""
}

# Main deployment function
main() {
    print_header
    
    check_prerequisites
    
    show_deployment_options
    choice=$(get_user_choice)
    
    echo ""
    init_terraform
    echo ""
    
    case $choice in
        1)
            deploy_full
            show_summary
            ;;
        2)
            deploy_infrastructure
            print_success "Infrastructure deployment completed"
            ;;
        3)
            deploy_lambda_only
            print_success "Lambda functions deployment completed"
            ;;
        4)
            deploy_container_only
            print_success "Container build and deployment completed"
            ;;
        5)
            populate_rules_only
            print_success "Rules population completed"
            ;;
        6)
            show_plan
            ;;
        7)
            print_info "Deployment cancelled"
            exit 0
            ;;
    esac
    
    echo ""
    print_success "🎉 Deployment process completed!"
}

# Run main function
main "$@"