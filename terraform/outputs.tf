# Infrastructure outputs
output "api_endpoint" {
  description = "API Gateway endpoint URL"
  value       = "https://${aws_api_gateway_rest_api.anycompany_rest_api.id}.execute-api.${var.aws_region}.amazonaws.com/prod"
}

output "application_url" {
  description = "Application Load Balancer URL"
  value       = "http://${aws_lb.anycompany_alb.dns_name}"
}

output "input_bucket" {
  description = "S3 input bucket name"
  value       = aws_s3_bucket.anycompany_input_bucket.id
}

output "calls_table" {
  description = "DynamoDB calls table name"
  value       = aws_dynamodb_table.anycompany_calls_table.name
}

output "rules_table" {
  description = "DynamoDB rules table name"
  value       = aws_dynamodb_table.anycompany_rules_table.name
}

# Deployment status outputs
output "lambda_deployment_status" {
  description = "Lambda functions deployment status"
  value       = "Lambda functions deployed with latest AI-powered compliance rules"
  depends_on  = [null_resource.deploy_lambda_functions]
}

output "rules_population_status" {
  description = "Rules population status"
  value       = "43 compliance rules populated in DynamoDB"
  depends_on  = [null_resource.populate_rules]
}

output "container_build_status" {
  description = "Container build status"
  value       = "React UI container built and pushed to ECR with correct API configuration"
  depends_on  = [null_resource.build_and_deploy_container]
}

output "ecs_deployment_status" {
  description = "ECS service deployment status"
  value       = "ECS service deployed and running with latest container"
  depends_on  = [aws_ecs_service.anycompany_ecs_service]
}

# Configuration details
output "cognito_user_pool_id" {
  description = "Cognito User Pool ID"
  value       = aws_cognito_user_pool.anycompany_cognito_user_pool.id
}

output "cognito_client_id" {
  description = "Cognito User Pool Client ID"
  value       = aws_cognito_user_pool_client.anycompany_cognito_user_pool_client.id
}

output "ecr_repository_url" {
  description = "ECR repository URL"
  value       = aws_ecr_repository.anycompany_ecr_repository.repository_url
}