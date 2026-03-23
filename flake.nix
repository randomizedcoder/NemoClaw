{
  description = "NemoClaw — run OpenClaw inside OpenShell with NVIDIA inference";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.permittedInsecurePackages = [
            "openclaw-2026.3.12"
          ];
        };

        # Pure data — no pkgs needed
        constants = import ./nix/constants.nix;

        # Centralized runtime dependencies (single source of truth)
        nodejs = pkgs.nodejs_22;
        python = pkgs.python314.withPackages (ps: [ ps.pyyaml ]);

        # Source filters
        sources = pkgs.callPackage ./nix/source-filter.nix { inherit constants; };

        # OpenClaw CLI from nixpkgs
        openclaw = pkgs.openclaw;

        # NemoClaw package (TS plugin + assembly)
        nemoclaw = pkgs.callPackage ./nix/package.nix {
          inherit constants sources openclaw nodejs python;
        };

        # OCI container image
        container = pkgs.callPackage ./nix/container.nix {
          inherit constants nemoclaw openclaw nodejs python;
        };

        # Documentation (best-effort, uses its own Python with Sphinx packages)
        docs = pkgs.callPackage ./nix/docs.nix { inherit constants sources; };

        # Container smoke-test script
        container-test = pkgs.callPackage ./nix/container-test.nix {
          inherit constants container;
          docker = pkgs.docker-client;
        };

      in
      {
        packages = {
          default = nemoclaw;
          inherit nemoclaw openclaw container container-test docs;
        };

        devShells.default = pkgs.callPackage ./nix/shell.nix {
          inherit nemoclaw nodejs python;
        };

        checks = {
          inherit nemoclaw;
          shell = self.devShells.${system}.default;
        };
      }
    );
}
