module "vault" {
  source                  = "git@github.com:hmcts/cnp-module-key-vault?ref=master"
  name                    = local.vault_name
  product                 = var.product
  env                     = var.env
  tenant_id               = var.tenant_id
  object_id               = var.jenkins_AAD_objectId
  resource_group_name     = azurerm_resource_group.shared_resource_group.name
  product_group_object_id = var.product_group_object_id
  product_group_name      = var.product_group_name
  common_tags             = local.tags

  # Azure RBAC rather than access policies.
  #
  # Not a stylistic choice: in access-policy mode the module unconditionally
  # creates product_team_access_policy, and with no product AAD group to point
  # it at, that resource is built with an empty object_id and apply fails. In
  # RBAC mode the equivalent role assignment is skipped when the group is
  # empty, while every identity that actually needs the vault still gets a
  # role — Jenkins and the deployment identity as Key Vault Administrator, and
  # the workload identity this module creates as Key Vault Secrets User, which
  # is what the CSI driver uses to mount secrets into the pods.
  enable_rbac_authorization = true

  managed_identity_object_id           = var.managed_identity_object_id
  create_managed_identity              = true
  additional_managed_identities_access = var.additional_managed_identities_access
  jenkins_object_id                    = data.azurerm_user_assigned_identity.jenkins.principal_id
}

output "vaultName" {
  value = module.vault.key_vault_name
}

output "vaultUri" {
  value = module.vault.key_vault_uri
}
