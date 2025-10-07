# Step Functions for Batch Processing
# Production-ready batch processing for 10K daily calls with 100 parallel execution

# IAM Role for Step Functions
resource "aws_iam_role" "step_functions_role" {
  name = "anycompany-stepfunctions-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "states.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Environment = var.environment
    Project     = "anycompany-compliance"
  }
}

# IAM Policy for Step Functions to invoke Lambda
resource "aws_iam_role_policy" "step_functions_lambda_policy" {
  name = "stepfunctions-lambda-policy"
  role = aws_iam_role.step_functions_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = [
          aws_lambda_function.batch_prep.arn,
          aws_lambda_function.batch_trigger.arn
        ]
      }
    ]
  })
}

# Batch Preparation Lambda Function
resource "aws_lambda_function" "batch_prep" {
  filename         = "batch_prep.zip"
  function_name    = "anycompany-batch-prep-${var.environment}"
  role            = aws_iam_role.anycompany_lambda_role.arn
  handler         = "index.lambda_handler"
  runtime         = "python3.9"
  timeout         = 900
  memory_size     = 512

  environment {
    variables = {
      ENVIRONMENT = var.environment
    }
  }

  tags = {
    Environment = var.environment
    Project     = "anycompany-compliance"
  }
}

# Batch Trigger Lambda Function
resource "aws_lambda_function" "batch_trigger" {
  filename         = "batch_trigger.zip"
  function_name    = "anycompany-batch-trigger-${var.environment}"
  role            = aws_iam_role.anycompany_lambda_role.arn
  handler         = "index.lambda_handler"
  runtime         = "python3.9"
  timeout         = 300
  memory_size     = 256

  environment {
    variables = {
      CALLS_TABLE = aws_dynamodb_table.calls.name
      ENVIRONMENT = var.environment
    }
  }

  tags = {
    Environment = var.environment
    Project     = "anycompany-compliance"
  }
}

# Step Functions State Machine for Production Batch Processing
resource "aws_sfn_state_machine" "batch_processor" {
  name     = "anycompany-batch-processor-${var.environment}"
  role_arn = aws_iam_role.step_functions_role.arn

  definition = jsonencode({
    Comment = "Production Batch Compliance Processing - 10K Files, 100 Parallel"
    StartAt = "PrepareBatch"
    States = {
      PrepareBatch = {
        Type     = "Task"
        Resource = aws_lambda_function.batch_prep.arn
        ResultPath = "$.batch_result"
        Retry = [
          {
            ErrorEquals     = ["States.TaskFailed"]
            IntervalSeconds = 30
            MaxAttempts     = 3
            BackoffRate     = 2.0
          }
        ]
        Next = "CheckBatchSize"
      }
      CheckBatchSize = {
        Type = "Choice"
        Choices = [
          {
            Variable      = "$.batch_result.batch_info.total_files_found"
            NumericEquals = 0
            Next          = "NoBatchFiles"
          },
          {
            Variable           = "$.batch_result.batch_info.total_files_found"
            NumericGreaterThan = 15000
            Next               = "BatchTooLarge"
          }
        ]
        Default = "ProcessBatch"
      }
      NoBatchFiles = {
        Type = "Pass"
        Result = {
          status                   = "completed"
          message                  = "No files found in batch folder"
          files_processed          = 0
          processing_time_seconds  = 0
        }
        End = true
      }
      BatchTooLarge = {
        Type = "Pass"
        Result = {
          status      = "error"
          message     = "Batch size exceeds 15,000 files limit"
          max_allowed = 15000
        }
        End = true
      }
      ProcessBatch = {
        Type                        = "Map"
        ItemsPath                   = "$.batch_result.calls"
        MaxConcurrency              = 100
        ToleratedFailurePercentage  = 5
        Iterator = {
          StartAt = "TriggerProcessing"
          States = {
            TriggerProcessing = {
              Type     = "Task"
              Resource = aws_lambda_function.batch_trigger.arn
              Retry = [
                {
                  ErrorEquals     = ["States.TaskFailed"]
                  IntervalSeconds = 30
                  MaxAttempts     = 3
                  BackoffRate     = 2.0
                }
              ]
              Catch = [
                {
                  ErrorEquals = ["States.ALL"]
                  Next        = "HandleProcessingError"
                  ResultPath  = "$.error"
                }
              ]
              End = true
            }
            HandleProcessingError = {
              Type = "Pass"
              Parameters = {
                status     = "failed"
                "filename.$" = "$.filename"
                "genesys_id.$" = "$.genesys_id"
                "error.$"    = "$.error.Cause"
              }
              End = true
            }
          }
        }
        ResultPath = "$.processing_results"
        Next       = "GenerateSummary"
      }
      GenerateSummary = {
        Type = "Pass"
        Parameters = {
          batch_summary = {
            status                         = "completed"
            "total_files.$"                = "$.batch_result.batch_info.total_files_found"
            "files_triggered.$"            = "States.ArrayLength($.processing_results)"
            "batch_folder.$"               = "$.batch_result.batch_info.batch_folder"
            "processing_timestamp.$"       = "$.batch_result.batch_info.processing_timestamp"
            max_concurrency                = 100
            tolerated_failure_percentage   = 5
            note                          = "Production batch processing completed - check DynamoDB for individual call status"
          }
        }
        OutputPath = "$.batch_summary"
        End        = true
      }
    }
  })

  tags = {
    Environment = var.environment
    Project     = "anycompany-compliance"
  }
}

# EventBridge Rule for Daily Batch Processing
resource "aws_cloudwatch_event_rule" "daily_batch" {
  name                = "anycompany-daily-batch-${var.environment}"
  description         = "Daily compliance batch processing at 2 AM UTC"
  schedule_expression = "cron(0 2 * * ? *)"

  tags = {
    Environment = var.environment
    Project     = "anycompany-compliance"
  }
}

# IAM Role for EventBridge to invoke Step Functions
resource "aws_iam_role" "eventbridge_stepfunctions_role" {
  name = "anycompany-eventbridge-stepfunctions-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Environment = var.environment
    Project     = "anycompany-compliance"
  }
}

# IAM Policy for EventBridge to start Step Functions execution
resource "aws_iam_role_policy" "eventbridge_stepfunctions_policy" {
  name = "eventbridge-stepfunctions-policy"
  role = aws_iam_role.eventbridge_stepfunctions_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "states:StartExecution"
        ]
        Resource = aws_sfn_state_machine.batch_processor.arn
      }
    ]
  })
}

# EventBridge Target to trigger Step Functions
resource "aws_cloudwatch_event_target" "step_functions_target" {
  rule      = aws_cloudwatch_event_rule.daily_batch.name
  target_id = "StepFunctionsTarget"
  arn       = aws_sfn_state_machine.batch_processor.arn
  role_arn  = aws_iam_role.eventbridge_stepfunctions_role.arn

  input = jsonencode({
    batch_folder = "s3://${aws_s3_bucket.input.bucket}/daily-batch/"
    max_files    = 10000
  })
}