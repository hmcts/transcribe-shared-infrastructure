# The benchnotes-prod app registration (hmcts/central-app-registration).
entra_client_secret_source = {
  subscription_id     = "6c4d2513-a873-41b4-afdd-b05a33206631"
  resource_group_name = "central-app-registration-rg"
  key_vault_name      = "central-app-reg-kv"
  secret_name         = "benchnotes-prod-secret"
}

# Changing between LRS and ZRS later replaces the account and loses its data.
sa_account_replication_type = "ZRS"
