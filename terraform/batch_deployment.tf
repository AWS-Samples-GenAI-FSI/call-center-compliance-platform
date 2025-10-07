# Batch Processing Lambda Deployment
# Creates ZIP files and deploys batch processing Lambda functions

# Create ZIP file for batch prep Lambda
data "archive_file" "batch_prep_zip" {
  type        = "zip"
  output_path = "${path.module}/batch_prep.zip"
  
  source {
    content = templatefile("${path.module}/batch_lambda_code.py", {
      handler_function = "batch_prep_handler"
    })
    filename = "index.py"
  }
}

# Create ZIP file for batch trigger Lambda  
data "archive_file" "batch_trigger_zip" {
  type        = "zip"
  output_path = "${path.module}/batch_trigger.zip"
  
  source {
    content = templatefile("${path.module}/batch_lambda_code.py", {
      handler_function = "batch_trigger_handler"
    })
    filename = "index.py"
  }
}

# Update Lambda function dependencies
resource "null_resource" "update_batch_prep_lambda" {
  depends_on = [aws_lambda_function.batch_prep]
  
  triggers = {
    code_hash = data.archive_file.batch_prep_zip.output_base64sha256
  }

  provisioner "local-exec" {
    command = "aws lambda update-function-code --function-name ${aws_lambda_function.batch_prep.function_name} --zip-file fileb://${data.archive_file.batch_prep_zip.output_path}"
  }
}

resource "null_resource" "update_batch_trigger_lambda" {
  depends_on = [aws_lambda_function.batch_trigger]
  
  triggers = {
    code_hash = data.archive_file.batch_trigger_zip.output_base64sha256
  }

  provisioner "local-exec" {
    command = "aws lambda update-function-code --function-name ${aws_lambda_function.batch_trigger.function_name} --zip-file fileb://${data.archive_file.batch_trigger_zip.output_path}"
  }
}