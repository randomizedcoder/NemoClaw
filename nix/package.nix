# NemoClaw package: three-phase build mirroring the upstream architecture.
#
# Phase A — compile the TypeScript plugin (buildNpmPackage)
# Phase B — compile the root CLI from src/ (buildNpmPackage)
# Phase C — assemble plugin + CLI + blueprint + bin + scripts into a single derivation
{
  lib,
  stdenv,
  buildNpmPackage,
  makeWrapper,
  constants,
  sources,
  openclaw,
  nodejs,
  python,
}:

let
  # Phase A: compile the TypeScript OpenClaw plugin (nemoclaw/ directory)
  plugin = buildNpmPackage {
    pname = "nemoclaw-plugin";
    version = constants.nemoclawVersion;
    src = sources.pluginSrc;

    npmDepsHash = "sha256-Y1OfWVcYNRs/LnNui9rlW0OQSRIxa3dT2o9Q7hfwFtg=";

    # Build with tsc, then prune devDependencies
    buildPhase = ''
      runHook preBuild
      npm run build
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p $out
      cp -r dist $out/dist
      cp openclaw.plugin.json $out/
      cp package.json $out/

      # Prune devDependencies offline, then copy production deps
      npm prune --omit=dev
      cp -r node_modules $out/node_modules

      runHook postInstall
    '';

    meta.description = "NemoClaw TypeScript plugin (compiled)";
  };

  # Phase B: compile the root CLI (src/ → dist/ via tsconfig.src.json)
  # bin/nemoclaw.js is a thin shim that does require("../dist/nemoclaw")
  cli = buildNpmPackage {
    pname = "nemoclaw-cli";
    version = constants.nemoclawVersion;
    src = sources.cliSrc;

    npmDepsHash = "sha256-RTlyyxoyd+5xVQeTWvKZcmgRJDXqcM346CJcRRYNTys=";

    # Skip prepare/postinstall scripts — prek tries to download binaries,
    # and the prepare script runs build:cli (we do that explicitly below).
    npmFlags = [ "--ignore-scripts" ];

    buildPhase = ''
      runHook preBuild
      npx tsc -p tsconfig.src.json
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p $out
      cp -r dist $out/dist

      # Keep runtime deps (js-yaml, p-retry, yaml)
      npm prune --omit=dev
      cp -r node_modules $out/node_modules

      runHook postInstall
    '';

    meta.description = "NemoClaw CLI (compiled from src/)";
  };

in
stdenv.mkDerivation {
  pname = "nemoclaw";
  version = constants.nemoclawVersion;
  src = sources.projectSrc;

  nativeBuildInputs = [ makeWrapper ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    # Plugin files (compiled output for direct use)
    mkdir -p $out/lib/nemoclaw
    cp -r ${plugin}/dist       $out/lib/nemoclaw/dist
    cp -r ${plugin}/node_modules $out/lib/nemoclaw/node_modules
    cp    ${plugin}/openclaw.plugin.json $out/lib/nemoclaw/
    cp    ${plugin}/package.json         $out/lib/nemoclaw/

    # Plugin source files — the Dockerfile has its own multi-stage build that
    # compiles TypeScript from source inside the sandbox image, so the build
    # context needs tsconfig.json, src/, and package-lock.json.
    cp    nemoclaw/tsconfig.json    $out/lib/nemoclaw/
    cp    nemoclaw/package-lock.json $out/lib/nemoclaw/
    cp -r nemoclaw/src              $out/lib/nemoclaw/src

    # Root CLI compiled output — bin/nemoclaw.js does require("../dist/nemoclaw")
    cp -r ${cli}/dist $out/lib/dist
    cp -r ${cli}/node_modules $out/lib/node_modules

    # Blueprint (blueprint.yaml + policies only)
    mkdir -p $out/lib/nemoclaw-blueprint
    cp -r nemoclaw-blueprint/* $out/lib/nemoclaw-blueprint/

    # CLI entrypoint and supporting scripts
    mkdir -p $out/lib/bin
    cp bin/nemoclaw.js $out/lib/bin/
    cp -r bin/lib      $out/lib/bin/lib

    mkdir -p $out/lib/scripts
    cp -r scripts/* $out/lib/scripts/

    # Root package.json — nemoclaw.js reads it via ../package.json
    cp package.json $out/lib/package.json

    # Dockerfiles — build context needs both for sandbox image creation
    cp Dockerfile $out/lib/Dockerfile
    if [ -f Dockerfile.base ]; then
      cp Dockerfile.base $out/lib/Dockerfile.base
    fi

    # Wrapper binary
    mkdir -p $out/bin
    makeWrapper ${nodejs}/bin/node $out/bin/nemoclaw \
      --add-flags "$out/lib/bin/nemoclaw.js" \
      --set-default OPENSHELL_GATEWAY_PORT "${constants.defaults.gatewayPort}" \
      --prefix PATH : ${
        lib.makeBinPath [
          nodejs
          python
          openclaw
        ]
      }

    runHook postInstall
  '';

  # Nix auto-patches shebangs in fixupPhase to point at /nix/store/…/bash.
  # Scripts under lib/scripts/ are copied into non-nix Docker containers by
  # the build context, so restore portable shebangs after fixup runs.
  postFixup = ''
    for f in $out/lib/scripts/*.sh; do
      sed -i '1s|^#!.*/bin/bash|#!/usr/bin/env bash|' "$f"
    done
  '';

  meta = {
    description = "NemoClaw — run OpenClaw inside OpenShell with NVIDIA inference";
    homepage = "https://github.com/NVIDIA/NemoClaw";
    license = lib.licenses.asl20;
    mainProgram = "nemoclaw";
  };
}
