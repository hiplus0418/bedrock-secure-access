variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
  default     = "bedrock-secure"
}

variable "region" {
  description = "Region where Bedrock is used. Invocation logging and the guardrail are regional."
  type        = string
}

variable "workload_profile" {
  description = "AWS CLI profile for the workload account. null = default credential chain."
  type        = string
  default     = null
}

variable "identity_center_region" {
  description = "Region of the IAM Identity Center instance."
  type        = string
}

variable "management_profile" {
  description = "AWS CLI profile for the management / Identity Center delegated admin account."
  type        = string
  default     = null
}

variable "identity_center_group_name" {
  description = "Display name of the existing Identity Center group that receives Bedrock access."
  type        = string
}

variable "allowed_model_ids" {
  description = "Foundation model IDs users may invoke, e.g. from `aws bedrock list-foundation-models`."
  type        = list(string)

  validation {
    condition     = length(var.allowed_model_ids) > 0
    error_message = "Allow at least one model."
  }
}

variable "allowed_inference_profile_ids" {
  description = "Cross-region inference profile IDs users may invoke, e.g. from `aws bedrock list-inference-profiles`. Leave empty if you only use in-region models."
  type        = list(string)
  default     = []
}

variable "inference_destination_regions" {
  description = "Regions the inference profiles may route to. Needed for the foundation-model ARNs and for the optional SCP."
  type        = list(string)
  default     = []
}

variable "guardrail_profile_arn" {
  description = "Guardrail profile ARN that enables cross-Region inference on the guardrail. Set it when callers use cross-region inference profiles. null = disabled."
  type        = string
  default     = null
}

variable "log_retention_days" {
  description = "Days to keep invocation logs (S3 and CloudWatch). Logs contain prompts and responses."
  type        = number
  default     = 90
}

variable "monthly_budget_usd" {
  description = "Monthly Bedrock budget in USD."
  type        = number
  default     = 100
}

variable "budget_service_names" {
  description = "Cost Explorer service names to include in the budget. Check Cost Explorer: some third-party model charges appear under their own service names."
  type        = list(string)
  default     = ["Amazon Bedrock"]
}

variable "budget_alert_emails" {
  description = "Email addresses for budget alerts."
  type        = list(string)
}

variable "session_duration" {
  description = "Session duration of the permission set (ISO 8601)."
  type        = string
  default     = "PT4H"
}

variable "enable_scp" {
  description = "Create and attach the optional SCP (requires the management account)."
  type        = bool
  default     = false
}

variable "scp_admin_role_arn_patterns" {
  description = "Principal ARN patterns exempt from the SCP's protection statements (e.g. your platform admin role)."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default = {
    Project   = "bedrock-secure-access"
    ManagedBy = "terraform"
  }
}
