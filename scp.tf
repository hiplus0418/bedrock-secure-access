# Optional. Requires the management account (enable_scp = true).
# An SCP applies to every principal in the account, so it also covers
# IAM roles and users that never go through Identity Center.

locals {
  scp_regions = distinct(concat([var.region], var.inference_destination_regions))
}

data "aws_iam_policy_document" "bedrock_scp" {
  # Cross-region inference executes in the destination regions,
  # so they must be allowed here or calls will fail.
  statement {
    sid       = "DenyBedrockOutsideApprovedRegions"
    effect    = "Deny"
    actions   = ["bedrock:*"]
    resources = ["*"]

    condition {
      test     = "StringNotEquals"
      variable = "aws:RequestedRegion"
      values   = local.scp_regions
    }
  }

  statement {
    sid    = "ProtectBedrockControls"
    effect = "Deny"
    actions = [
      "bedrock:PutModelInvocationLoggingConfiguration",
      "bedrock:DeleteModelInvocationLoggingConfiguration",
      "bedrock:UpdateGuardrail",
      "bedrock:DeleteGuardrail",
    ]
    resources = ["*"]

    dynamic "condition" {
      for_each = length(var.scp_admin_role_arn_patterns) > 0 ? [1] : []
      content {
        test     = "ArnNotLike"
        variable = "aws:PrincipalArn"
        values   = var.scp_admin_role_arn_patterns
      }
    }
  }
}

resource "aws_organizations_policy" "bedrock" {
  count    = var.enable_scp ? 1 : 0
  provider = aws.management

  name        = "${var.name_prefix}-bedrock-guardrails"
  description = "Region restriction and tamper protection for Bedrock controls."
  type        = "SERVICE_CONTROL_POLICY"
  content     = data.aws_iam_policy_document.bedrock_scp.json
}

resource "aws_organizations_policy_attachment" "bedrock" {
  count    = var.enable_scp ? 1 : 0
  provider = aws.management

  policy_id = aws_organizations_policy.bedrock[0].id
  target_id = local.account_id
}
