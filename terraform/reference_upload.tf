# Upload reference file to S3 input bucket
resource "aws_s3_object" "reference_file" {
  bucket = aws_s3_bucket.input.bucket
  key    = "reference/master_reference.json"
  content = jsonencode({
    "calls" = {
      "GEN-2024-001001" = {
        "expected_violations" = ["LO1001.04"]
        "expected_entities" = {
          "agent_names" = ["John"]
          "company_identification" = ["AnyCompany"]
        }
        "description" = "Agent identification violation"
      }
      "GEN-2024-002001" = {
        "expected_violations" = ["LO1007.05"]
        "expected_entities" = {
          "threatening_language" = ["arrest", "jail", "prison"]
        }
        "description" = "Threatening language violation"
      }
    }
  })
  content_type = "application/json"
}