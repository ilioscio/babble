{
  description = "babble - A Markov chain text generator written in Zig";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Zig overlay for specific Zig versions
    zig-overlay = {
      url = "github:mitchellh/zig-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, zig-overlay }:
    let
      # Systems we support
      supportedSystems = [ "x86_64-linux" "aarch64-linux" ];

      # Helper to generate per-system outputs
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      # Package derivation (reusable across systems)
      mkBabble = pkgs: zig:
        pkgs.stdenv.mkDerivation {
          pname = "babble";
          version = "0.1.0";

          src = ./.;

          nativeBuildInputs = [ zig ];

          dontConfigure = true;
          dontInstall = true;

          buildPhase = ''
            runHook preBuild

            # Set up writable cache directories for Zig
            export ZIG_GLOBAL_CACHE_DIR=$(mktemp -d)
            export ZIG_LOCAL_CACHE_DIR=$(mktemp -d)

            # Build with Zig
            zig build \
              --release=safe \
              -Doptimize=ReleaseSafe \
              --prefix $out

            runHook postBuild
          '';

          meta = with pkgs.lib; {
            description = "A Markov chain text generator written in Zig";
            longDescription = ''
              babble generates readable nonsense using a Markov chain algorithm.
              Feed it text input, and it will produce randomized output that
              captures the flavor of the original while adding its own whimsical touch.
            '';
            license = licenses.mit;
            platforms = platforms.linux;
            maintainers = [];
            mainProgram = "babble";
          };
        };
    in
    {
      # ============================================================
      # OVERLAY - For users who want to add babble to their pkgs
      # ============================================================
      # Usage in user's flake.nix:
      #   nixpkgs.overlays = [ babble.overlays.default ];
      #   environment.systemPackages = [ pkgs.babble ];
      overlays.default = final: prev:
        let
          zig = zig-overlay.packages.${prev.system}."0.15.2";
        in {
          babble = mkBabble final zig;
        };

      # ============================================================
      # PACKAGES - Direct package access per system
      # ============================================================
      # Usage: babble.packages.x86_64-linux.default
      # Or: nix build github:USERNAME/babble
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ zig-overlay.overlays.default ];
          };
          zig = pkgs.zigpkgs."0.15.2";
        in {
          default = mkBabble pkgs zig;
          babble = mkBabble pkgs zig;
        }
      );

      # ============================================================
      # APPS - For `nix run github:USERNAME/babble`
      # ============================================================
      apps = forAllSystems (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/babble";
        };
      });

      # ============================================================
      # DEV SHELLS - For contributors/developers
      # ============================================================
      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ zig-overlay.overlays.default ];
          };
          zig = pkgs.zigpkgs."0.15.2";
        in {
          default = pkgs.mkShell {
            buildInputs = [
              zig
            ];

            shellHook = ''
              echo "babble development environment"
              echo ""
              echo "Available commands:"
              echo "  zig build        - Build the project"
              echo "  zig build run    - Run babble"
              echo "  zig build test   - Run tests"
              echo ""
              echo "Zig version: $(zig version)"
            '';
          };
        }
      );
    };
}

