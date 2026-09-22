provider "azurerm" {
  features {}
}

data "azurerm_user_assigned_identity" "jenkins" {
  name                = "jenkins-${var.env == "sandbox" ? "sbox" : var.env}-mi"
  resource_group_name = "managed-identities-${var.env}-rg"
}

locals {
  # Must match the `keyVaults:` key in each component's Helm values, which the
  # base chart expands to "<key>-<environment>". charts/transcribe-api and
  # charts/transcribe-web both use "transcribe", so the vault is
  # "transcribe-<env>".
  vault_name = "${var.product}-${var.env}"

  tags = merge(
    var.common_tags,
    tomap({ "Team Contact" = var.team_contact })
  )
}

resource "azurerm_resource_group" "shared_resource_group" {
  name     = "${var.product}-shared-infrastructure-${var.env}"
  location = var.location

  tags = local.tags
}
