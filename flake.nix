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
          withBuildInputsAndSearchPaths =
            package: buildInputs: searchPaths:
            package.overrideAttrs (old: {
              buildInputs = (old.buildInputs or [ ]) ++ buildInputs;
              preFixup =
                (old.preFixup or "")
                + lib.concatMapStrings (searchPath: ''
                  if [ -d "${searchPath}" ]; then
                    addAutoPatchelfSearchPath "${searchPath}"
                  fi
                '') searchPaths;
            });
          cudaLibPath = package: "${package}/${pkgs.python313.sitePackages}/nvidia/cu13/lib";
          torchLibPath = package: "${package}/${pkgs.python313.sitePackages}/torch/lib";
          withCudaBuildInputs =
            package: buildInputs:
            withBuildInputsAndSearchPaths package buildInputs (map cudaLibPath buildInputs);
          torchCudaPackages = [
            final.nvidia-cublas
            final.nvidia-cuda-cupti
            final.nvidia-cuda-nvrtc
            final.nvidia-cuda-runtime
            final.nvidia-cudnn-cu13
            final.nvidia-cufft
            final.nvidia-cufile
            final.nvidia-curand
            final.nvidia-cusolver
            final.nvidia-cusparse
            final.nvidia-cusparselt-cu13
            final.nvidia-nccl-cu13
            final.nvidia-nvjitlink
            final.nvidia-nvshmem-cu13
            final.nvidia-nvtx
          ];
        in
        {
          antlr4-python3-runtime = withSetuptools prev.antlr4-python3-runtime;
          nvidia-cublas = withCudaBuildInputs prev.nvidia-cublas [
            final.nvidia-cuda-nvrtc
          ];
          nvidia-cudnn-cu13 = withCudaBuildInputs prev.nvidia-cudnn-cu13 [
            final.nvidia-cublas
          ];
          nvidia-cufft = withCudaBuildInputs prev.nvidia-cufft [
            final.nvidia-nvjitlink
          ];
          nvidia-cufile = withBuildInputs prev.nvidia-cufile [
            pkgs.rdma-core
          ];
          nvidia-cusolver = withCudaBuildInputs prev.nvidia-cusolver [
            final.nvidia-cublas
            final.nvidia-cusparse
            final.nvidia-nvjitlink
          ];
          nvidia-cusparse = withCudaBuildInputs prev.nvidia-cusparse [
            final.nvidia-nvjitlink
          ];
          nvidia-nvshmem-cu13 = withBuildInputs prev.nvidia-nvshmem-cu13 [
            pkgs.libfabric
            pkgs.openmpi
            pkgs.pmix
            pkgs.rdma-core
            pkgs.ucx
          ];
          pylatexenc = withSetuptools prev.pylatexenc;
          torch = withCudaBuildInputs prev.torch torchCudaPackages;
          torchvision =
            withBuildInputsAndSearchPaths prev.torchvision
              [
                final.torch
                final.nvidia-cuda-runtime
              ]
              [
                (torchLibPath final.torch)
                (cudaLibPath final.nvidia-cuda-runtime)
              ];
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
