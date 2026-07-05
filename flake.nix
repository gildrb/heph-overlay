{
  description = "Nix flake overlay for Heph";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
    };

    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.uv2nix.follows = "uv2nix";
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      pyproject-nix,
      uv2nix,
      pyproject-build-systems,
      ...
    }:
    let
      inherit (nixpkgs) lib;

      supportedSystems = [
        "x86_64-linux"
      ];
      forAllSystems = lib.genAttrs supportedSystems;

      workspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ./.; };

      workspaceOverlay = workspace.mkPyprojectOverlay {
        sourcePreference = "wheel";
      };

      buildOverrides =
        system: final: prev:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          withSetuptools =
            package:
            package.overrideAttrs (old: {
              nativeBuildInputs =
                (old.nativeBuildInputs or [ ])
                ++ final.resolveBuildSystem {
                  setuptools = [ ];
                };
            });
          withBuildInputs =
            package: buildInputs:
            package.overrideAttrs (old: {
              buildInputs = (old.buildInputs or [ ]) ++ buildInputs;
            });
        in
        {
          antlr4-python3-runtime = withSetuptools prev.antlr4-python3-runtime;
          nvidia-cublas = withBuildInputs prev.nvidia-cublas [
            final.nvidia-cuda-nvrtc
          ];
          nvidia-cudnn-cu13 = withBuildInputs prev.nvidia-cudnn-cu13 [
            final.nvidia-cublas
          ];
          nvidia-cufft = withBuildInputs prev.nvidia-cufft [
            final.nvidia-nvjitlink
          ];
          nvidia-cufile = withBuildInputs prev.nvidia-cufile [
            pkgs.rdma-core
          ];
          nvidia-cusolver = withBuildInputs prev.nvidia-cusolver [
            final.nvidia-cublas
            final.nvidia-cusparse
            final.nvidia-nvjitlink
          ];
          nvidia-cusparse = withBuildInputs prev.nvidia-cusparse [
            final.nvidia-nvjitlink
          ];
          pylatexenc = withSetuptools prev.pylatexenc;
        };

      mkPythonSet =
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          python = pkgs.python313;
        in
        (pkgs.callPackage pyproject-nix.build.packages {
          inherit python;
        }).overrideScope
          (
            lib.composeManyExtensions [
              pyproject-build-systems.overlays.wheel
              workspaceOverlay
              (buildOverrides system)
            ]
          );

      mkHephPackage =
        system:
        let
          pythonSet = mkPythonSet system;
        in
        pythonSet.mkVirtualEnv "heph-env" workspace.deps.default;
    in
    {
      packages = forAllSystems (
        system:
        let
          heph = mkHephPackage system;
        in
        {
          inherit heph;
          default = heph;
        }
      );

      apps = forAllSystems (system: {
        heph = {
          type = "app";
          program = "${self.packages.${system}.heph}/bin/heph";
          meta.description = "Run the Heph CLI";
        };
        default = self.apps.${system}.heph;
      });

      overlays.default =
        final: prev:
        let
          system = prev.stdenv.hostPlatform.system;
        in
        lib.optionalAttrs (builtins.hasAttr system self.packages) {
          hephpkgs = self.packages.${system};
          heph = self.packages.${system}.heph;
        };

      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default =
            pkgs.runCommand "heph-version-smoke"
              {
                nativeBuildInputs = [
                  self.packages.${system}.heph
                ];
              }
              ''
                heph --version | grep -F 'heph 0.0.58'
                touch "$out"
              '';
        }
      );

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt);
    };
}
