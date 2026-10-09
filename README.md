# transcribe-shared-infrastructure

Product-level Azure infrastructure for the **transcribe** product, deployed by
the HMCTS CNP common pipeline (`withInfraPipeline`). Terraform lives at the
repository root, and each long-lived environment has its own branch kept in
step with `master`.

This is the middle of the three CNP infrastructure tiers:

| Tier | Owner | Where |
|---|---|---|
| Platform | PlatOps (`cnp-core-infrastructure`) | Resource group, VNet, AKS. Service teams do not provision networking. |
| **Product** | **this repo** | **Key Vault, Application Insights, storage — anything shared by more than one component.** |
| Component | `transcribe-api/infrastructure` | Resources belonging to exactly one component, e.g. its Postgres server. |

## What this builds

- Resource group `transcribe-shared-infrastructure-<env>`
- Key Vault **`transcribe-<env>`** — the name is load-bearing, see below
- Application Insights, plus the `AppInsightsConnectionString` secret
- Storage account with `audio` and `transcriptions` containers, plus the
  `azure-storage-account-name` secret

## The Key Vault name is load-bearing

Both component charts declare `keyVaults: { transcribe: ... }`. The HMCTS base
chart expands that to `"<key>-<global.environment>"`, so the vault **must** be
named `transcribe-<env>`. Renaming it here silently breaks every component
deployment: the CSI driver cannot find the vault, the volume never mounts, and
pods stay unready with no obvious error in the application logs.

## Secrets that must be seeded by hand

The chart's `keyVaults` block names every secret it wants mounted. **If any one
of them is missing from the vault, the Secrets Store CSI driver fails the mount
and the pod never starts** — so seeding these is a hard precondition for the
first deploy, not a follow-up.

Terraform creates these:

| Secret | Created by |
|---|---|
| `AppInsightsConnectionString` | this repo |
| `azure-storage-account-name` | this repo |
| `database-connection-string` | `transcribe-api/infrastructure` |
| `azure-speech-endpoint` | this repo |
| `azure-speech-resource-id` | this repo |

These have to be seeded manually, because they are credentials for systems
outside this product's Terraform:

| Secret | Notes |
|---|---|
| `entra-client-id` | MoJ Entra (e-judiciary) app registration |
| `entra-tenant-id` | " |
| `entra-client-secret` | " |
| `azure-openai-api-key` | |
| `azure-openai-endpoint` | |
| `gov-notify-api-key` | GOV.UK Notify |
| `jwt-secret-key` | Any high-entropy string |
| `webhook-secret-encryption-key` | Must be a valid Fernet key: 32 random bytes, url-safe base64. Generate with `python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"`. A plain random string will fail at decrypt time, not at startup. |

Seed one with:

```bash
az keyvault secret set --vault-name transcribe-aat --name gov-notify-api-key --value '<value>'
```

## Azure Speech

Built here by `terraform-module-ai-services`, the platform's approved module for
cognitive accounts (globally whitelisted; the bare `azurerm_cognitive_account`
is not). The one approval this repo needs is for `azurerm_role_assignment`
(cnp-jenkins-config#1349), for the data-plane grant below.

**No API keys exist.** `cognitive_account_local_auth_enabled = false`, so Speech
issues no key at all. The API authenticates as the product managed identity and
mints an `aad#<resourceId>#<token>` for the Speech SDK, which is why the vault
holds `azure-speech-resource-id` and not `azure-speech-key`.

**The account is private, and that is mandated.** hmcts/azure-policy's
`allowed_ai_resources` policy requires public network access disabled, network
ACLs denying by default, outbound access restricted, local auth disabled and
UK South. Build #6 was refused with `RequestDisallowedByPolicy` while it was
public. (That policy's README says it is assigned in Audit mode; in this
subscription it denies.)

**Private endpoint.** `ai-services.tf` creates it in `cft-<env>-vnet`'s
`private-endpoints` subnet, in the AKS subscription (a private endpoint must
share its VNet's subscription), as em-icp-api does. DNS in the central
`privatelink.cognitiveservices.azure.com` zone is registered by the platform.
`azurerm_private_endpoint` is approved for this repo in cnp-jenkins-config#1367.

Because the browser can no longer reach Speech, real-time dictation must
connect through the frontend: `DIRECT_SDK_ACCESS=false`, and the frontend's
Caddyfile proxies `/cognitiveservices/*` to `AZURE_SPEECH_ENDPOINT`
server-side, over the private endpoint.

We comply rather than take a policy exception. Both apps this product replaces
run their Speech accounts as named `notScopes` exceptions in
`assign.allowed_ai_resources.json`; that is not the CNP default.

## Key Vault access

The vault uses **access policies, not Azure RBAC**. RBAC was tried and cannot
work here: it needs the module to grant Jenkins *Key Vault Administrator*, and
the Jenkins identity's role-assignment permission has an ABAC condition that
forbids granting that role. Every secret write then failed with
`Assignment: (not found)` (builds #4–#6). Access policies need no role
assignments, which is why every CNP product uses them.

**Product group — `DTS Transcribe`.** In access-policy mode the module always
creates a product-team policy, resolving `product_group_name` by display name,
so the group must exist before `terraform plan` can succeed. Per CNP
convention it is defined as code in `hmcts/azure-access` (`users/groups.yml`,
created by azure-access#8294; members in `users/prod_users.yml`) and also
named as `azure_ad_group` in `team-config.yml` (cnp-jenkins-config#1368) and as
`TEAM_AAD_GROUP_ID` in `cnp-flux-config`. Members of this group add the secrets
that cannot be generated — see "Secrets that must be seeded by hand".

The two apps this replaces use `DTS Platform Operations` here, which leaves the
product team unable to manage its own secrets; a product group is the CNP norm
(`DTS Darts Modernisation`, `DTS Possession Claim Service`, `CPP Rota`).

## Key Vault secrets wait for the vault module

Every `azurerm_key_vault_secret` here carries `depends_on = [module.vault]`.
Jenkins' permission to write secrets is a separate resource inside the module,
and a secret only references `key_vault_id`, so without the dependency
Terraform writes secrets in parallel with that grant. Keep it.

## Role assignments Jenkins is allowed to make

Jenkins' permission to create role assignments is *Role Based Access Control
Administrator* on the subscription, with an ABAC condition that allows exactly
six roles: Cognitive Services OpenAI User, Cognitive Services User, PostgreSQL
Flexible Server Long Term Retention Backup Role, Reader, Storage Account
Contributor and Storage Blob Data Contributor. Any other role — Key Vault
Administrator, Cognitive Services Speech User, Storage Blob Data Reader — is
refused at apply time. Choose from that list, or ask PlatOps to make the grant.

This repo grants the product managed identity (`transcribe-<env>-mi`):

- **Cognitive Services User** on the Speech account (for Speech tokens and
  batch transcription; Speech User is not permitted).
- **Storage Blob Data Contributor** on the storage account (the API's audio
  I/O and its user-delegation SAS URLs).

## Deploying

The pipeline runs Terraform per environment; `env`, `product` and
`subscription` are injected as `-var` at runtime and must never be set in the
`.tfvars` files.
