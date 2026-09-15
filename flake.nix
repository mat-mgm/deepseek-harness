{
  description = "DeepSeek Harness (dsh): devShell and packaged CLI";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forEachSystem = nixpkgs.lib.genAttrs systems;
      pkgsFor = system: import nixpkgs { inherit system; };
    in
    {
      packages = forEachSystem (system:
        let pkgs = pkgsFor system;
        in {
          dsh = pkgs.callPackage ./nix/dsh.nix { };
          default = self.packages.${system}.dsh;
        });

      devShells = forEachSystem (system:
        let pkgs = pkgsFor system;
        in {
          default = pkgs.mkShell {
            packages = with pkgs; [
              nodejs_22
              pnpm_11
              python3
              gnumake
              gcc
              git
            ];

            shellHook = ''
              export PATH="$PWD/node_modules/.bin:$PATH"
            '';
          };
        });
    };
}
