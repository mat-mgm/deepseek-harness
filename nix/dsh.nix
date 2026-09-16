{
  lib,
  stdenv,
  fetchPnpmDeps,
  makeWrapper,
  nodejs_22,
  pnpm_11,
  pnpmConfigHook,
  python3,
  gcc,
  git,
}:

let
  nodejs = nodejs_22;
  pnpm = pnpm_11;
in
stdenv.mkDerivation (finalAttrs: {
  pname = "dsh";
  version = "0.1.6-alpha.1";

  src = lib.cleanSource ../.;

  nativeBuildInputs = [
    nodejs
    pnpmConfigHook
    pnpm
    python3
    gcc
    git
    makeWrapper
  ];

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    inherit pnpm;
    fetcherVersion = 4;
    hash = "sha256-mXcnNIGDImq45FGVhdVTTIsMbrxdmlqpMiB5vnjRVas=";
  };

  # node-gyp (used to build the node-pty native addon) fetches Node headers
  # over the network unless pointed at an existing Node installation.
  npm_config_nodedir = "${nodejs}";
  npm_config_build_from_source = "true";

  # The Nix store copy of the source carries no .git directory; supply a
  # placeholder so the client-build commit stamp does not need `git rev-parse`.
  DSH_CLIENT_COMMIT_HASH = "0000000";

  # fetchPnpmDeps does not materialize every platform variant of
  # @anthropic-ai/claude-agent-sdk and @openai/codex (both are exempted from
  # pnpm's minimum-release-age policy in pnpm-workspace.yaml as multi-platform
  # version unions); the resulting dangling optional-platform symlinks are
  # inert for the dsh CLI's own code paths.
  dontCheckForBrokenSymlinks = true;

  buildPhase = ''
    runHook preBuild
    export HOME=$(mktemp -d)
    pnpm run build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/libexec/deepseek-harness
    cp -r . $out/libexec/deepseek-harness/
    mkdir -p $out/bin
    # node-addon-require-builtin's prebuilt binary does V8-internal
    # field-offset probing that fails against nixpkgs' Node build; --expose-internals
    # is the Loader's own documented fallback for reaching the same internals.
    makeWrapper ${nodejs}/bin/node $out/bin/dsh \
      --add-flags "--expose-internals $out/libexec/deepseek-harness/apps/cli/lib/bin.js"
    runHook postInstall
  '';

  meta = {
    description = "DeepSeek Harness CLI (dsh)";
    homepage = "https://github.com/deepseek-ai/deepseek-harness";
    license = lib.licenses.mit;
    mainProgram = "dsh";
  };
})
