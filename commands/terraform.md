# Terraform Command Reference

## Terraform Workflow

The standard Terraform workflow is:

```text
Write configuration
        ↓
terraform fmt
        ↓
terraform init
        ↓
terraform validate
        ↓
terraform plan
        ↓
terraform apply
        ↓
terraform destroy
```

## Initialize a Configuration

```bash
terraform init
```

`terraform init`:

- Downloads required providers
- Initializes configured modules
- Configures the Terraform backend
- Creates or updates `.terraform.lock.hcl`

Initialize without configuring a remote backend:

```bash
terraform init -backend=false
```

This is useful in CI validation workflows where no Terraform state is required.

Reinitialize after changing provider, module, or backend configuration:

```bash
terraform init -reconfigure
```

Upgrade providers within the permitted version constraints:

```bash
terraform init -upgrade
```

## Format Terraform Code

Format the current directory:

```bash
terraform fmt
```

Format all nested Terraform directories:

```bash
terraform fmt -recursive
```

Check formatting without modifying files:

```bash
terraform fmt -check -recursive
```

A non-zero exit code indicates that one or more files require formatting.

## Validate Configuration

```bash
terraform validate
```

Validation checks:

- HCL syntax
- Resource argument structure
- Variable references
- Output references
- Provider schema compatibility
- Internal configuration consistency

Validation does not create resources.

It also does not fully verify whether the current credentials have permission to create the infrastructure.

## Create an Execution Plan

```bash
terraform plan
```

A plan compares:

- Terraform configuration
- Terraform state
- Current remote infrastructure

Common plan symbols:

```text
+ create
~ update in place
-/+ destroy and recreate
- destroy
<= read data source
```

Provide a variable directly:

```bash
terraform plan \
  -var="project_id=my-gcp-project"
```

Use a variable file:

```bash
terraform plan \
  -var-file="terraform.tfvars"
```

Save a plan:

```bash
terraform plan \
  -out=tfplan
```

Review the saved plan:

```bash
terraform show tfplan
```

Show it in JSON format:

```bash
terraform show -json tfplan
```

A plan normally does not create infrastructure, but it can contact provider APIs to read the current environment.

## Apply Infrastructure

```bash
terraform apply
```

Apply a previously reviewed plan:

```bash
terraform apply tfplan
```

Using a saved plan is safer because Terraform applies the exact plan that was reviewed.

Automatic approval:

```bash
terraform apply -auto-approve
```

Automatic approval should be used carefully, especially for production infrastructure.

## Destroy Infrastructure

Preview destruction:

```bash
terraform plan -destroy
```

Destroy resources:

```bash
terraform destroy
```

Destroy without interactive approval:

```bash
terraform destroy -auto-approve
```

For this repository, Cloud SQL deletion protection must be disabled before Terraform can destroy the database instance.

## Work with Another Directory

Terraform supports running against a directory without changing into it:

```bash
terraform -chdir=terraform/cloud-sql init -backend=false
```

```bash
terraform -chdir=terraform/cloud-sql fmt -check -recursive
```

```bash
terraform -chdir=terraform/cloud-sql validate
```

This is useful in CI pipelines and repositories containing multiple Terraform root configurations.

## Inspect Providers

```bash
terraform providers
```

This shows:

- Providers required by the configuration
- Providers recorded in state
- Provider dependencies introduced by modules

It does not display every resource managed by the provider.

## Inspect the Dependency Graph

```bash
terraform graph
```

Filter important GCP resources:

```bash
terraform graph |
  grep -E 'google_sql|google_compute|google_service'
```

Generate a visual graph when Graphviz is installed:

```bash
terraform graph |
  dot -Tpng > terraform-graph.png
```

Terraform automatically creates dependencies when one resource references another.

Explicit dependencies can be added using:

```hcl
depends_on = [
  google_service_networking_connection.private_services
]
```

Explicit dependencies should only be used when Terraform cannot infer the relationship through resource references.

## Terraform State

Terraform state maps configuration resources to real infrastructure.

List resources in state:

```bash
terraform state list
```

Inspect a resource:

```bash
terraform state show \
  google_sql_database_instance.postgresql
```

Remove a resource from state without deleting the real resource:

```bash
terraform state rm \
  google_sql_database_instance.postgresql
```

Move or rename a state entry:

```bash
terraform state mv \
  google_sql_database_instance.old \
  google_sql_database_instance.postgresql
```

State can contain sensitive information and must not be committed to Git.

Ignored state patterns include:

```text
*.tfstate
*.tfstate.*
```

Production environments should normally use a remote backend with:

- Encryption
- Access control
- State locking where supported
- Versioning
- Audit logging

## Import Existing Infrastructure

Generate an import block:

```hcl
import {
  to = google_sql_database_instance.postgresql
  id = "projects/PROJECT_ID/instances/INSTANCE_NAME"
}
```

Preview the import:

```bash
terraform plan
```

Import using the CLI:

```bash
terraform import \
  google_sql_database_instance.postgresql \
  projects/PROJECT_ID/instances/INSTANCE_NAME
```

Import adds an existing resource to Terraform state. The matching Terraform configuration must still be written and reviewed.

## Detect Configuration Drift

Run:

```bash
terraform plan
```

Terraform compares the configuration and state with the current remote infrastructure.

A refresh-only plan updates Terraform's understanding without proposing configuration-driven changes:

```bash
terraform plan -refresh-only
```

Apply refreshed state information:

```bash
terraform apply -refresh-only
```

Manual cloud-console changes can cause drift and should be reviewed before applying Terraform.

## Terraform Console

Start an interactive expression console:

```bash
terraform console
```

Examples:

```hcl
var.region
```

```hcl
length(local.required_apis)
```

```hcl
cidrsubnet("10.10.0.0/16", 8, 1)
```

Exit using:

```text
exit
```

## Output Values

Display all outputs:

```bash
terraform output
```

Display one output:

```bash
terraform output cloud_sql_connection_name
```

Return a raw value:

```bash
terraform output -raw cloud_sql_connection_name
```

Return outputs as JSON:

```bash
terraform output -json
```

Outputs only contain deployed values after infrastructure has been recorded in Terraform state.

## Variables

Terraform commonly loads variables from:

```text
terraform.tfvars
*.auto.tfvars
TF_VAR_<variable_name>
-var
-var-file
```

Example environment variable:

```bash
export TF_VAR_project_id="my-gcp-project"
```

Example command-line variable:

```bash
terraform plan \
  -var="project_id=my-gcp-project"
```

Do not commit production credentials or sensitive variable files.

## Sensitive Values

Mark sensitive variables:

```hcl
variable "database_password" {
  type      = string
  sensitive = true
}
```

Mark sensitive outputs:

```hcl
output "database_password" {
  value     = var.database_password
  sensitive = true
}
```

The `sensitive` flag hides values from normal CLI output, but the values can still be stored in Terraform state.

Use Secret Manager or another dedicated secrets platform instead of committing secrets to Terraform files.

## Resource Targeting

Target one resource:

```bash
terraform plan \
  -target=google_sql_database_instance.postgresql
```

Targeting should be reserved for exceptional recovery or troubleshooting situations.

It should not be used as the standard deployment workflow because it can produce incomplete infrastructure changes.

## Replace a Resource

Force replacement during the next apply:

```bash
terraform plan \
  -replace=google_sql_database_instance.postgresql
```

This is preferred over the older `terraform taint` workflow.

Replacing a database resource can be destructive and must be reviewed carefully.

## Lifecycle Protection

Terraform-level deletion protection:

```hcl
resource "google_sql_database_instance" "postgresql" {
  deletion_protection = true
}
```

Provider-level Cloud SQL protection:

```hcl
settings {
  deletion_protection_enabled = true
}
```

These controls protect against different deletion paths and are useful together for critical databases.

## Useful Commands for This Repository

From the repository root:

```bash
terraform -chdir=terraform/cloud-sql fmt -check -recursive
```

```bash
terraform -chdir=terraform/cloud-sql init -backend=false
```

```bash
terraform -chdir=terraform/cloud-sql validate
```

```bash
terraform -chdir=terraform/cloud-sql graph |
  grep -E 'google_sql|google_compute|google_service'
```

## Important Interview Points

- Terraform configuration describes the desired infrastructure state.
- Terraform state maps configuration objects to real resources.
- `terraform init` installs providers and initializes the backend.
- `terraform fmt` provides consistent formatting.
- `terraform validate` checks configuration consistency.
- `terraform plan` previews changes.
- `terraform apply` makes infrastructure changes.
- Provider lock files should normally be committed.
- Terraform state files must not be committed.
- Remote state should be protected using encryption, access controls, and versioning.
- Resource references create implicit dependencies.
- `depends_on` creates explicit dependencies.
- Saved plans help ensure that the reviewed changes are the changes applied.
- Manual infrastructure modifications can create drift.
- Sensitive values can still exist in Terraform state even when marked sensitive.
- Terraform should provision infrastructure, while database schema migrations should normally be handled separately.
