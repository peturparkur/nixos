# Known Build Issues

This document tracks upstream build issues we have hit in this NixOS configuration.

## dragonflydb

**Status:** Reverted to Redis. A commented-out configuration is preserved in `modules/zerofs.nix`.

**Problem:**
The `dragonflydb` package in `nixos-26.05` fails to build from source with a hash mismatch followed by a patch failure.

**Error:**
```
error: hash mismatch in fixed-output derivation:
         specified: sha256-n70IB32tZDe665hVLrKC0BSSJutmYhtPJvfNa48xaqA=
            got:    sha256-wFmf/3WSq9qhIf1wGDeOX4IplAjiC4avdZH3JwweQS8=
```

After overriding the hash to match the current upstream archive, the build then fails with:
```
patching file absl/debugging/internal/symbolize.h
Hunk #1 FAILED at 28.
1 out of 1 hunk FAILED
```

**Root Cause:**
`dragonflydb` uses `fetchFromGitHub` with `fetchSubmodules = true`. The nixpkgs hash was recorded against a specific snapshot of the source and its submodules. Upstream later force-pushed the tag or updated submodules, causing both the hash mismatch and a source-level incompatibility with the `abseil-cpp` patch that nixpkgs applies during the build.

**Impact:**
- The `dragonflydb` binary cannot be produced from the current `nixos-26.05` package definition.
- Awaiting an upstream nixpkgs fix before it can be re-enabled.

---

## zerofs (webui feature)

**Status:** Stable `zerofs` (1.1.7) is used without the `webui` feature. The `[servers.webui]` config section is still generated in `/etc/zerofs.toml`, but the binary ignores it. The `zerofs` CLI (e.g. `zerofs monitor`) works fine.

**Problem:**
The optional `webui` Cargo feature fails to compile in both the stable and unstable nixpkgs packages.

**Error:**
```
error: could not compile `zerofs` (bin "zerofs") due to 3 previous errors
error[E0599]: no method named `get` found for struct ...
```

**Investigation:**
1. The Web UI was not starting despite the service running and the config being present.
2. The nixpkgs package does not enable the `webui` Cargo feature by default (it is optional: `webui = ["dep:rust-embed", "dep:axum", "dep:tonic-web", "dep:tower-http"]`).
3. We attempted to enable it by overriding `cargoBuildFeatures`.
4. The build failed with the same trait method error in both versions:
   - **1.1.7** (stable `nixos-26.05`)
   - **1.1.15** (unstable `nixpkgs`)

**Root Cause:**
The upstream `webui` feature code is incompatible with the dependency versions provided by nixpkgs (specifically a missing `.get()` trait implementation). This is an upstream source bug, not a packaging issue.

**Impact:**
- The embedded Web UI on port 8080 is unavailable.
- All other zerofs functionality (NFS, 9P, NBD, RPC, `zerofs monitor`) works correctly using the stable binary.
- Awaiting a future upstream release where the `webui` feature compiles cleanly.
