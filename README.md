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

Built here, by `terraform-module-ai-services` — the platform's approved module
for cognitive accounts. (A bare `azurerm_cognitive_account` is *not* on any
whitelist; the module is, globally, so this needs no resource approval. The one
approval this repo does need is for `azurerm_role_assignment`, used to grant the
product managed identity data-plane access — see
`terraform-infra-approvals/transcribe-shared-infrastructure.json` in
`hmcts/cnp-jenkins-config`.)

**No API keys exist.** The account is created with
`cognitive_account_local_auth_enabled = false`, so Speech issues no key at all.
The API authenticates with the product managed identity and mints an
`aad#<resourceId>#<token>` for the Speech SDK, which is why the vault holds
`azure-speech-resource-id` and not `azure-speech-key`.

`speech_public_network_access` defaults to **true**, and that is not the end
state. A private endpoint is the target, but it is not sufficient on its own:
real-time dictation has the *browser* open a websocket to Speech, so locking the
account to the VNet also means routing that traffic through the frontend. The
`Caddyfile` already proxies `/cognitiveservices/*` for exactly this, selected by
`DIRECT_SDK_ACCESS`. Until that path is proven end to end, closing public access
would break dictation rather than secure it. Keys stay disabled either way, so a
reachable endpoint still only accepts Entra tokens.

## Key Vault secrets are ordered after the vault's role assignments

Every `azurerm_key_vault_secret` here carries `depends_on = [module.vault]`.
Do not remove it.

The vault uses RBAC authorisation (see `vault.tf` for why), so the module
grants Jenkins its data-plane role in the same apply that creates the vault. A
secret only references `key_vault_id`, which Terraform knows the moment the
vault exists, so without the explicit dependency it writes the secret *in
parallel with* that role assignment and is refused:

```
... is not authorized to perform action on resource.
If role assignments, deny assignments or role definitions were changed recently,
please observe propagation time.
Assignment: (not found)
```

Despite the wording, the first cause was ordering, not propagation — builds #4
and #5 in aat both failed this way, and the role assignments were still being
created in #5. Ordering is now fixed. A residual propagation delay right after
the grant is possible but should be rare; if the very first apply in a new
environment still hits it, re-run the build.

## Deploying

The pipeline runs Terraform per environment; `env`, `product` and
`subscription` are injected as `-var` at runtime and must never be set in the
`.tfvars` files.
