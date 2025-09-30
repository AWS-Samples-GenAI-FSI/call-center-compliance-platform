#!/bin/bash

# Script to upload Terraform files to GitHub
# Run this after creating a new GitHub repository

echo "🚀 Preparing Terraform files for GitHub upload"

# Initialize git if not already done
if [ ! -d ".git" ]; then
    git init
    echo "✅ Git repository initialized"
fi

# Create .gitignore for Terraform
cat > .gitignore << EOF
# Terraform files
*.tfstate
*.tfstate.*
.terraform/
.terraform.lock.hcl
terraform.tfvars
*.zip

# OS files
.DS_Store
Thumbs.db

# IDE files
.vscode/
.idea/
*.swp
*.swo
EOF

# Add Terraform files
git add main.tf
git add lambda.tf
git add api_gateway.tf
git add cognito_ecs.tf
git add notifications.tf
git add aws_services.tf
git add terraform.tfvars.example
git add deploy-terraform.sh
git add TERRAFORM.md
git add .gitignore

# Commit
git commit -m "Add Terraform infrastructure for AnyCompany Compliance Platform

- Complete infrastructure as code conversion from CloudFormation
- Includes VPC, S3, DynamoDB, Lambda, API Gateway, Cognito, ECS
- Added deployment script and documentation
- Ready for production deployment"

echo "✅ Files committed locally"
echo ""
echo "Next steps:"
echo "1. Create a new repository on GitHub"
echo "2. Run: git remote add origin https://github.com/YOUR_USERNAME/YOUR_REPO.git"
echo "3. Run: git branch -M main"
echo "4. Run: git push -u origin main"