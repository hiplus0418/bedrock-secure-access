data "aws_ssoadmin_instances" "this" {
  provider = aws.management
}

locals {
  sso_instance_arn  = tolist(data.aws_ssoadmin_instances.this.arns)[0]
  identity_store_id = tolist(data.aws_ssoadmin_instances.this.identity_store_ids)[0]

  # Pinned guardrail version, e.g. arn:aws:bedrock:<region>:<acct>:guardrail/<id>:1
  guardrail_version_arn = "${aws_bedrock_guardrail.this.guardrail_arn}:${aws_bedrock_guardrail_version.this.version}"

  model_regions = distinct(concat([var.region], var.inference_destination_regions))

  # A cross-region inference profile needs permission on the profile AND on the
  # foundation model in every region it can route to.
  allowed_model_arns = flatten([
    for r in local.model_regions : [
      for m in var.allowed_model_ids : "arn:aws:bedrock:${r}::foundation-model/${m}"
    ]
  ])
  allowed_profile_arns = [
    for p in var.allowed_inference_profile_ids :
    "arn:aws:bedrock:${var.region}:${local.account_id}:inference-profile/${p}"
  ]
  allowed_invoke_arns = concat(local.allowed_model_arns, local.allowed_profile_arns)

  invoke_actions = [
    "bedrock:InvokeModel",                   # also covers Converse
    "bedrock:InvokeModelWithResponseStream", # also covers ConverseStream
  ]
  all_invoke_targets = [
    "arn:aws:bedrock:*::foundation-model/*",
    "arn:aws:bedrock:*:${local.account_id}:inference-profile/*",
  ]
}

data "aws_iam_policy_document" "bedrock_user" {
  statement {
    sid = "DiscoverModels"
    actions = [
      "bedrock:ListFoundationModels",
      "bedrock:GetFoundationModel",
      "bedrock:ListInferenceProfiles",
      "bedrock:GetInferenceProfile",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "InvokeAllowedModelsWithGuardrail"
    actions   = local.invoke_actions
    resources = local.allowed_invoke_arns

    condition {
      test     = "StringEquals"
      variable = "bedrock:GuardrailIdentifier"
      values   = [local.guardrail_version_arn]
    }
  }

  statement {
    sid       = "ApplyGuardrail"
    actions   = ["bedrock:ApplyGuardrail"]
    resources = [aws_bedrock_guardrail.this.guardrail_arn]
  }

  # Explicit denies hold even if someone attaches a broader managed policy
  # (e.g. AmazonBedrockFullAccess) to this permission set later.
  statement {
    sid       = "DenyInvokeWithoutPinnedGuardrail"
    effect    = "Deny"
    actions   = local.invoke_actions
    resources = local.all_invoke_targets

    condition {
      test     = "StringNotEquals"
      variable = "bedrock:GuardrailIdentifier"
      values   = [local.guardrail_version_arn]
    }
  }

  statement {
    sid           = "DenyModelsNotOnAllowList"
    effect        = "Deny"
    actions       = local.invoke_actions
    not_resources = local.allowed_invoke_arns
  }

  statement {
    sid    = "DenyWeakeningControls"
    effect = "Deny"
    actions = [
      "bedrock:PutModelInvocationLoggingConfiguration",
      "bedrock:DeleteModelInvocationLoggingConfiguration",
      "bedrock:UpdateGuardrail",
      "bedrock:DeleteGuardrail",
      "bedrock:CreateGuardrailVersion",
    ]
    resources = ["*"]
  }
}

resource "aws_ssoadmin_permission_set" "bedrock_user" {
  provider = aws.management

  name             = "BedrockUser"
  description      = "Invoke approved Bedrock models with the mandatory guardrail."
  instance_arn     = local.sso_instance_arn
  session_duration = var.session_duration

  lifecycle {
    precondition {
      condition     = length(var.allowed_inference_profile_ids) == 0 || length(var.inference_destination_regions) > 0
      error_message = "Set inference_destination_regions when using inference profiles; otherwise calls are denied in the destination regions."
    }
  }
}

resource "aws_ssoadmin_permission_set_inline_policy" "bedrock_user" {
  provider = aws.management

  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.bedrock_user.arn
  inline_policy      = data.aws_iam_policy_document.bedrock_user.json
}

data "aws_identitystore_group" "bedrock_users" {
  provider = aws.management

  identity_store_id = local.identity_store_id

  alternate_identifier {
    unique_attribute {
      attribute_path  = "DisplayName"
      attribute_value = var.identity_center_group_name
    }
  }
}

resource "aws_ssoadmin_account_assignment" "bedrock_users" {
  provider = aws.management

  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.bedrock_user.arn

  principal_type = "GROUP"
  principal_id   = data.aws_identitystore_group.bedrock_users.group_id

  target_type = "AWS_ACCOUNT"
  target_id   = local.account_id

  depends_on = [aws_ssoadmin_permission_set_inline_policy.bedrock_user]
}
