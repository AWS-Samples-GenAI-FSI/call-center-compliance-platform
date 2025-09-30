#!/bin/bash

# AnyCompany Compliance Platform - Terraform Deployment Script
set -e

echo "🚀 AnyCompany Compliance Platform - Terraform Deployment"
echo "========================================================"

# Check if terraform is installed
if ! command -v terraform &> /dev/null; then
    echo "❌ Terraform is not installed. Please install Terraform first."
    exit 1
fi

# Check if AWS CLI is configured
if ! aws sts get-caller-identity &> /dev/null; then
    echo "❌ AWS CLI is not configured. Please run 'aws configure' first."
    exit 1
fi

# Create terraform.tfvars if it doesn't exist
if [ ! -f "terraform.tfvars" ]; then
    echo "📝 Creating terraform.tfvars from example..."
    cp terraform.tfvars.example terraform.tfvars
    echo "⚠️  Please edit terraform.tfvars with your specific values before continuing."
    read -p "Press Enter to continue after editing terraform.tfvars..."
fi

# Deployment options
echo ""
echo "Select deployment option:"
echo "1. Full deployment (Infrastructure + Lambda + ECS)"
echo "2. Infrastructure only"
echo "3. Plan only (no deployment)"
echo "4. Destroy all resources"
echo ""
read -p "Enter your choice (1-4): " choice

case $choice in
    1)
        echo "🏗️  Full deployment selected"
        terraform init
        terraform plan -out=tfplan
        echo ""
        read -p "Review the plan above. Continue with deployment? (y/N): " confirm
        if [[ $confirm == [yY] ]]; then
            terraform apply tfplan
            echo "✅ Full deployment completed!"
        else
            echo "❌ Deployment cancelled"
        fi
        ;;
    2)
        echo "🏗️  Infrastructure only deployment"
        terraform init
        terraform plan -var="deploy_ecs=false" -out=tfplan
        echo ""
        read -p "Review the plan above. Continue with deployment? (y/N): " confirm
        if [[ $confirm == [yY] ]]; then
            terraform apply tfplan
            echo "✅ Infrastructure deployment completed!"
            echo "💡 To deploy ECS later, set deploy_ecs=true in terraform.tfvars and run this script again"
        else
            echo "❌ Deployment cancelled"
        fi
        ;;
    3)
        echo "📋 Planning deployment..."
        terraform init
        terraform plan
        echo "✅ Plan completed!"
        ;;
    4)
        echo "💥 Destroying all resources..."
        echo "⚠️  WARNING: This will delete ALL resources and data!"
        read -p "Are you absolutely sure? Type 'yes' to confirm: " confirm
        if [[ $confirm == "yes" ]]; then
            terraform destroy
            echo "✅ All resources destroyed!"
        else
            echo "❌ Destroy cancelled"
        fi
        ;;
    *)
        echo "❌ Invalid choice"
        exit 1
        ;;
esac

echo ""
echo "🎉 Deployment script completed!"