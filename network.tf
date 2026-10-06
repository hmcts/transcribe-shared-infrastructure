# Subnets allowed through the storage account firewall.
#
# Copied from tax-tribunals-shared-infrastructure, the working CFT reference.
# cnp-module-storage-account defaults its network rules to default_action =
# "Deny" with no allowed subnets, so without this list the Jenkins agents cannot
# reach the blob data plane to create the containers (build #6 failed with
# "AuthorizationFailure: This request is not authorized to perform this
# operation" on both containers) — and the AKS pods could not read or write
# audio either. The list covers the Jenkins agents (cft-ptl), the CFT AKS
# cluster for this environment, and, in aat only, the preview cluster.
#
# mgmt_subscription_id and aks_subscription_id are injected by the pipeline
# (TF_VAR_*), so they are declared without defaults.

locals {
  mgmt_network_name    = "cft-ptl-vnet"
  mgmt_network_rg_name = "cft-ptl-network-rg"

  aks_env = var.env == "sandbox" ? "sbox" : var.env

  aat_cft_vnet_name           = "cft-aat-vnet"
  aat_cft_vnet_resource_group = "cft-aat-network-rg"

  cft_aks_network_name    = "cft-${local.aks_env}-vnet"
  cft_aks_network_rg_name = "cft-${local.aks_env}-network-rg"


  preview_vnet_name            = "cft-preview-vnet"
  preview_vnet_resource_group  = "cft-preview-network-rg"
  perftest_vnet_name           = "core-infra-vnet-perftest"
  perftest_subnet_name         = "core-infra-subnet-mgmtperftest"
  perftest_vnet_resource_group = "core-infra-perftest"
}

provider "azurerm" {
  alias           = "mgmt"
  subscription_id = var.mgmt_subscription_id
  features {}
}

provider "azurerm" {
  features {}
  skip_provider_registration = true
  alias                      = "aks"
  subscription_id            = var.aks_subscription_id
}

provider "azurerm" {
  features {}
  alias                           = "aks_preview"
  subscription_id                 = var.env == "aat" ? "8b6ea922-0862-443e-af15-6056e1c9b9a4" : var.aks_subscription_id
  resource_provider_registrations = "none"
}

provider "azurerm" {
  features {}
  alias                           = "aks_perftest_mgmt"
  subscription_id                 = var.env == "perftest" ? "7a4e3bd5-ae3a-4d0c-b441-2188fee3ff1c" : var.aks_subscription_id
  resource_provider_registrations = "none"
}

data "azurerm_subnet" "perftest_mgmt_subnet" {
  count                = var.env == "perftest" ? 1 : 0
  provider             = azurerm.aks_perftest_mgmt
  name                 = local.perftest_subnet_name
  virtual_network_name = local.perftest_vnet_name
  resource_group_name  = local.perftest_vnet_resource_group
}

data "azurerm_subnet" "preview_aks_00_subnet" {
  count                = var.env == "aat" ? 1 : 0
  provider             = azurerm.aks_preview
  name                 = "aks-00"
  virtual_network_name = local.preview_vnet_name
  resource_group_name  = local.preview_vnet_resource_group
}

data "azurerm_subnet" "preview_aks_01_subnet" {
  count                = var.env == "aat" ? 1 : 0
  provider             = azurerm.aks_preview
  name                 = "aks-01"
  virtual_network_name = local.preview_vnet_name
  resource_group_name  = local.preview_vnet_resource_group
}

data "azurerm_subnet" "jenkins_subnet" {
  provider             = azurerm.mgmt
  name                 = "iaas"
  virtual_network_name = local.mgmt_network_name
  resource_group_name  = local.mgmt_network_rg_name
}

data "azurerm_subnet" "jenkins_aks_00" {
  provider             = azurerm.mgmt
  name                 = "aks-00"
  virtual_network_name = local.mgmt_network_name
  resource_group_name  = local.mgmt_network_rg_name
}

data "azurerm_subnet" "jenkins_aks_01" {
  provider             = azurerm.mgmt
  name                 = "aks-01"
  virtual_network_name = local.mgmt_network_name
  resource_group_name  = local.mgmt_network_rg_name
}

data "azurerm_subnet" "cft_aks_00_subnet" {
  provider             = azurerm.aks
  name                 = "aks-00"
  virtual_network_name = local.cft_aks_network_name
  resource_group_name  = local.cft_aks_network_rg_name
}

data "azurerm_subnet" "cft_aks_01_subnet" {
  provider             = azurerm.aks
  name                 = "aks-01"
  virtual_network_name = local.cft_aks_network_name
  resource_group_name  = local.cft_aks_network_rg_name
}

locals {
  standard_subnets = [
    data.azurerm_subnet.jenkins_subnet.id,
    data.azurerm_subnet.jenkins_aks_00.id,
    data.azurerm_subnet.jenkins_aks_01.id,
    data.azurerm_subnet.cft_aks_00_subnet.id,
    data.azurerm_subnet.cft_aks_01_subnet.id,
  ]

  preview_subnets   = var.env == "aat" ? [data.azurerm_subnet.preview_aks_00_subnet[0].id, data.azurerm_subnet.preview_aks_01_subnet[0].id] : []
  perftest_subnets  = var.env == "perftest" ? [data.azurerm_subnet.perftest_mgmt_subnet[0].id] : []
  all_valid_subnets = concat(local.standard_subnets, local.preview_subnets, local.perftest_subnets)
}

# Private endpoints for this product's PaaS resources go in the CFT cluster
# network's dedicated `private-endpoints` subnet, as em-icp-api does. The
# subnet (and so the endpoint) is in the AKS subscription, not the CNP infra
# subscription that holds the rest of this repo's resources.
data "azurerm_subnet" "cft_private_endpoints" {
  provider             = azurerm.aks
  name                 = "private-endpoints"
  virtual_network_name = local.cft_aks_network_name
  resource_group_name  = local.cft_aks_network_rg_name
}
