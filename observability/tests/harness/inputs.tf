# Test harness for the root's observability-*.tf (DIAAT-205): stands in for
# observability.tf, the only file linking them to the rest of the root, so they can be
# planned against a mock provider without the root's git modules. Assembled and run by
# observability/tests/run-terraform-tests.sh.

terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

variable "product" {
  type = string
}

variable "env" {
  type = string
}

variable "application_insights_id" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "billing_resource_ids" {
  type    = list(string)
  default = []
}

variable "speech_resource_id" {
  type    = string
  default = ""
}

locals {
  tags                        = var.tags
  obs_application_insights_id = var.application_insights_id
  obs_resource_group_name     = var.resource_group_name
  obs_location                = var.location
  obs_billing_resource_ids    = var.billing_resource_ids
  obs_speech_resource_id      = var.speech_resource_id
}
