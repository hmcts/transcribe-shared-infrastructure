# The benchnotes-prod app registration (hmcts/central-app-registration).
entra_client_secret_source = {
  subscription_id     = "6c4d2513-a873-41b4-afdd-b05a33206631"
  resource_group_name = "central-app-registration-rg"
  key_vault_name      = "central-app-reg-kv"
  secret_name         = "benchnotes-prod-secret"
}

# Zone-redundant: prod holds the only copy of judges' audio and transcripts.
# Set before the first prod apply: azurerm replaces the account to move
# between LRS and ZRS.
sa_account_replication_type = "ZRS"
