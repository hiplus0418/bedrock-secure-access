terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.69"
    }
  }
}

# Workload account: where Bedrock is used (guardrail, logging, budget).
provider "aws" {
  region  = var.region
  profile = var.workload_profile

  default_tags {
    tags = var.tags
  }
}

# Management (or IAM Identity Center delegated admin) account:
# permission set, account assignment and the optional SCP.
provider "aws" {
  alias   = "management"
  region  = var.identity_center_region
  profile = var.management_profile

  default_tags {
    tags = var.tags
  }
}
