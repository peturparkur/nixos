# Repository guide

Personal NixOS system configuration for a laptop and a home cluster, including user environments managed through Home Manager.

## Source of truth

- Treat executable Nix configuration and its import graph as authoritative for declared behavior. A file's presence does not mean it is enabled; start at `flake.nix` and follow imports for the target host.
- Documentation explains navigation, intent, and operational context—not an inventory of current settings. Configured services are not proof of actual use or runtime health.
- Update documentation when structure, purpose, or assumptions change. Do not duplicate host lists, IPs, package versions, service assignments, or option values in this guide, or require documentation edits for routine configuration changes.

## Where to look

| Path | Purpose |
| --- | --- |
| `flake.nix`, `flake.lock` | Entry point: inputs, pinned dependencies, host outputs, shared/host-specific module composition, and topology passed to modules. |
| `configuration.nix` | Common OS baseline and system tools; retained generated examples are commented out. |
| `networking.nix` | Shared cluster networking configuration. |
| `nodes/<host>/default.nix` | Host-specific configuration and imports. |
| `nodes/<host>/hardware.nix` | Machine-specific disks, boot, and hardware configuration. |
| `modules/` | Reusable NixOS features and custom option definitions; some files also configure services directly. |
| `services/` | Service configurations and concrete instances of custom modules. |
| `kubes/` | NixOS support for Kubernetes and its storage prerequisites, not a general Kubernetes manifests directory. |
| `pkgs/` | Package-oriented configuration modules/helpers, not necessarily Nix package derivations. |
| `users/` | NixOS accounts, permissions, and user package helpers. |
| `home/` | Home Manager settings, user programs/services, and shell dotfiles. |
| `kernel/` | Optional kernel-selection modules; check imports before assuming one is used. |
| `secrets/`, `.sops.yaml` | Encrypted SOPS data and recipient rules; shared integration is in `flake.nix`. Never commit decrypted secrets or private keys. |
| `justfile` | Local rebuild and dependency-update shortcuts. |
| `README.md` | Human-facing navigation, workflows, and operational caveats, including storage usage and migration intent. |
| `docs/`, `issues.md` | Deployment background and troubleshooting notes; verify examples and outstanding issues against current code before acting. |

## Workflows and operational context

Keep how-to instructions in the README; reference them here rather than duplicating commands or procedures:

- [Rebuild and update](README.md#rebuild-and-update): applying configuration and updating dependencies.
- [Secrets](README.md#secrets): age-key prerequisites, editing secrets, and updating recipients.
- [Reconfiguring Powerlevel10k](README.md#reconfiguring-powerlevel10k): regenerating the shell prompt configuration.
- [Storage status and planned migration](README.md#storage-status-and-planned-migration): read before changing storage; see [Garage](README.md#garage) and [ZeroFS](README.md#zerofs) for operational context.

## Editing guidance

- Keep changes scoped; do not deploy, migrate data, or update dependencies as a side effect of a documentation or comment cleanup.
- Preserve comments explaining intent, workarounds, or deliberately retained optional settings. Avoid comments that merely restate code.
