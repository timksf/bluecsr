{
    description = "BlueCSR development and test environment";

    inputs = {
        nixpkgs.url = "github:NixOS/nixpkgs/25.11";
        flake-utils.url = "github:numtide/flake-utils";
    };

    outputs = { flake-utils, nixpkgs, ... }:
        flake-utils.lib.eachSystem ["x86_64-linux"] (system: let
            pkgs = import nixpkgs {
                inherit system;
            };
        in {
            devShells.default = pkgs.mkShell {
                packages = with pkgs; [
                    bluespec
                    gnumake
                    iverilog
                ];
            };
        });
}
