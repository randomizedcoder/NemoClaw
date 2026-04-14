# Reusable source filtering for NemoClaw builds.
# Keeps derivations from rebuilding when unrelated files change.
{ lib, constants }:

let
  root = ./..;

  # Filter that excludes patterns listed in constants.excludePatterns
  excludeFilter =
    path: _type:
    let
      baseName = baseNameOf (toString path);
    in
    !builtins.elem baseName constants.excludePatterns;

  # Full project source minus excluded directories
  projectSrc = lib.cleanSourceWith {
    src = root;
    filter = excludeFilter;
    name = "nemoclaw-source";
  };

  # Sub-source filters are intentionally specific to each directory's build artifacts,
  # independent of constants.excludePatterns which covers the full project source.

  # Just the nemoclaw/ TypeScript plugin directory
  pluginSrc = lib.cleanSourceWith {
    src = root + "/nemoclaw";
    filter =
      path: type:
      let
        baseName = baseNameOf (toString path);
      in
      !builtins.elem baseName [
        "node_modules"
        "dist"
      ];
    name = "nemoclaw-plugin-source";
  };

  # Just the nemoclaw-blueprint/ directory (blueprint.yaml + policies only)
  blueprintSrc = lib.cleanSourceWith {
    src = root + "/nemoclaw-blueprint";
    filter = _path: _type: true;
    name = "nemoclaw-blueprint-source";
  };

  # Root CLI source — compiled via tsconfig.src.json to dist/
  cliSrc = lib.cleanSourceWith {
    src = root;
    filter =
      path: type:
      let
        baseName = baseNameOf (toString path);
        relPath = lib.removePrefix (toString root + "/") (toString path);
      in
      # Include root config files needed for the build
      builtins.elem baseName [
        "package.json"
        "package-lock.json"
        "tsconfig.src.json"
      ]
      # Include the src/ directory and everything inside it
      || baseName == "src"
      || (
        lib.hasPrefix "src/" relPath
        && !builtins.elem baseName [
          "node_modules"
          "dist"
        ]
      )
      # Include bin/ directory — src/ imports JSON files from bin/lib/
      || baseName == "bin"
      || lib.hasPrefix "bin/" relPath;
    name = "nemoclaw-cli-source";
  };

  # Just the docs/ directory
  docsSrc = lib.cleanSourceWith {
    src = root + "/docs";
    filter =
      path: type:
      let
        baseName = baseNameOf (toString path);
      in
      !builtins.elem baseName [
        "_build"
        "__pycache__"
      ];
    name = "nemoclaw-docs-source";
  };

in
{
  inherit
    projectSrc
    pluginSrc
    blueprintSrc
    cliSrc
    docsSrc
    ;
}
