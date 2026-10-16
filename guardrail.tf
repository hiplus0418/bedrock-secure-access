resource "aws_bedrock_guardrail" "this" {
  name                      = "${var.name_prefix}-default"
  description               = "Baseline guardrail required on every model call."
  blocked_input_messaging   = "This request was blocked by your organization's AI usage policy."
  blocked_outputs_messaging = "The response was blocked by your organization's AI usage policy."

  content_policy_config {
    dynamic "filters_config" {
      for_each = ["HATE", "INSULTS", "SEXUAL", "VIOLENCE", "MISCONDUCT"]
      content {
        type            = filters_config.value
        input_strength  = "HIGH"
        output_strength = "HIGH"
      }
    }

    # Prompt attacks are only evaluated on input.
    filters_config {
      type            = "PROMPT_ATTACK"
      input_strength  = "HIGH"
      output_strength = "NONE"
    }
  }

  sensitive_information_policy_config {
    # Credentials must never be sent to or returned by a model.
    dynamic "pii_entities_config" {
      for_each = ["AWS_ACCESS_KEY", "AWS_SECRET_KEY", "PASSWORD"]
      content {
        type   = pii_entities_config.value
        action = "BLOCK"
      }
    }

    # Personal data is masked in responses rather than blocked.
    dynamic "pii_entities_config" {
      for_each = ["EMAIL", "PHONE", "CREDIT_DEBIT_CARD_NUMBER"]
      content {
        type   = pii_entities_config.value
        action = "ANONYMIZE"
      }
    }
  }

  word_policy_config {
    managed_word_lists_config {
      type = "PROFANITY"
    }
  }
}

# A numbered, immutable version. IAM pins this version, so editing the
# DRAFT guardrail cannot silently weaken what users run against.
resource "aws_bedrock_guardrail_version" "this" {
  guardrail_arn = aws_bedrock_guardrail.this.guardrail_arn
  description   = "Managed by Terraform"
  skip_destroy  = true
}
