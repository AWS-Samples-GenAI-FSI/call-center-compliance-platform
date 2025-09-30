# AWS Transcribe and Comprehend don't require resource definitions
# They are managed services accessed via API calls from Lambda functions
# The IAM permissions are already included in lambda.tf

# Optional: Transcribe Custom Vocabulary (if needed)
# resource "aws_transcribe_vocabulary" "compliance_vocabulary" {
#   vocabulary_name   = "anycompany-compliance-vocabulary"
#   language_code     = "en-US"
#   phrases           = ["AnyCompany", "compliance", "FDCPA", "TCPA"]
# }

# Optional: Comprehend Custom Entity Recognizer (if needed for compliance terms)
# resource "aws_comprehend_entity_recognizer" "compliance_entities" {
#   name = "anycompany-compliance-entities"
#   
#   data_access_role_arn = aws_iam_role.comprehend_role.arn
#   language_code        = "en"
#   
#   input_data_config {
#     entity_types {
#       type = "COMPLIANCE_TERM"
#     }
#     documents {
#       s3_uri = "s3://${aws_s3_bucket.anycompany_input_bucket.id}/training/documents/"
#     }
#     annotations {
#       s3_uri = "s3://${aws_s3_bucket.anycompany_input_bucket.id}/training/annotations/"
#     }
#   }
# }

# Service-linked roles are automatically created by AWS when needed
# No explicit resource creation required for Transcribe/Comprehend