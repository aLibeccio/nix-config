{ lib, pkgs, ... }:
let
  # 去掉 fzf-tab 的 C 加速模块:macOS 上加载不了、每次开 shell 都弹重建提示,
  # 改用纯 zsh 回退。
  fzfTab = pkgs.zsh-fzf-tab.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      rm -rf "$out/share/fzf-tab/modules"
    '';
  });

  # carapace 读取自定义 spec 的目录跟平台走:
  #   macOS → ~/Library/Application Support/carapace/specs/
  #   Linux → ~/.config/carapace/specs/
  # (carapace 用 Go 的 os.UserConfigDir,macOS 上不是 ~/.config)
  carapaceSpecTarget =
    if pkgs.stdenv.hostPlatform.isDarwin then
      "Library/Application Support/carapace/specs/claude.yaml"
    else
      ".config/carapace/specs/claude.yaml";
in
{
  # ── 让 home-manager 接管 zsh,并自动写好各工具的 shell 集成 ──
  programs.zsh = {
    enable = true;

    # 补全 / 交互增强
    enableCompletion = true; # zsh 补全系统(默认开,显式写更清楚)
    autosuggestion.enable = true; # 灰字行内建议(来自历史),按 → 接受
    syntaxHighlighting.enable = true; # 命令语法高亮(错命令标红)

    # 保留你原来的 oh-my-zsh(git 插件;主题留空,提示符交给 starship)
    oh-my-zsh = {
      enable = true;
      plugins = [ "git" ];
      theme = "";
    };

    shellAliases = {
      hms = "home-manager switch --flake ~/nixstation#generic --impure";
    };

    # 原 ~/.zprofile 的内容迁移到这里(登录 shell)
    profileExtra = ''
      # Homebrew (Apple Silicon) — 仅在存在时加载,Linux 上自动跳过
      [ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
      # npm 全局装到可写前缀(Nix node 默认 prefix 是只读 store);其 bin 上 PATH。
      export NPM_CONFIG_PREFIX="$HOME/.npm-global"
      export PATH="$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:$HOME/.npm-global/bin:$HOME/.local/bin:$PATH"
    '';

    # 原 ~/.zshrc 自定义内容 + 把 Ctrl-R 固定给 atuin(最后执行,盖过 fzf)
    initContent = lib.mkMerge [
      ''
      export NPM_CONFIG_PREFIX="$HOME/.npm-global"
      export PATH="$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:$HOME/.npm-global/bin:$HOME/.local/bin:$PATH"

      # Claude Code:默认把推理 effort 拉到 max(只能用环境变量,写不进 settings.json:
      # effortLevel 封顶 xhigh,max 是 session-only)。
      export CLAUDE_CODE_EFFORT_LEVEL="max"

      # Drop stale terminfo dirs inherited from parent shells.
      if [[ -n "''${TERMINFO_DIRS:-}" ]]; then
        _terminfo_dirs=("''${(@s/:/)TERMINFO_DIRS}")
        _terminfo_existing=()
        for _terminfo_dir in "''${_terminfo_dirs[@]}"; do
          [[ -z "$_terminfo_dir" || -d "$_terminfo_dir" ]] && _terminfo_existing+=("$_terminfo_dir")
        done
        if (( ''${#_terminfo_existing[@]} )); then
          export TERMINFO_DIRS="''${(j/:/)_terminfo_existing}"
        else
          unset TERMINFO_DIRS
        fi
        unset _terminfo_dir _terminfo_dirs _terminfo_existing
      fi

      # ── fzf-tab:把 Tab 补全菜单换成 fzf 模糊选择 ──
        # 须在 compinit 之后、syntax-highlighting 之前加载(fzf-tab 的顺序要求)。
        source ${fzfTab}/share/fzf-tab/fzf-tab.plugin.zsh
        # 关掉 zsh 原生菜单,交给 fzf-tab(必须,否则会先弹原生菜单/抢不到补全)
        zstyle ':completion:*' menu no
        # oh-my-zsh 设了更具体的 ':completion:*:*:*:*:*' menu select,用同样的 pattern 覆盖掉
        zstyle ':completion:*:*:*:*:*' menu no
        # 分组描述格式,配合下面的 < > 在多组结果间切换
        zstyle ':completion:*:descriptions' format '[%d]'
        # 用文件颜色渲染候选(LS_COLORS 为空时无害)
        zstyle ':completion:*' list-colors ''${(s.:.)LS_COLORS}
        # 补全 cd 时用 eza 预览目录内容
        zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -1 --color=always --icons=always $realpath'
        # 多组结果时用 < / > 切换分组
        zstyle ':fzf-tab:*' switch-group '<' '>'
        # fzf 弹窗参数(60% 高度,底部弹出而非全屏)
        zstyle ':fzf-tab:*' fzf-flags --height=60%

        # ── codex(Codex CLI)补全 ──
        # 缓存到文件,避免每次开 shell 都跑 codex 生成补全;codex 更新后才重建。
        if (( $+commands[codex] )); then
          _codex_comp="''${XDG_CACHE_HOME:-$HOME/.cache}/zsh/codex-completion.zsh"
          if [[ ! -s $_codex_comp || $commands[codex] -nt $_codex_comp ]]; then
            mkdir -p "''${_codex_comp:h}"
            codex completion zsh >| "$_codex_comp" 2>/dev/null
          fi
          source "$_codex_comp"
          unset _codex_comp
        fi

        # ── headroom：让 claude / codex 透明走上下文压缩代理（省 token）──
        # 逃生:HEADROOM_OFF=1 claude ... → 走原生、不压缩。
        if (( $+commands[headroom] )); then
          export HEADROOM_TELEMETRY=off   # 关掉匿名遥测(与 launchd daemon 一致)
          # claude：纯环境变量直连常驻 proxy(:8787),省去每次 wrap 的开销。
          claude() {
            [ -n "$HEADROOM_OFF" ] && { command claude "$@"; return; }
            ANTHROPIC_BASE_URL=http://127.0.0.1:8787 command claude "$@"
          }
          # codex：必须用 config provider 路由,缺失时补注入一次,省去每次 wrap 的开销。
          codex() {
            if [ -n "$HEADROOM_OFF" ]; then command headroom unwrap codex >/dev/null 2>&1; command codex "$@"; return; fi
            grep -q 'model_provider = "headroom"' "$HOME/.codex/config.toml" 2>/dev/null \
              || command headroom wrap codex --no-proxy --no-serena --no-context-tool -- --version >/dev/null 2>&1
            command codex "$@"
          }
        fi
      ''
      (lib.mkAfter ''
        bindkey '^r' atuin-search
      '')
    ];
  };

  # ── 需要 shell 集成才生效的工具,改用 programs.* 声明 ──
  programs.fzf = {
    enable = true;
    enableZshIntegration = true; # Ctrl-T 找文件、Alt-C 进目录
  };

  programs.zoxide = {
    enable = true;
    enableZshIntegration = true; # z / zi 智能跳转
  };

  programs.atuin = {
    enable = true;
    enableZshIntegration = true; # Ctrl-R 搜索历史(可选登录后多设备同步)
  };

  programs.starship = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true; # 进入含 .envrc 的目录自动加载 Nix devShell
  };

  # ── carapace:给 1000+ 个 CLI 提供 子命令/参数/flag 的 Tab 补全 ──
  programs.carapace = {
    enable = true;
    enableZshIntegration = true;
  };

  # ── 给 carapace 补一个 claude(Claude Code)的 spec ──
  # claude 不在 carapace 内置库里、自身也没有 zsh 补全,所以手动加。
  # 加了之后 carapace 会把 claude 也纳入补全,fzf-tab 自动套上模糊菜单:
  #   claude --d<Tab> → --dangerously-skip-permissions / --debug ...
  #   claude --model <Tab> → opus/sonnet/fable;claude <Tab> → mcp/auth/... 子命令
  home.file.${carapaceSpecTarget}.source = ./assets/claude.carapace.yaml;
}
