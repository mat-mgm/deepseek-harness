# Agent Note: Nix flake devShell and dsh package

Status: implemented

## Problem

Running the harness locally required an imperative `pnpm install` against whatever Node, pnpm, and C toolchain happened to be on the host, with no reproducible, declarative way to obtain a working development environment or a standalone `dsh` binary outside the repository checkout.

## Decision

`flake.nix` exposes `devShells.<system>.default` (`nodejs_22`, `pnpm_11`, `python3`, `gcc`, `git`, prepending `node_modules/.bin` to `PATH`) and `packages.<system>.dsh`, built by `nix/dsh.nix` via `pkgs.callPackage`. The package derivation follows nixpkgs' standard pnpm pattern (`fetchPnpmDeps` + `pnpmConfigHook`) with `nodejs_22`/`pnpm_11` pinned to match `package.json`'s `engines`/`packageManager` fields, runs the repository's own `pnpm run build` unmodified, and wraps `apps/cli/lib/bin.js` as `$out/bin/dsh` with `makeWrapper`.

Two environment variables route around behavior that assumes a live repository rather than a Nix store copy: `npm_config_nodedir`/`npm_config_build_from_source` point `node-gyp` (pulled in transitively for `node-pty`) at the pinned `nodejs` derivation instead of fetching Node headers over the network, and `DSH_CLIENT_COMMIT_HASH = "0000000"` (see [`scripts/client-build-environment.ts`](../../../../scripts/client-build-environment.ts)) substitutes for the `git rev-parse HEAD` call that fails against `lib.cleanSource`'s `.git`-less copy.

`dontCheckForBrokenSymlinks = true` disables nixpkgs' generic `noBrokenSymlinks` fixup check. `fetchPnpmDeps` does not materialize every platform variant of `@anthropic-ai/claude-agent-sdk` and `@openai/codex`, both listed under `minimumReleaseAgeExclude` in `pnpm-workspace.yaml` as multi-platform version-union exemptions; the resulting dangling `*-linux-x64` optional-platform symlinks under `node_modules/.pnpm/` are inert for the `dsh` CLI's own code paths but otherwise fail the build.

## Alternatives considered

**Cross-compile a static, musl-linked binary via `musl-gcc`.** The repository's own `build:native-system` script already accepts `--host-addon-only`, which the root `build` script passes; this skips the optional static Landlock binary and builds only the glibc-targeted Node-API addon, so no musl toolchain is needed in the devShell or the derivation.

**Patch `pnpm-workspace.yaml`'s `minimumReleaseAgeExclude` or otherwise force `fetchPnpmDeps` to resolve every optional platform variant.** This would touch source under version control to work around a Nix-specific packaging gap and would need re-verification against every future exemption the workspace adds. Disabling the unrelated fixup check with an explained escape hatch keeps the change local to the Nix derivation.

**Vendor a separate lockfile or dependency subset for the Nix build.** The derivation builds the same `pnpm-lock.yaml` the rest of the repository uses; a parallel lockfile would drift and double the maintenance surface for a single-package CLI build.

## Consequences

A full `nix build .#dsh` compiles the native addon, host/client `tsc`/`tsdown` outputs, the web frontend, and the Electron desktop app, and installs the whole built tree under `$out/libexec/deepseek-harness` with `$out/bin/dsh` wrapping `apps/cli/lib/bin.js`. The build is CPU- and memory-heavy (the whole monorepo, not just the CLI's own workspace); callers running it under a memory-constrained cgroup (e.g. `systemd-run --user --scope -p MemoryMax=...`) should budget accordingly. `pnpmDeps.hash` in `nix/dsh.nix` must be updated whenever `pnpm-lock.yaml` changes; a stale hash fails the build with Nix's standard fixed-output mismatch error, which also serves as the way to compute the next hash.

`dontCheckForBrokenSymlinks = true` is scoped to this derivation only and does not affect the rest of the repository's build or test paths run outside Nix.
