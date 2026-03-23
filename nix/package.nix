# NemoClaw package: two-phase build mirroring the Dockerfile's 2-stage pattern.
#
# Phase A — compile the TypeScript plugin (buildNpmPackage)
# Phase B — assemble plugin + blueprint + bin + scripts into a single derivation
{ lib, stdenv, buildNpmPackage, makeWrapper
, constants, sources, openclaw, nodejs, python }:

let
  # Phase A: compile the TypeScript OpenClaw plugin
  plugin = buildNpmPackage {
    pname = "nemoclaw-plugin";
    version = constants.nemoclawVersion;
    src = sources.pluginSrc;

    npmDepsHash = "sha256-htKa54tdIhoJ/44buuF7bRZ2HXVwha/H9mFBV9X+weg=";

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

in
stdenv.mkDerivation {
  pname = "nemoclaw";
  version = constants.nemoclawVersion;
  src = sources.projectSrc;

  nativeBuildInputs = [ makeWrapper ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    # Plugin files
    mkdir -p $out/lib/nemoclaw
    cp -r ${plugin}/dist       $out/lib/nemoclaw/dist
    cp -r ${plugin}/node_modules $out/lib/nemoclaw/node_modules
    cp    ${plugin}/openclaw.plugin.json $out/lib/nemoclaw/
    cp    ${plugin}/package.json         $out/lib/nemoclaw/

    # Blueprint
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

    # Wrapper binary
    mkdir -p $out/bin
    makeWrapper ${nodejs}/bin/node $out/bin/nemoclaw \
      --add-flags "$out/lib/bin/nemoclaw.js" \
      --prefix PATH : ${lib.makeBinPath [ nodejs python openclaw ]}

    runHook postInstall
  '';

  meta = {
    description = "NemoClaw — run OpenClaw inside OpenShell with NVIDIA inference";
    homepage = "https://github.com/NVIDIA/NemoClaw";
    license = lib.licenses.asl20;
    mainProgram = "nemoclaw";
  };
}
