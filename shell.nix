{ ... }:
{
  # ── 让 home-manager 接管 zsh,并自动写好各工具的 shell 集成 ──
  programs.zsh = {
    enable = true;

    # 保留你原来的 oh-my-zsh(git 插件;主题留空,提示符交给 starship)
    oh-my-zsh = {
      enable = true;
      plugins = [ "git" ];
      theme = "";
    };

    # 你 .zshrc 末尾的自定义内容迁移到这里
    initContent = ''
      export PATH="$HOME/.local/bin:$PATH"
    '';
  };

  # ── 需要 shell 集成才生效的工具,改用 programs.* 声明 ──
  programs.fzf = {
    enable = true;
    enableZshIntegration = true; # Ctrl-T 找文件、Alt-C 进目录
  };

  programs.zoxide = {
    enable = true;
    enableZshIntegration = true; # z / zi 智能跳转
    # options = [ "--cmd cd" ];  # 取消注释:让 cd 直接用 zoxide
  };

  programs.atuin = {
    enable = true;
    enableZshIntegration = true; # Ctrl-R 搜索历史(可选登录后多设备同步)
  };

  programs.starship = {
    enable = true;
    enableZshIntegration = true; # 提示符(替代你手写的 starship init)
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true; # 进入含 .envrc 的目录自动加载 Nix devShell
  };
}
