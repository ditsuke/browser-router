{
  description = "Minimal native macOS browser router";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      packageFor = system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in pkgs.callPackage ./nix/package.nix { };
    in {
      packages = forAllSystems (system: {
        default = self.packages.${system}.browser-router;
        browser-router = packageFor system;
      });

      apps = forAllSystems (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.browser-router}/bin/browser-router";
          meta.description = "Open Browser Router";
        };
      });

      checks = forAllSystems (system: {
        browser-router = self.packages.${system}.browser-router;
      });

      devShells = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          # SwiftPM's Nix build hook supplies this flag in derivations. Supply it
          # for interactive SwiftPM commands too, so SwiftUI macros also work here.
          swiftWithMacros = pkgs.writeShellScriptBin "swift" ''
            case "''${1-}" in
              build|test|run)
                subcommand="$1"
                shift
                exec ${pkgs.swift}/bin/swift "$subcommand" \
                  -Xswiftc -external-plugin-path \
                  -Xswiftc '${pkgs.open-apple-macros}/lib/swift/host/plugins#${pkgs.open-apple-macros}/libexec/swift/plugins/OpenAppleMacrosServer' \
                  "$@"
                ;;
              *) exec ${pkgs.swift}/bin/swift "$@" ;;
            esac
          '';
        in {
          default = pkgs.mkShell {
            inputsFrom = [ self.packages.${system}.browser-router ];
            packages = [ swiftWithMacros ];
          };
        });
    };
}
