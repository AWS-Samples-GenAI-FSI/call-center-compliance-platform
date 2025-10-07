# Add working rules to DynamoDB
resource "aws_dynamodb_table_item" "threatening_language_rule" {
  table_name = aws_dynamodb_table.rules.name
  hash_key   = aws_dynamodb_table.rules.hash_key

  item = jsonencode({
    rule_id = {
      S = "LO1007.05"
    }
    description = {
      S = "Threatening language detected"
    }
    category = {
      S = "communication"
    }
    severity = {
      S = "critical"
    }
    active = {
      BOOL = true
    }
    logic = {
      M = {
        type = {
          S = "pattern_match"
        }
        patterns = {
          L = [
            { S = "seize" },
            { S = "garnish" },
            { S = "arrest" },
            { S = "jail" },
            { S = "prison" }
          ]
        }
        required = {
          BOOL = true
        }
        entity_types = {
          L = []
        }
      }
    }
  })
}

resource "aws_dynamodb_table_item" "agent_identification_rule" {
  table_name = aws_dynamodb_table.rules.name
  hash_key   = aws_dynamodb_table.rules.hash_key

  item = jsonencode({
    rule_id = {
      S = "LO1001.04"
    }
    description = {
      S = "Agent identification missing"
    }
    category = {
      S = "identification"
    }
    severity = {
      S = "major"
    }
    active = {
      BOOL = true
    }
    logic = {
      M = {
        type = {
          S = "pattern_match"
        }
        patterns = {
          L = [
            { S = "my name is" },
            { S = "this is" },
            { S = "speaking" }
          ]
        }
        required = {
          BOOL = false
        }
        timeFrame = {
          S = "first_60_seconds"
        }
        entity_types = {
          L = [
            { S = "persons" }
          ]
        }
      }
    }
  })
}