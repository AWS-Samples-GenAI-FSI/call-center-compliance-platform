# Lambda function deployments with latest code
resource "null_resource" "deploy_lambda_functions" {
  depends_on = [
    aws_lambda_function.anycompany_api_function,
    aws_lambda_function.anycompany_processor_function,
    aws_lambda_function.anycompany_transcription_complete_function
  ]

  triggers = {
    # Redeploy when Lambda code changes
    api_code_hash = data.archive_file.api_function_zip.output_base64sha256
    processor_code_hash = data.archive_file.processor_function_zip.output_base64sha256
    transcription_code_hash = data.archive_file.transcription_complete_function_zip.output_base64sha256
  }

  provisioner "local-exec" {
    command = "cd ../lambda-functions && bash deploy-all.sh"
  }
}

# Populate DynamoDB rules table
resource "null_resource" "populate_rules" {
  depends_on = [
    aws_dynamodb_table.anycompany_rules_table,
    null_resource.deploy_lambda_functions
  ]

  triggers = {
    # Repopulate if table is recreated
    rules_table_arn = aws_dynamodb_table.anycompany_rules_table.arn
  }

  provisioner "local-exec" {
    command = "cd .. && python3 populate-rules.py"
  }
}

# Automated container build using CodeBuild (like CloudFormation)
resource "null_resource" "build_and_deploy_container" {
  depends_on = [
    aws_codebuild_project.anycompany_codebuild_project,
    aws_s3_bucket.anycompany_source_bucket
  ]

  triggers = {
    # Always rebuild on deployment
    timestamp = timestamp()
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "🚀 Starting CodeBuild container deployment..."
      
      # Configure React app
      cd ../anycompany-compliance-react
      cat > .env << EOF
REACT_APP_API_ENDPOINT=https://${aws_api_gateway_rest_api.anycompany_rest_api.id}.execute-api.${var.aws_region}.amazonaws.com/prod
REACT_APP_COGNITO_REGION=${var.aws_region}
REACT_APP_COGNITO_USER_POOL_ID=${aws_cognito_user_pool.anycompany_cognito_user_pool.id}
REACT_APP_COGNITO_CLIENT_ID=${aws_cognito_user_pool_client.anycompany_cognito_user_pool_client.id}
EOF
      
      # Create source zip and upload to S3
      echo "📦 Creating source package..."
      zip -r ../anycompany-ui-source.zip . -x "node_modules/*" ".git/*"
      cd ..
      aws s3 cp anycompany-ui-source.zip s3://${aws_s3_bucket.anycompany_source_bucket.id}/source/anycompany-ui-source.zip
      
      # Start CodeBuild
      echo "🏗️ Starting CodeBuild..."
      BUILD_ID=$(aws codebuild start-build --project-name ${aws_codebuild_project.anycompany_codebuild_project.name} --query 'build.id' --output text)
      
      # Wait for build completion
      echo "⏳ Waiting for build to complete..."
      aws codebuild wait build-complete --ids $BUILD_ID
      
      echo "✅ CodeBuild container deployment completed"
    EOT
  }
}

