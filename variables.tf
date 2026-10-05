# ---------------------------------------------------------------------------
# Injected by the CNP pipeline via -var. Do NOT set these in a .tfvars file.
# ---------------------------------------------------------------------------
variable "product" {}

variable "env" {}

variable "subscription" {}

variable "tenant_id" {}

variable "jenkins_AAD_objectId" {
  description = "Object ID of the Jenkins identity, granted access to the vault."
}

variable "common_tags" {
  type = map(string)
}

# ---------------------------------------------------------------------------
# Product configuration
# ---------------------------------------------------------------------------
variable "location" {
  default = "UK South"
}

variable "team_contact" {
  description = "Slack channel for the owning team."
  default     = "#justicetranscribe-ask"
}

variable "managed_identity_object_id" {
  default = ""
}

variable "additional_managed_identities_access" {
  type    = list(string)
  default = []
}

variable "daily_data_cap_in_gb" {
  description = "Cap on Application Insights ingestion, to bound cost."
  type        = number
  default     = 5
}

variable "product_group_name" {
  description = "Display name of the AAD security group granted administrative access to the vault."
  type        = string
  default     = ""

  # The vault uses access policies (see vault.tf), and cnp-module-key-vault
  # creates the product-team access policy unconditionally. With no group it
  # would be applied with an empty object_id and fail at apply time with an
  # opaque error, so fail at plan time with the actual reason instead.
  validation {
    condition     = length(var.product_group_name) > 0
    error_message = "product_group_name is empty. The transcribe product has no AAD security group yet: PlatOps must create one (it also belongs in team-config.yml as azure_ad_group). Set this variable to its display name. See README, 'Key Vault access'."
  }
}

variable "product_group_object_id" {
  description = "Deprecated object-ID form of product_group_name. Prefer the name."
  type        = string
  default     = ""
}

variable "speech_account_sku" {
  description = "SKU for the Speech cognitive account."
  type        = string
  default     = "S0"
}


# Injected by the pipeline (TF_VAR_mgmt_subscription_id / TF_VAR_aks_subscription_id).
variable "mgmt_subscription_id" {}

variable "aks_subscription_id" {}
