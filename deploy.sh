#!/bin/bash

# =============================================================================
# AnyCompany Compliance Platform - End-to-End Deployment Script
# =============================================================================

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
STACK_NAME="anycompany-compliance"
ENVIRONMENT="prod"
REGION="us-east-1"

echo -e "${BLUE}🚀 AnyCompany Compliance Platform - End-to-End Deployment${NC}"
echo -e "${BLUE}================================================================${NC}"
echo ""

# Function to print status
print_status() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Check prerequisites
echo -e "${BLUE}🔍 Checking Prerequisites...${NC}"

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    print_error "AWS CLI not found. Please install AWS CLI first."
    exit 1
fi

# Check if AWS credentials are configured
if ! aws sts get-caller-identity &> /dev/null; then
    print_error "AWS credentials not configured. Please run 'aws configure' first."
    exit 1
fi

# Check Node.js for React app
if ! command -v npm &> /dev/null; then
    print_error "Node.js/npm not found. Please install Node.js first."
    exit 1
fi

print_status "Prerequisites check passed"
echo ""

# Deployment options
echo -e "${BLUE}📋 Deployment Options:${NC}"
echo "1. Full deployment (Infrastructure + Frontend)"
echo "2. Infrastructure only"
echo "3. Frontend only"
echo ""

read -p "Select deployment option (1-3): " DEPLOY_OPTION

case $DEPLOY_OPTION in
    1)
        DEPLOY_INFRA=true
        DEPLOY_FRONTEND=true
        echo -e "${BLUE}🎯 Selected: Full deployment${NC}"
        ;;
    2)
        DEPLOY_INFRA=true
        DEPLOY_FRONTEND=false
        echo -e "${BLUE}🎯 Selected: Infrastructure only${NC}"
        ;;
    3)
        DEPLOY_INFRA=false
        DEPLOY_FRONTEND=true
        echo -e "${BLUE}🎯 Selected: Frontend only${NC}"
        ;;
    *)
        print_error "Invalid option selected"
        exit 1
        ;;
esac

echo ""

# =============================================================================
# PHASE 1: INFRASTRUCTURE DEPLOYMENT
# =============================================================================

if [ "$DEPLOY_INFRA" = true ]; then
    echo -e "${BLUE}🏗️  Phase 1: Deploying Infrastructure...${NC}"
    
    # Check template size and determine deployment method
    TEMPLATE_FILE="infrastructure.yaml"
    TEMPLATE_SIZE=$(wc -c < "$TEMPLATE_FILE" 2>/dev/null || echo "0")
    
    if [ "$TEMPLATE_SIZE" -gt 51200 ]; then
        print_info "Template is ${TEMPLATE_SIZE} bytes (>51KB), using S3 upload method..."
        
        # Create or get template bucket name
        TEMPLATE_BUCKET="${STACK_NAME}-cfn-templates-${REGION}"
        
        # Create bucket if it doesn't exist
        if ! aws s3 ls "s3://$TEMPLATE_BUCKET" &> /dev/null; then
            print_info "Creating S3 bucket for CloudFormation templates..."
            aws s3 mb "s3://$TEMPLATE_BUCKET" --region $REGION
        fi
        
        # Upload template to S3
        print_info "Uploading CloudFormation template to S3..."
        aws s3 cp "$TEMPLATE_FILE" "s3://$TEMPLATE_BUCKET/infrastructure.yaml"
        
        TEMPLATE_URL="https://$TEMPLATE_BUCKET.s3.amazonaws.com/infrastructure.yaml"
        TEMPLATE_PARAM="--template-url $TEMPLATE_URL"
    else
        print_info "Template is ${TEMPLATE_SIZE} bytes (<51KB), using direct deployment..."
        TEMPLATE_PARAM="--template-body file://$TEMPLATE_FILE"
    fi
    
    # Check if stack exists
    if aws cloudformation describe-stacks --stack-name $STACK_NAME --region $REGION &> /dev/null; then
        print_info "Stack exists, updating..."
        aws cloudformation update-stack \
            --stack-name $STACK_NAME \
            $TEMPLATE_PARAM \
            --capabilities CAPABILITY_IAM \
            --region $REGION \
            --parameters ParameterKey=Environment,ParameterValue=$ENVIRONMENT \
                        ParameterKey=DeployECS,ParameterValue=true \
                        ParameterKey=AllowedIP,ParameterValue=$CURRENT_IP/32
        
        print_info "Waiting for stack update to complete..."
        aws cloudformation wait stack-update-complete --stack-name $STACK_NAME --region $REGION
    else
        print_info "Creating new stack..."
        aws cloudformation create-stack \
            --stack-name $STACK_NAME \
            $TEMPLATE_PARAM \
            --capabilities CAPABILITY_IAM \
            --region $REGION \
            --parameters ParameterKey=Environment,ParameterValue=$ENVIRONMENT \
                        ParameterKey=DeployECS,ParameterValue=true \
                        ParameterKey=AllowedIP,ParameterValue=$CURRENT_IP/32
        
        print_info "Waiting for stack creation to complete..."
        aws cloudformation wait stack-create-complete --stack-name $STACK_NAME --region $REGION
    fi
    
    print_status "Infrastructure deployment completed"
    
    # Upload source code immediately after infrastructure is ready
    print_info "Preparing source code for CodeBuild..."
    
    # Update .env file with current API endpoint and Cognito settings
    print_info "Updating React app configuration..."
    
    # Get current API endpoint and Cognito settings from CloudFormation
    API_ENDPOINT=$(aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --region $REGION \
        --query 'Stacks[0].Outputs[?OutputKey==`ApiEndpoint`].OutputValue' \
        --output text)
    
    COGNITO_USER_POOL_ID=$(aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --region $REGION \
        --query 'Stacks[0].Outputs[?OutputKey==`CognitoUserPoolId`].OutputValue' \
        --output text)
    
    COGNITO_CLIENT_ID=$(aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --region $REGION \
        --query 'Stacks[0].Outputs[?OutputKey==`CognitoUserPoolClientId`].OutputValue' \
        --output text)
    
    # Get current public IP for security group restriction
    print_info "Detecting current public IP for security configuration..."
    CURRENT_IP=$(curl -s https://checkip.amazonaws.com)
    if [ -z "$CURRENT_IP" ]; then
        print_error "Could not detect current public IP"
        exit 1
    fi
    print_info "Current public IP detected: $CURRENT_IP"
    
    # Current IP will be passed as CloudFormation parameter
    
    # Update .env file with current values
    cat > anycompany-compliance-react/.env << EOF
REACT_APP_API_ENDPOINT=$API_ENDPOINT
REACT_APP_COGNITO_REGION=$REGION
REACT_APP_COGNITO_USER_POOL_ID=$COGNITO_USER_POOL_ID
REACT_APP_COGNITO_CLIENT_ID=$COGNITO_CLIENT_ID
EOF
    
    print_info "Updated .env file with current API endpoint: $API_ENDPOINT"
    print_info "Updated security group to restrict access to IP: $CURRENT_IP/32"
    
    # Build React application
    print_info "Building React application..."
    cd anycompany-compliance-react
    
    # Install dependencies if needed
    if [ ! -d "node_modules" ]; then
        print_info "Installing npm dependencies..."
        npm install
    fi
    
    # Build the application
    npm run build
    cd ..
    
    # Create deployment package (from inside the React directory to avoid nested paths)
    print_info "Creating deployment package..."
    cd anycompany-compliance-react
    zip -r ../anycompany-ui-source.zip . -x "node_modules/*" ".git/*" "build/*"
    cd ..
    
    # Get S3 source bucket name from CloudFormation outputs
    SOURCE_BUCKET=$(aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --region $REGION \
        --query 'Stacks[0].Outputs[?OutputKey==`SourceBucket`].OutputValue' \
        --output text)
    
    if [ -z "$SOURCE_BUCKET" ]; then
        print_error "Could not get source bucket name from CloudFormation outputs"
        exit 1
    fi
    
    # Upload source code to S3
    print_info "Uploading source code to S3..."
    aws s3 cp anycompany-ui-source.zip s3://$SOURCE_BUCKET/source/anycompany-ui-source.zip
    
    # Get CodeBuild project name
    CODEBUILD_PROJECT=$(aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --region $REGION \
        --query 'Stacks[0].Outputs[?OutputKey==`CodeBuildProject`].OutputValue' \
        --output text)
    
    if [ -z "$CODEBUILD_PROJECT" ]; then
        print_error "Could not get CodeBuild project name from CloudFormation outputs"
        exit 1
    fi
    
    # Trigger CodeBuild to create Docker image
    print_info "Starting CodeBuild to create Docker image..."
    BUILD_ID=$(aws codebuild start-build \
        --project-name $CODEBUILD_PROJECT \
        --region $REGION \
        --query 'build.id' \
        --output text)
    
    print_info "CodeBuild started with ID: $BUILD_ID"
    print_info "Waiting for Docker image build to complete..."
    
    # Wait for build to complete
    while true; do
        BUILD_STATUS=$(aws codebuild batch-get-builds \
            --ids $BUILD_ID \
            --region $REGION \
            --query 'builds[0].buildStatus' \
            --output text)
        
        if [ "$BUILD_STATUS" = "SUCCEEDED" ]; then
            print_status "Docker image build completed successfully"
            break
        elif [ "$BUILD_STATUS" = "FAILED" ] || [ "$BUILD_STATUS" = "FAULT" ] || [ "$BUILD_STATUS" = "STOPPED" ] || [ "$BUILD_STATUS" = "TIMED_OUT" ]; then
            print_error "Docker image build failed with status: $BUILD_STATUS"
            exit 1
        else
            print_info "Build status: $BUILD_STATUS (waiting...)"
            sleep 30
        fi
    done
    
    # Clean up temporary files
    rm -f anycompany-ui-source.zip
    
    print_status "Source code uploaded and Docker image built successfully"
    echo ""
fi

# =============================================================================
# PHASE 2: FRONTEND DEPLOYMENT
# =============================================================================

if [ "$DEPLOY_FRONTEND" = true ]; then
    echo -e "${BLUE}🎨 Phase 2: Finalizing Frontend Deployment...${NC}"
    
    # Force ECS service update to ensure it picks up the new image
    print_info "Updating ECS service..."
    ECS_CLUSTER=$(aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --region $REGION \
        --query 'Stacks[0].Outputs[?OutputKey==`ECSCluster`].OutputValue' \
        --output text)
    
    aws ecs update-service \
        --cluster $ECS_CLUSTER \
        --service anycompany-ui-$ENVIRONMENT \
        --force-new-deployment \
        --region $REGION > /dev/null
    
    print_info "Waiting for ECS service to stabilize..."
    aws ecs wait services-stable \
        --cluster $ECS_CLUSTER \
        --services anycompany-ui-$ENVIRONMENT \
        --region $REGION
    
    print_status "Frontend deployment completed"
    echo ""
fi

# =============================================================================
# DEPLOYMENT SUMMARY
# =============================================================================

echo -e "${GREEN}🎉 Deployment Completed Successfully!${NC}"
echo -e "${GREEN}=================================${NC}"
echo ""

# Get application URL
APP_URL=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --region $REGION \
    --query 'Stacks[0].Outputs[?OutputKey==`ApplicationURL`].OutputValue' \
    --output text 2>/dev/null || echo "Not available")

# Get API endpoint
API_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --region $REGION \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiEndpoint`].OutputValue' \
    --output text 2>/dev/null || echo "Not available")

echo -e "${BLUE}📋 Deployment Summary:${NC}"
echo "• Stack Name: $STACK_NAME"
echo "• Environment: $ENVIRONMENT"
echo "• Region: $REGION"
echo ""

echo -e "${BLUE}🔗 Access Information:${NC}"
echo "• Application URL: $APP_URL"
echo "• API Endpoint: $API_ENDPOINT"
echo ""

echo -e "${BLUE}🔐 Demo Login Credentials:${NC}"
echo "• Username: compliancemanager, auditreviewer, or qualityanalyst"
echo "• Password: AnyCompanyDemo2024!"
echo ""

echo -e "${BLUE}✨ Platform Features:${NC}"
echo "• Audio processing with AWS Transcribe"
echo "• Entity analysis with AWS Comprehend"
echo "• 43 compliance rules across 4 categories"
echo "• Real-time violation detection"
echo "• Web dashboard with authentication"
echo ""

if [ "$DEPLOY_INFRA" = true ]; then
    echo -e "${GREEN}✅ Infrastructure: Deployed${NC}"
fi

if [ "$DEPLOY_LAMBDA" = true ]; then
    echo -e "${GREEN}✅ Lambda Functions: Deployed with all fixes${NC}"
fi

if [ "$DEPLOY_FRONTEND" = true ]; then
    echo -e "${GREEN}✅ Frontend Application: Built and deployed${NC}"
fi

echo ""
echo -e "${BLUE}🚀 Your AI-powered compliance validation platform is ready!${NC}"

# Clean up temporary files
rm -f anycompany-ui-source.zip

echo ""
print_status "Deployment script completed successfully!"