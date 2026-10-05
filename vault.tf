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

  # Access policies, NOT Azure RBAC — do not switch this on.
  #
  # RBAC mode was tried and cannot work on CNP. It needs the module to grant
  # Jenkins "Key Vault Administrator", and the Jenkins identity's role-assignment
  # permission carries an ABAC condition that forbids granting that role:
  # "has an authorization with ABAC condition that is not fulfilled to perform
  # action 'Microsoft.Authorization/roleAssignments/write'" (build #6). Every
  # secret write then failed with "Assignment: (not found)" (builds #4-#6).
  # Access policies need no role assignments, which is why every CNP product
  # uses them.
  enable_rbac_authorization = false

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
