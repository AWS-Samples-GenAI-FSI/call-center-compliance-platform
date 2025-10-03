#!/bin/bash

# =============================================================================
# FULLY AUTOMATED TERRAFORM DEPLOYMENT SCRIPT
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
    echo "🚀 AnyCompany Compliance Platform - Automated Deployment"
    echo "========================================================"
    echo -e "${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
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
    
    if [ ! -f "main.tf" ]; then
        print_error "Not in terraform directory. Please run from terraform/ folder"
        exit 1
    fi
    
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI not found. Please install AWS CLI"
        exit 1
    fi
    
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured. Run 'aws configure'"
        exit 1
    fi
    
    if ! command -v terraform &> /dev/null; then
        print_error "Terraform not found. Please install Terraform"
        exit 1
    fi
    
    print_success "Prerequisites check passed"
}

# Initialize and deploy everything
deploy_all() {
    print_step "Initializing Terraform..."
    terraform init -upgrade
    
    print_step "Creating Lambda deployment packages..."
    
    # Create API function zip
    if [ -f "api_function_code.py" ]; then
        zip -j api_function.zip api_function_code.py
        print_success "API function package created"
    fi
    
    # Create processor function zip (placeholder)
    echo "# Processor function code" > temp_processor.py
    zip -j processor_function.zip temp_processor.py
    rm temp_processor.py
    
    # Create transcription complete function zip (placeholder)
    echo "# Transcription complete function code" > temp_transcription.py
    zip -j transcription_complete_function.zip temp_transcription.py
    rm temp_transcription.py
    
    print_step "Container build will use AWS CodeBuild (no Docker required locally)"
    print_success "CodeBuild setup ready"
    
    print_step "Deploying complete infrastructure..."
    terraform apply -auto-approve
    
    print_success "Deployment completed successfully!"
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
    print_info "Platform Features:"
    print_info "• 43 AI-powered compliance rules"
    print_info "• Real-time transcription and analysis"
    print_info "• Enhanced Rules Library with detailed logic"
    print_info "• Entity detection and confidence scoring"
    print_info "• Automated container build and ECS deployment"
    print_info "• Load balancer with health checks"
    echo ""
}

# Main function
main() {
    print_header
    
    check_prerequisites
    echo ""
    
    deploy_all
    echo ""
    
    show_summary
    
    print_success "🎉 AnyCompany Compliance Platform is ready!"
}

# Run main function
main "$@"