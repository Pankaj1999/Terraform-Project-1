# KEDB Runbook: Terraform Azure Deployment Failures

## Purpose

Known-error runbook for the Terraform deployment in this repository. It covers the failures seen during deployment, how to identify their causes, and a safe recovery sequence.

## Before troubleshooting

1. Open the failed Azure DevOps run and identify the failing Terraform command and working directory. This project runs Terraform from `dev`.
2. Confirm which Azure service connection the failing task uses. The identity used for `azurerm` and `azuread` operations must have the permissions described below.
3. Do not paste service-connection secrets, client secrets, private keys, or state-file contents into logs, tickets, or this runbook.
4. Keep `terraform init`, `plan`, and `apply` on the same agent job, or initialize the backend again in each job. Hosted agents are ephemeral.
5. After a failed apply, inspect the existing remote state and run a fresh plan. Terraform may have completed and recorded some resources before another resource failed; do not delete resources or state to force a retry.

## Error: unsupported Terraform Core version

**Typical message**

`This configuration does not support Terraform version 1.5.7. required_version = ">= 1.9.0"`

**Cause**

The agent's Terraform version is below the `required_version` constraint in `dev/providers.tf`.

**Resolution**

1. Keep the version constraint unless the configuration has been tested and is intentionally being made compatible with an older Terraform release.
2. Install Terraform 1.9.0 or a later compatible version in the pipeline before running Terraform commands:

   ```yaml
   - task: TerraformInstaller@1
     inputs:
       terraformVersion: '1.9.0'
   ```

3. Add a diagnostic step immediately afterward:

   ```yaml
   - script: |
       which terraform
       terraform version
     displayName: Verify Terraform installation
   ```

4. Ensure the Terraform task runs in the same job, after the installer.
5. Confirm the logged version satisfies the constraint, then rerun `init` and `validate`.

## Error: Terraform executable could not start (`ENOENT`)

**Typical message**

`spawn .../terraform ENOENT`

**Cause**

The Terraform task selected a path in the hosted tool cache, but no executable existed at that path. This is an agent/tool installation or task-order problem, not a configuration-version constraint error.

**Resolution**

1. Ensure the installer task runs before every Terraform job that needs Terraform. A different job or hosted agent cannot rely on an earlier job's tool installation.
2. Use the Terraform Installer task supported by the Azure DevOps organization and install the required version.
3. Run the `which terraform` and `terraform version` diagnostic shown above in the same job.
4. If the command fails or reports a different version, check the installer task result, task ordering, agent image, and whether a later step changes `PATH`.
5. Only run `TerraformTaskV4` after the diagnostic confirms the executable is present.

## Error: Entra ID application creation returns 403

**Typical message**

`Authorization_RequestDenied: Insufficient privileges to complete the operation`

**Cause**

The identity used by the AzureAD provider cannot create or manage app registrations in the Entra tenant. Azure subscription roles such as `Contributor` do not grant Microsoft Entra directory permissions.

**Resolution**

1. In Azure DevOps, open **Project settings → Service connections** and identify the service connection used by the failing deployment task.
2. Have an Entra administrator verify that the service connection's service principal belongs to the expected tenant.
3. Grant the identity the minimum appropriate directory permission to create and manage the applications Terraform owns. A common option is Microsoft Graph **Application.ReadWrite.All** as an application permission with tenant admin consent. A suitable Entra directory role, such as **Application Administrator**, may also be used according to tenant policy.
4. Do not grant permissions to a developer's personal account when the pipeline uses a service principal.
5. Rerun the deployment after permissions propagate. If the application was created despite a reported failure, inspect Terraform state and the tenant before attempting manual cleanup.

## Error: role assignment creation returns 403

**Typical message**

`does not have authorization to perform action 'Microsoft.Authorization/roleAssignments/write'`

**Cause**

The pipeline identity is trying to create an Azure RBAC role assignment (the configuration assigns `Contributor` to the generated service principal), but its own role does not permit creating role assignments. `Contributor` alone does not include this permission.

**Resolution**

1. Confirm the failing identity is the service principal used by the deployment's Azure Resource Manager service connection.
2. Ask a subscription administrator to grant that identity **Role Based Access Control Administrator** or **User Access Administrator** at the narrowest scope that contains the Terraform role assignment. This configuration creates an assignment at subscription scope, so a resource-group-only grant will not authorize that operation.
3. If organizational policy prohibits these roles, ask the administrator to create the required assignment outside Terraform and adjust the Terraform configuration so it no longer tries to create it. Do not repeatedly rerun an unauthorized role-assignment operation.
4. Allow time for role propagation, refresh/re-authenticate the service connection if needed, and rerun the pipeline.

## Error: Key Vault secret read returns 403

**Typical message**

`does not have secrets get permission on key vault`

**Cause**

The identity running Terraform can reach the vault but lacks secret data-plane permissions. Azure management-plane roles do not automatically grant Key Vault secret access.

**Resolution**

1. Identify the exact pipeline identity from the failing task's service connection. In the error, `oid` is the identity's object ID; do not use the client ID in its place.
2. Check the vault's permission model in Azure. This repository configures Key Vault access policies.
3. The Key Vault module grants the current AzureRM provider identity `Get`, `Set`, and `Delete` secret permissions using an access policy. Apply that configuration using an identity that already has permission to manage the vault's access policies.
4. Confirm the access policy is present for the pipeline identity and allow time for changes to propagate.
5. If the vault uses Azure RBAC instead of access policies, configure an appropriate vault-scoped data role (for example, **Key Vault Secrets Officer**) for the Terraform identity instead. Do not mix permission models without confirming the vault configuration.
6. Retry the plan/apply. If the error persists, verify the task's service connection is the same identity named in the policy and that the vault's networking/firewall permits the agent.

## Error: AKS availability zone is unsupported

**Typical message**

`AvailabilityZoneNotSupported` and `The supported zones for location ... are ''`

**Cause**

The AKS node pool specifies availability zones that are not available for the chosen region, subscription, or requested resource configuration.

**Resolution**

1. Check the location configured for the cluster and the exact supported zones for the subscription and VM SKU.
2. If zones are not required, remove the `zones` argument from the node-pool configuration. This repository's AKS module leaves zones unspecified.
3. If zonal placement is required, select a supported zone/SKU combination or a region that supports it; do not guess zone numbers.
4. Run `terraform plan` and verify the planned cluster/node-pool changes before applying.

## Error: Key Vault name is already in use

**Typical message**

`VaultAlreadyExists` or `The vault name ... is already in use`

**Cause**

Key Vault names are globally unique. The name may belong to another tenant/subscription, or the vault may be soft-deleted and still reserved.

**Resolution**

1. If creating a new vault, choose a globally unique name that meets Azure Key Vault naming requirements (3–24 characters; letters, digits, and hyphens).
2. If the vault should already belong to this deployment, verify its subscription, resource group, and identity. Import it into the correct Terraform state only after confirming ownership and reviewing the import plan.
3. If the name is reserved by a soft-deleted vault, ask the owner to recover it or, only if permanent deletion is explicitly intended and authorized, purge it. Purging is irreversible.
4. Do not destroy or purge an unknown vault just to free its name.

## Error: AKS OIDC issuer cannot be disabled

**Typical message**

`OIDCIssuerFeatureCannotBeDisabled`

**Cause**

Terraform is attempting to update an existing AKS cluster with the OIDC issuer disabled, while Azure does not permit disabling that feature for the cluster.

**Resolution**

1. In the AKS cluster resource, set `oidc_issuer_enabled = true`. This repository's AKS module now explicitly enables it.
2. Run `terraform plan` and check that Terraform is not proposing to disable OIDC or replace the cluster unexpectedly.
3. If the cluster was created outside this state or its settings differ, inspect the live cluster and Terraform state before applying. Import the cluster if necessary; do not remove it from Azure to bypass the error.
4. Apply only after reviewing the plan. If using workload identity, ensure its related configuration is intentionally enabled as well.

## Safe retry and verification checklist

1. Confirm all required Entra directory, Azure RBAC, and Key Vault data-plane permissions are assigned to the service-connection identity.
2. Confirm `terraform version` meets the constraint in `dev/providers.tf`.
3. Run Terraform from `dev` and initialize the configured remote backend:

   ```sh
   terraform -chdir=dev init
   terraform -chdir=dev validate
   terraform -chdir=dev plan
   ```

4. Review the plan for unexpected replacement or destruction, especially for the AKS cluster, Key Vault, and existing resources.
5. Apply through the approved Azure DevOps deployment job.
6. If state locking reports a lock, verify no apply is still running and identify the lock owner before considering unlock. Never force-unlock an active operation.
7. Record the pipeline run, affected resource, root cause, permission or configuration change, and outcome in the incident ticket.

## Current project references

- Terraform core constraint and providers: [`dev/providers.tf`](./dev/providers.tf)
- Azure DevOps pipeline: [`create.yml`](./create.yml)
- AKS cluster configuration: [`modules/aks/main.tf`](./modules/aks/main.tf)
- Key Vault configuration and Terraform identity access policy: [`modules/keyvault/main.tf`](./modules/keyvault/main.tf)
- Subscription role assignment: [`dev/main.tf`](./dev/main.tf)
