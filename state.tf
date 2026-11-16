terraform {
  # Backend configuration is supplied by the CNP pipeline.
  backend "azurerm" {}

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.81.0"
    }
    random = {
      source = "hashicorp/random"
    }
  }
}
