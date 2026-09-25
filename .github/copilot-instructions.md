# Minecraft EC2 Terraform contributor guidance

This repository manages a production Minecraft fleet with Terraform, host-side
Bash scripts, and a Node.js Discord Lambda. Preserve existing infrastructure
addresses, migration safeguards, command responses, and operational defaults
unless a change explicitly requires otherwise.

Before proposing or committing a change:

- Run `terraform fmt -check -recursive`, initialize with the committed provider
  lock file, and run `terraform validate`.
- In `modules/discord-bot-lambda/lambda`, run `yarn install --frozen-lockfile`,
  `yarn typecheck`, `yarn test`, and `yarn build`.
- Run ShellCheck and `bash -n` for Bash scripts, and parse PowerShell scripts.
- Never run `terraform apply` as a validation step. Review a saved plan against
  the real private variables and state before any deployment.
- Do not rename stable server keys or Terraform resource labels without an
  explicit state migration.
- Do not weaken `prevent_destroy`, archive checksum verification, signature
  verification, replay protection, or the controlled world-volume migration.
- Keep secrets and private `.tfvars` files out of the repository.

Generated directories such as `.terraform`, `node_modules`, `dist`, and `tmp`
must remain untracked.
