{
  description = "My Python App with Nix and uv2nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    # Core pyproject-nix ecosystem tools
    pyproject-nix.url = "github:pyproject-nix/pyproject.nix";
    uv2nix.url = "github:pyproject-nix/uv2nix";
    pyproject-build-systems.url = "github:pyproject-nix/build-system-pkgs";

    # Ensure consistent dependencies between these tools
    pyproject-nix.inputs.nixpkgs.follows = "nixpkgs";
    uv2nix.inputs.nixpkgs.follows = "nixpkgs";
    pyproject-build-systems.inputs.nixpkgs.follows = "nixpkgs";
    uv2nix.inputs.pyproject-nix.follows = "pyproject-nix";
    pyproject-build-systems.inputs.pyproject-nix.follows = "pyproject-nix";
  };

  outputs = { self, nixpkgs, flake-utils, uv2nix, pyproject-nix, pyproject-build-systems, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        python = pkgs.python312; # Your desired Python version

        # 1. Load Project Workspace (parses pyproject.toml, uv.lock)
        workspace = uv2nix.lib.workspace.loadWorkspace {
          workspaceRoot = ./.; # Root of your flake/project
        };

        # 2. Generate Nix Overlay from uv.lock (via workspace)
        uvLockedOverlay = workspace.mkPyprojectOverlay {
          sourcePreference = "wheel"; # Or "sdist"
        };

        # 3. Placeholder for Your Custom Package Overrides
        myCustomOverrides = final: prev: {
          /* e.g., some-package = prev.some-package.overridePythonAttrs (...); */

          pytorch-triton-rocm =
            prev."pytorch-triton-rocm".overrideAttrs (oldAttrs: rec {
            buildInputs =
              (oldAttrs.buildInputs or []) ++ [
                pkgs.zlib
                pkgs.zstd
                pkgs.xz
                pkgs.bzip2
              ];
          });
          torch = prev.torch.overrideAttrs (oldAttrs: rec {
            buildInputs =
              (oldAttrs.buildInputs or []) ++ [
                pkgs.rocmPackages.rocblas
                pkgs.zlib
                pkgs.zstd
                pkgs.xz
                pkgs.bzip2
              ];
          });
          docopt = pkgs.python312Packages.docopt;

        };

        # 4. Construct the Final Python Package Set
        pythonSet =
          (pkgs.callPackage pyproject-nix.build.packages { inherit python; })
          .overrideScope (nixpkgs.lib.composeManyExtensions [
            pyproject-build-systems.overlays.default # For build tools
            uvLockedOverlay                          # Your locked dependencies
            myCustomOverrides                        # Your fixes
          ]);

        # --- This is where your project's metadata is accessed ---
        projectNameInToml = "kokoro-fastapi"; # MUST match [project.name] in pyproject.toml!
        thisProjectAsNixPkg = pythonSet.${projectNameInToml};
        # ---

        # 5. Create the Python Runtime Environment
        appPythonEnv = pythonSet.mkVirtualEnv 
          (thisProjectAsNixPkg.pname + "-env") 
          (workspace.deps.byName or {});  # fallback to empty set if missing

      in
      {
        # Development Shell
        devShells.default = pkgs.mkShell {
          packages = [ appPythonEnv pkgs.ruff pkgs.uv ];
          shellHook = '' /* Your custom shell hooks */ '';
          LD_LIBRARY_PATH = "${pkgs.libsndfile.out}/lib";
        };

        # Nix Package for Your Application
        packages.default = pkgs.stdenv.mkDerivation {
          pname = thisProjectAsNixPkg.pname;
          version = thisProjectAsNixPkg.version;
          src = ./.; # Source of your main script

          nativeBuildInputs = [ pkgs.makeWrapper ];
          buildInputs = [ 
            appPythonEnv
            pkgs.libsndfile
          ]; # Runtime Python environment

          installPhase = ''
            mkdir -p $out/bin
            cp ${./start-gpu.sh} $out/bin/kokoro-fastapi
            chmod +x $out/bin/kokoro-fastapi

            # copy only what you actually import at runtime
            mkdir -p $out/app
            cp -r api $out/app/api
            # (copy other needed dirs like web/, docker/scripts/ if used at runtime)
            cp -r docker $out/app/docker


            wrapProgram $out/bin/kokoro-fastapi \
              --prefix PATH : ${appPythonEnv}/bin \
              --prefix LD_LIBRARY_PATH : ${appPythonEnv}/lib/python3.12/site-packages/torch/lib \
              --suffix LD_LIBRARY_PATH : ${pkgs.libsndfile.out}/lib \
              --set APP_ROOT "$out/app" \
              --set-default PYTHONPATH "$out/app:$out/app/api"


          '';
        };
        packages.${thisProjectAsNixPkg.pname} = self.packages.${system}.default;

        # App for `nix run`
        apps.default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/${thisProjectAsNixPkg.pname}";
        };
        apps.${thisProjectAsNixPkg.pname} = self.apps.${system}.default;
      }
    );
}
