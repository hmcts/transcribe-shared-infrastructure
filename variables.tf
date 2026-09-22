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

variable "product_group_object_id" {
  description = "AAD group granted access to the vault. Supplied by PlatOps for the product."
  type        = string
}

variable "speech_account_sku" {
  description = "SKU for the Speech cognitive account."
  type        = string
  default     = "S0"
}

variable "speech_public_network_access" {
  description = <<-EOT
    Whether the Speech account is reachable from the public internet.

    True is not the end state. The target is a private endpoint, as
    cnp-plum-shared-infrastructure does, but a private endpoint alone is not
    sufficient here: real-time dictation has the BROWSER talk to Speech over a
    websocket, so locking the account to the VNet also requires routing that
    traffic through the frontend (the Caddyfile already proxies
    /cognitiveservices/* for exactly this, selected by DIRECT_SDK_ACCESS).
    Until that path is proven end to end, closing this would break dictation
    rather than secure it.

    API keys are disabled regardless, so a reachable endpoint still only
    accepts Entra tokens.
  EOT
  type        = bool
  default     = true
}
