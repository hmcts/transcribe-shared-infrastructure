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

## Deploying

The pipeline runs Terraform per environment; `env`, `product` and
`subscription` are injected as `-var` at runtime and must never be set in the
`.tfvars` files.
