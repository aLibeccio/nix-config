{ config, lib, pkgs, ... }:
let
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
  home = config.home.homeDirectory;
  # Brewfile 的落盘路径(固定、可预测),activation 步骤按这个绝对路径喂给 brew bundle。
  brewfileDest = ".config/homebrew/Brewfile";
in
# ── Homebrew 模块(仅 macOS)──
#   Homebrew 只管 GUI cask / 字体,运行时交给 Nix。Linux 是 no-op。
{
  # 把仓库里的 Brewfile 软链到 ~/.config/homebrew/Brewfile,作为 brew bundle 的唯一真相源。
  # 注:optionalAttrs 必须放在 value 里(home.file / home.activation 等顶层 key 固定),
  #     不能在顶层 mkMerge 里按 isDarwin 增删属性,否则「模块声明哪些属性」依赖 pkgs → 无限递归。
  home.file = lib.optionalAttrs isDarwin {
    ${brewfileDest}.source = ./Brewfile;
  };

  # 幂等应用 Brewfile:每次 hms 都跑,但已装即 no-op。
  home.activation = lib.optionalAttrs isDarwin {
    homebrewBundle = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      # activation 环境的 PATH 很精简,brew 通常不在里面;用绝对路径守卫,
      # brew 没装(例如 CI / 还没装 Homebrew 的新机)就静默跳过,绝不让 hms 失败。
      BREW=/opt/homebrew/bin/brew
      if [ -x "''${BREW}" ]; then
        # 注入 brew 的 shellenv(补 PATH/HOMEBREW_* 环境),再做 bundle。
        eval "$("''${BREW}" shellenv)"
        echo "[activation] brew bundle (cask/字体, --no-upgrade)..."
        # --no-upgrade:已装即 no-op,升级留给用户显式 `brew upgrade`。不加 --cleanup 避免误卸载。
        # 直接用 Nix store 路径,避开 activation 早于 linkGeneration 导致软链未就绪的时序问题。
        "''${BREW}" bundle --file=${./Brewfile} --no-upgrade || \
          echo "[activation] brew bundle 失败(忽略,不阻断 hms)"
      else
        echo "[activation] 未找到 ''${BREW},跳过 brew bundle(非 macOS 或未装 Homebrew)"
      fi
    '';
  };
}
