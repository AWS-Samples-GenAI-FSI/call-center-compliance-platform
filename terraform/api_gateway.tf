# API Gateway
resource "aws_api_gateway_rest_api" "anycompany_rest_api" {
  name        = "anycompany-api-${var.environment}"
  description = "AnyCompany Compliance Platform API"
}

# API Gateway Resource
resource "aws_api_gateway_resource" "anycompany_api_resource" {
  rest_api_id = aws_api_gateway_rest_api.anycompany_rest_api.id
  parent_id   = aws_api_gateway_rest_api.anycompany_rest_api.root_resource_id
  path_part   = "{proxy+}"
}

# API Gateway Method
resource "aws_api_gateway_method" "anycompany_api_method" {
  rest_api_id   = aws_api_gateway_rest_api.anycompany_rest_api.id
  resource_id   = aws_api_gateway_resource.anycompany_api_resource.id
  http_method   = "ANY"
  authorization = "NONE"
}

# API Gateway Integration
resource "aws_api_gateway_integration" "anycompany_api_integration" {
  rest_api_id = aws_api_gateway_rest_api.anycompany_rest_api.id
  resource_id = aws_api_gateway_resource.anycompany_api_resource.id
  http_method = aws_api_gateway_method.anycompany_api_method.http_method

  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.anycompany_api_function.invoke_arn
}

# API Gateway OPTIONS Method for CORS
resource "aws_api_gateway_method" "anycompany_api_options_method" {
  rest_api_id   = aws_api_gateway_rest_api.anycompany_rest_api.id
  resource_id   = aws_api_gateway_resource.anycompany_api_resource.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

# API Gateway OPTIONS Integration
resource "aws_api_gateway_integration" "anycompany_api_options_integration" {
  rest_api_id = aws_api_gateway_rest_api.anycompany_rest_api.id
  resource_id = aws_api_gateway_resource.anycompany_api_resource.id
  http_method = aws_api_gateway_method.anycompany_api_options_method.http_method

  type = "MOCK"
  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

# API Gateway Method Response for OPTIONS
resource "aws_api_gateway_method_response" "anycompany_api_options_method_response" {
  rest_api_id = aws_api_gateway_rest_api.anycompany_rest_api.id
  resource_id = aws_api_gateway_resource.anycompany_api_resource.id
  http_method = aws_api_gateway_method.anycompany_api_options_method.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers"     = true
    "method.response.header.Access-Control-Allow-Methods"     = true
    "method.response.header.Access-Control-Allow-Origin"      = true
    "method.response.header.Access-Control-Allow-Credentials" = true
  }
}

# API Gateway Integration Response for OPTIONS
resource "aws_api_gateway_integration_response" "anycompany_api_options_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.anycompany_rest_api.id
  resource_id = aws_api_gateway_resource.anycompany_api_resource.id
  http_method = aws_api_gateway_method.anycompany_api_options_method.http_method
  status_code = aws_api_gateway_method_response.anycompany_api_options_method_response.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers"     = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods"     = "'GET,POST,PUT,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"      = "'*'"
    "method.response.header.Access-Control-Allow-Credentials" = "'true'"
  }
}

# API Gateway Deployment
resource "aws_api_gateway_deployment" "anycompany_api_deployment" {
  depends_on = [
    aws_api_gateway_method.anycompany_api_method,
    aws_api_gateway_method.anycompany_api_options_method,
    aws_api_gateway_integration.anycompany_api_integration,
    aws_api_gateway_integration.anycompany_api_options_integration
  ]

  rest_api_id = aws_api_gateway_rest_api.anycompany_rest_api.id
  stage_name  = "prod"
}