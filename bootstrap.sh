#!/bin/sh
set -eu
REPO_FLAKE="github:<GH_USER>/nix-config"
REPO_HTTPS="https://github.com/<GH_USER>/nix-config.git"

# 1) 没有 nix 就装 Determinate Nix(非交互),并在当前进程内可用
if ! command -v nix >/dev/null 2>&1; then
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install --no-confirm
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi

# 2) 应用配置:generic 自动探测当前 用户/家目录/平台。
#    -b backup:已存在的 ~/.zshrc 等会被备份为 *.backup,而不是报错中断。
nix run home-manager/master -- switch -b backup --flake "${REPO_FLAKE}#generic" --impure

# 3) 拉一份本地工作副本,方便以后编辑/push(用 nix 提供的 git,无需预装)
[ -d "$HOME/nix-config" ] || nix run nixpkgs#git -- clone "${REPO_HTTPS}" "$HOME/nix-config"

echo "✅ 完成。打开新终端即可用。以后改配置:编辑 ~/nix-config 后运行  home-manager switch --flake ~/nix-config#generic --impure"
