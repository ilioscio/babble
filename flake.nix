{
  description = "babble - A Markov chain text generator written in Zig";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    zig-overlay = {
      url = "github:mitchellh/zig-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, zig-overlay }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

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
            export ZIG_GLOBAL_CACHE_DIR=$(mktemp -d)
            export ZIG_LOCAL_CACHE_DIR=$(mktemp -d)
            # Build for baseline x86_64 (no CPU-specific instructions)
            zig build --release=safe -Doptimize=ReleaseSafe -Dcpu=baseline --prefix $out

            # Bundle the default corpus
            mkdir -p $out/share/babble
            cp corpus.txt $out/share/babble/

            runHook postBuild
          '';

          meta = with pkgs.lib; {
            description = "A Markov chain text generator written in Zig";
            license = licenses.mit;
            platforms = platforms.linux;
            mainProgram = "babble";
          };
        };
    in
    {
      overlays.default = final: prev:
        let zig = zig-overlay.packages.${prev.system}."0.15.2";
        in { babble = mkBabble final zig; };

      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; overlays = [ zig-overlay.overlays.default ]; };
          zig = pkgs.zigpkgs."0.15.2";
        in {
          default = mkBabble pkgs zig;
          babble = mkBabble pkgs zig;
        }
      );

      # nix run github:ilioscio/babble -- 500
      apps = forAllSystems (system:
        let pkg = self.packages.${system}.default;
        in {
          default = {
            type = "app";
            program = toString (nixpkgs.legacyPackages.${system}.writeShellScript "babble-run" ''
              exec ${pkg}/bin/babble "''${1:-500}" "''${2:-${pkg}/share/babble/corpus.txt}"
            '');
          };
        }
      );

      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; overlays = [ zig-overlay.overlays.default ]; };
          zig = pkgs.zigpkgs."0.15.2";
        in {
          default = pkgs.mkShell {
            buildInputs = [ zig ];
            shellHook = ''
              echo "babble dev environment - Zig $(zig version)"
            '';
          };
        }
      );
    };
}
