{
  description = "Personal multi-device home-manager config";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, home-manager, ... }:
    let
      mkHome = { system, username, homeDirectory }:
        home-manager.lib.homeManagerConfiguration {
          pkgs = import nixpkgs { inherit system; config.allowUnfree = true; };
          modules = [
            ./home.nix
            { home.username = username; home.homeDirectory = homeDirectory; }
          ];
        };
    in {
      homeConfigurations = {
        # 通用入口:任何机器都用它,自动适配当前 用户/家目录/平台。
        # 需要 --impure(下面三个 builtins 会读取当前环境)。
        "generic" = mkHome {
          system        = builtins.currentSystem;
          username      = builtins.getEnv "USER";
          homeDirectory = builtins.getEnv "HOME";
        };

        # 可选:只有当某台机器需要"不一样的配置"时,才单独登记。
        # "yuu@workmac" = mkHome { system = "aarch64-darwin"; username = "yuu"; homeDirectory = "/Users/yuu"; };
      };
    };
}
