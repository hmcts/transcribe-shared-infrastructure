# The benchnotes-demo app registration (hmcts/central-app-registration).
entra_client_secret_source = {
  subscription_id     = "6c4d2513-a873-41b4-afdd-b05a33206631"
  resource_group_name = "central-app-registration-rg"
  key_vault_name      = "central-app-reg-kv"
  secret_name         = "benchnotes-demo-secret"
}

alert_limit_reached = true

# DIAAT-205: alert rules on in demo, as in AAT. Personal mailboxes for the trial
# only; swap for a team mailbox (or a Key Vault webhook) once PlatOps confirm the
# route.
observability_alerts_enabled = true
observability_service_alert_emails = [
  "saad.shaukat@hmcts.net",
  "Hamza.Ahmed@justice.gov.uk",
  "christopher.john@Justice.gov.uk",
]
observability_security_alert_emails = [
  "saad.shaukat@hmcts.net",
  "Hamza.Ahmed@justice.gov.uk",
  "christopher.john@Justice.gov.uk",
]
