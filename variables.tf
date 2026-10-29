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

variable "sampling_percentage" {
  description = <<-EOT
    App Insights ingestion sampling. 100 everywhere (DIAAT-205): the module's
    default for non-prod environments is 1%, which keeps about one request,
    event or log in a hundred, so the observability workbooks, alerts and the
    DIAAT-287 telemetry validation would be meaningless in AAT and demo. Usage
    is low; the daily cap (daily_data_cap_in_gb) bounds the cost.
  EOT
  type        = number
  default     = 100
}

variable "alert_limit_reached" {
  description = "Use a scheduled query rule for the daily-cap alert instead of an activity log alert. Set where the subscription has hit its limit of 100 activity log alerts."
  type        = bool
  default     = false
}

variable "product_group_name" {
  description = <<-EOT
    Display name of the product's AAD security group, given administrative
    access to the vault. CNP convention: one group per product, defined as code
    in hmcts/azure-access (users/groups.yml) and also set as azure_ad_group in
    cnp-jenkins-config's team-config.yml and as TEAM_AAD_GROUP_ID in
    cnp-flux-config. Created by hmcts/azure-access#8294.
  EOT
  type        = string
  default     = "DTS Transcribe"

  # cnp-module-key-vault always creates the product-team access policy and
  # resolves this name with a data lookup, so an empty value can only fail —
  # fail at plan time with the reason rather than with an empty object_id.
  validation {
    condition     = length(var.product_group_name) > 0
    error_message = "product_group_name must name the product's AAD group (DTS Transcribe)."
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

variable "entra_client_secret_source" {
  description = "Where the BenchNotes app registration's client secret is kept (central-app-reg-kv, from hmcts/central-app-registration). null skips the copy (see entra.tf)."
  type = object({
    subscription_id     = string
    resource_group_name = string
    key_vault_name      = string
    secret_name         = string
  })
  default = null
}

variable "openai_gpt4o_capacity" {
  description = "gpt-4o deployment capacity, in thousands of tokens per minute."
  type        = number
  default     = 30
}

variable "sa_account_replication_type" {
  description = "Replication for the storage account in storage.tf."
  type        = string
  default     = "LRS"

  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "RAGRS", "GZRS", "RAGZRS"], var.sa_account_replication_type)
    error_message = "sa_account_replication_type must be one of LRS, ZRS, GRS, RAGRS, GZRS or RAGZRS."
  }
}
