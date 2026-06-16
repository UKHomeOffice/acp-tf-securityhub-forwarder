terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 3.70"
    }
    # Used only for the region-assertion null_resource in main.tf, which emulates a
    # lifecycle precondition on Terraform < 1.2 (the version consumers like
    # acp-ops-resources actually run).
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0"
    }
  }
}
