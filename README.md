<p align="left">
  <img alt="Heph" src="assets/logo-auto.svg" width="280">
</p>

Nix flake packaging for [Heph](https://github.com/gildrb/heph). The Python package and release
workflow remain in the upstream Heph repo and on PyPI.

### Usage

Run the packaged CLI:

```sh
nix run github:gildrb/heph-overlay -- --version
```

Install it into a profile:

```sh
nix profile install github:gildrb/heph-overlay
```

Use it from another flake:

```nix
{
  inputs.heph-overlay.url = "github:gildrb/heph-overlay";

  outputs = { nixpkgs, heph-overlay, ... }:
  let
    system = "x86_64-linux";
    pkgs = import nixpkgs { inherit system; };
  in
  {
    devShells.${system}.default = pkgs.mkShell {
      packages = [
        heph-overlay.packages.${system}.default
      ];
    };
  };
}
```

Use the overlay:

```nix
{
  inputs.heph-overlay.url = "github:gildrb/heph-overlay";

  outputs = { nixpkgs, heph-overlay, ... }:
  let
    system = "x86_64-linux";
    pkgs = import nixpkgs {
      inherit system;
      overlays = [ heph-overlay.overlays.default ];
    };
  in
  {
    packages.${system}.default = pkgs.heph;
  };
}
```

### Outputs

- `packages.x86_64-linux.default` and `packages.x86_64-linux.heph`
- `apps.x86_64-linux.default` and `apps.x86_64-linux.heph`
- `overlays.default`, which exposes `pkgs.heph` and `pkgs.hephpkgs`
- `checks.x86_64-linux.default`, a `heph --version` smoke check

### Updating

Update to the latest published Heph package:

```sh
uv run python update
```

That updates the pinned `heph` dependency in `pyproject.toml` and refreshes
`uv.lock`. Commit the resulting lockfile and verify with:

```sh
nix flake check
nix run .# -- --version
```
