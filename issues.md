# Known Build Issues

This document records upstream build issues encountered in this NixOS configuration.
The ZeroFS-related entries below are historical: ZeroFS has been removed, and they
are not current deployment instructions or runtime-health claims.

## dragonflydb

**Status:** Historical. Redis was used instead; the ZeroFS module and its experimental configuration have since been removed.

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
- This no longer blocks the configuration because the ZeroFS deployment has been removed.

---

## zerofs (webui feature)

**Status:** Historical. The former deployment used the stable binary without the `webui` feature. ZeroFS and its generated configuration have since been removed.

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

**Impact at the time:**
- The optional embedded Web UI could not be built.
- This no longer blocks the configuration. ZeroFS was later retired because of restart/power-loss reliability problems; successful compilation did not establish storage reliability.
