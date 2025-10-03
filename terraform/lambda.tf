# IAM Role for Lambda Functions
resource "aws_iam_role" "anycompany_lambda_role" {
  name = "anycompany-lambda-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.anycompany_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_vpc_access" {
  role       = aws_iam_role.anycompany_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "anycompany_compliance_policy" {
  name = "AnyCompanyCompliancePolicy"
  role = aws_iam_role.anycompany_lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          "${aws_s3_bucket.anycompany_input_bucket.arn}/*",
          aws_s3_bucket.anycompany_input_bucket.arn,
          "${aws_s3_bucket.anycompany_transcribe_output_bucket.arn}/*",
          aws_s3_bucket.anycompany_transcribe_output_bucket.arn,
          "${aws_s3_bucket.anycompany_comprehend_output_bucket.arn}/*",
          aws_s3_bucket.anycompany_comprehend_output_bucket.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:Scan",
          "dynamodb:Query",
          "dynamodb:UpdateItem"
        ]
        Resource = [
          aws_dynamodb_table.anycompany_calls_table.arn,
          aws_dynamodb_table.anycompany_rules_table.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "transcribe:StartTranscriptionJob",
          "transcribe:GetTranscriptionJob",
          "transcribe:ListTranscriptionJobs",
          "transcribe:DeleteTranscriptionJob"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "comprehend:DetectPiiEntities",
          "comprehend:DetectSentiment",
          "comprehend:DetectEntities",
          "comprehend:DetectKeyPhrases"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetBucketNotification",
          "s3:PutBucketNotification"
        ]
        Resource = [
          aws_s3_bucket.anycompany_input_bucket.arn,
          aws_s3_bucket.anycompany_transcribe_output_bucket.arn,
          aws_s3_bucket.anycompany_comprehend_output_bucket.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:SendMessage"
        ]
        Resource = [
          aws_sqs_queue.anycompany_processing_queue.arn,
          aws_sqs_queue.anycompany_processing_dlq.arn
        ]
      }
    ]
  })
}

# API Lambda Function
resource "aws_lambda_function" "anycompany_api_function" {
  filename         = "api_function.zip"
  function_name    = "anycompany-api-${var.environment}"
  role            = aws_iam_role.anycompany_lambda_role.arn
  handler         = "index.lambda_handler"
  runtime         = "python3.9"
  timeout         = 30

  environment {
    variables = {
      CALLS_TABLE_NAME = aws_dynamodb_table.anycompany_calls_table.name
      INPUT_BUCKET_NAME = aws_s3_bucket.anycompany_input_bucket.id
      RULES_TABLE_NAME = aws_dynamodb_table.anycompany_rules_table.name
    }
  }

  depends_on = [data.archive_file.api_function_zip]
}

# Processor Lambda Function
resource "aws_lambda_function" "anycompany_processor_function" {
  filename                       = "processor_function.zip"
  function_name                  = "anycompany-processor-${var.environment}"
  role                          = aws_iam_role.anycompany_lambda_role.arn
  handler                       = "index.lambda_handler"
  runtime                       = "python3.9"
  timeout                       = 900
  reserved_concurrent_executions = 10

  environment {
    variables = {
      CALLS_TABLE = aws_dynamodb_table.anycompany_calls_table.name
      RULES_TABLE = aws_dynamodb_table.anycompany_rules_table.name
      INPUT_BUCKET_NAME = aws_s3_bucket.anycompany_input_bucket.id
      TRANSCRIBE_OUTPUT_BUCKET = aws_s3_bucket.anycompany_transcribe_output_bucket.id
      COMPREHEND_OUTPUT_BUCKET = aws_s3_bucket.anycompany_comprehend_output_bucket.id
    }
  }

  depends_on = [data.archive_file.processor_function_zip]
}

# Transcription Complete Lambda Function
resource "aws_lambda_function" "anycompany_transcription_complete_function" {
  filename      = "transcription_complete_function.zip"
  function_name = "anycompany-transcription-complete-${var.environment}"
  role         = aws_iam_role.anycompany_lambda_role.arn
  handler      = "index.lambda_handler"
  runtime      = "python3.9"
  timeout      = 300

  environment {
    variables = {
      CALLS_TABLE = aws_dynamodb_table.anycompany_calls_table.name
      RULES_TABLE = aws_dynamodb_table.anycompany_rules_table.name
      INPUT_BUCKET_NAME = aws_s3_bucket.anycompany_input_bucket.id
      TRANSCRIBE_OUTPUT_BUCKET = aws_s3_bucket.anycompany_transcribe_output_bucket.id
      COMPREHEND_OUTPUT_BUCKET = aws_s3_bucket.anycompany_comprehend_output_bucket.id
    }
  }

  depends_on = [data.archive_file.transcription_complete_function_zip]
}

# SQS Event Source Mapping
resource "aws_lambda_event_source_mapping" "anycompany_processor_event_source_mapping" {
  event_source_arn                   = aws_sqs_queue.anycompany_processing_queue.arn
  function_name                      = aws_lambda_function.anycompany_processor_function.arn
  batch_size                         = 50
  maximum_batching_window_in_seconds = 10
}

# Lambda Permissions
resource "aws_lambda_permission" "api_gateway_invoke" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.anycompany_api_function.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.anycompany_rest_api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "s3_invoke_transcription_complete" {
  statement_id  = "AllowExecutionFromS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.anycompany_transcription_complete_function.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.anycompany_transcribe_output_bucket.arn
}

# Archive files for Lambda functions
data "archive_file" "api_function_zip" {
  type        = "zip"
  output_path = "api_function.zip"
  source {
    content  = file("${path.module}/api_function_code.py")
    filename = "index.py"
  }
}

data "archive_file" "processor_function_zip" {
  type        = "zip"
  output_path = "processor_function.zip"
  source {
    content  = file("${path.module}/processor_function_code.py")
    filename = "index.py"
  }
}

data "archive_file" "transcription_complete_function_zip" {
  type        = "zip"
  output_path = "transcription_complete_function.zip"
  source {
    content  = file("${path.module}/transcription_complete_function_code.py")
    filename = "index.py"
  }
}