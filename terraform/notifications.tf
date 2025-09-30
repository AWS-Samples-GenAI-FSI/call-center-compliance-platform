# SQS Queue Policy
resource "aws_sqs_queue_policy" "anycompany_queue_policy" {
  queue_url = aws_sqs_queue.anycompany_processing_queue.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.anycompany_processing_queue.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_s3_bucket.anycompany_input_bucket.arn
          }
        }
      }
    ]
  })
}

# S3 Bucket Notification for Input Bucket
resource "aws_s3_bucket_notification" "anycompany_input_bucket_notification" {
  bucket = aws_s3_bucket.anycompany_input_bucket.id

  queue {
    queue_arn = aws_sqs_queue.anycompany_processing_queue.arn
    events    = ["s3:ObjectCreated:*"]

    filter_prefix = "audio/"
    filter_suffix = ".wav"
  }

  depends_on = [aws_sqs_queue_policy.anycompany_queue_policy]
}

# S3 Bucket Notification for Transcribe Output Bucket
resource "aws_s3_bucket_notification" "anycompany_transcribe_output_bucket_notification" {
  bucket = aws_s3_bucket.anycompany_transcribe_output_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.anycompany_transcription_complete_function.arn
    events              = ["s3:ObjectCreated:*"]

    filter_prefix = "transcripts/"
    filter_suffix = ".json"
  }

  depends_on = [aws_lambda_permission.s3_invoke_transcription_complete]
}

# WAF Web ACL
resource "aws_wafv2_web_acl" "anycompany_waf_web_acl" {
  name  = "anycompany-demo-protection-${var.environment}"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "RateLimitRule"
    priority = 1

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 100
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimitRule"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"

        rule_action_override {
          action_to_use {
            allow {}
          }
          name = "GenericLFI_BODY"
        }

        rule_action_override {
          action_to_use {
            allow {}
          }
          name = "GenericRFI_BODY"
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "CommonRuleSetMetric"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "anycompany-demo-waf-${var.environment}"
    sampled_requests_enabled   = true
  }

  tags = {
    Name        = "anycompany-demo-protection-${var.environment}"
    Environment = var.environment
  }
}

# WAF Web ACL Association
resource "aws_wafv2_web_acl_association" "anycompany_waf_association" {
  resource_arn = aws_lb.anycompany_alb.arn
  web_acl_arn  = aws_wafv2_web_acl.anycompany_waf_web_acl.arn
}

# CodeBuild Role
resource "aws_iam_role" "anycompany_codebuild_role" {
  name = "anycompany-codebuild-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "codebuild.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "codebuild_policy" {
  name = "CodeBuildPolicy"
  role = aws_iam_role.anycompany_codebuild_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion"
        ]
        Resource = "${aws_s3_bucket.anycompany_source_bucket.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:GetAuthorizationToken",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage"
        ]
        Resource = "*"
      }
    ]
  })
}

# CodeBuild Project
resource "aws_codebuild_project" "anycompany_codebuild_project" {
  name         = "anycompany-ui-build-${var.environment}"
  service_role = aws_iam_role.anycompany_codebuild_role.arn

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type = "BUILD_GENERAL1_MEDIUM"
    image        = "aws/codebuild/standard:7.0"
    type         = "LINUX_CONTAINER"
    privileged_mode = true

    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = var.aws_region
    }

    environment_variable {
      name  = "AWS_ACCOUNT_ID"
      value = data.aws_caller_identity.current.account_id
    }

    environment_variable {
      name  = "IMAGE_REPO_NAME"
      value = aws_ecr_repository.anycompany_ecr_repository.name
    }

    environment_variable {
      name  = "IMAGE_TAG"
      value = "latest"
    }

    environment_variable {
      name  = "API_ENDPOINT"
      value = "https://${aws_api_gateway_rest_api.anycompany_rest_api.id}.execute-api.${var.aws_region}.amazonaws.com/prod"
    }

    environment_variable {
      name  = "COGNITO_REGION"
      value = var.aws_region
    }

    environment_variable {
      name  = "COGNITO_USER_POOL_ID"
      value = aws_cognito_user_pool.anycompany_cognito_user_pool.id
    }

    environment_variable {
      name  = "COGNITO_CLIENT_ID"
      value = aws_cognito_user_pool_client.anycompany_cognito_user_pool_client.id
    }
  }

  source {
    type     = "S3"
    location = "${aws_s3_bucket.anycompany_source_bucket.id}/source/anycompany-ui-source.zip"

    buildspec = "buildspec.yml"
  }

  depends_on = [
    aws_cognito_user_pool.anycompany_cognito_user_pool,
    aws_cognito_user_pool_client.anycompany_cognito_user_pool_client
  ]
}