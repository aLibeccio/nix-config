{
  pkgs,
  lib,
  ...
}: {
  home.packages = with pkgs;
    [
      # Core Utilities
      curl
      xh # fast HTTP client (Rust httpie) for API testing/debug
      jq
      yq
      dasel # query/convert JSON/YAML/TOML/XML/CSV in one tool
      gron # flatten JSON into greppable path=value lines
      duckdb
      postgresql # psql client + server tools
      miller # mlr: CSV/TSV/JSON data swiss army knife
      shfmt
      eza
      bat
      ripgrep
      fd
      sd # intuitive find & replace (modern sed)
      dust
      tailspin
      hexyl # colored hex viewer
      doggo # modern dig: clean DNS lookups
      trippy # modern traceroute/mtr (network path diagnosis)
      bandwhich # per-process network bandwidth monitor
      glow # render markdown in the terminal
      jless # interactive TUI viewer for JSON/YAML

      # Nix & System Tools
      nh # ergonomic nix/home-manager workflow helper
      nix-output-monitor # nom: colorful nix build progress
      nixd # Nix language server (LSP for helix/editors)
      nixfmt # official Nix formatter (RFC style is now the default)
      statix # Nix linter / anti-pattern fixer
      deadnix # find unused Nix code
      nix-tree # explore a derivation's dependency closure
      btop
      procs # modern ps: tree view, search, ports
      fastfetch
      hyperfine # command-line benchmarking
      oha # modern benchmark tool

      # Code stats & utilities (language-agnostic)
      tokei # count lines of code
      grex # generate regex

      # Development - Tools & Version Control
      git-lfs
      sops
      age
      watchexec
      usage # CLI docs generator
      shellcheck
      yamlfmt
      pre-commit
      # gh 移到 programs.nix(programs.gh,含 git 凭据助手)
      lazygit # fast terminal UI for git
      delta # syntax-highlighted git diffs (pairs with bat)
      difftastic # structural (syntax-aware) diff: difft
      gitleaks # scan repos/commits for leaked secrets
      just # command runner (modern make for task recipes)
      mise # polyglot runtime & tool-version manager (asdf successor)
      uv # fast Python pkg/tool manager (used to install headroom-ai for the agent harness)

      # 语言运行时 —— Nix 为准(取代 Homebrew 的 node/go/python;见 modules/homebrew)。
      # agent harness 的 agentmemory daemon 直接用 ${pkgs.nodejs_22},这里再放一份给交互/npx 用。
      nodejs_22 # Node.js LTS(+ npm/npx)
      go # Go 工具链
      golangci-lint # Go linter(原 brew formula)
      python3 # Python 解释器(headroom 自带 uv 管的 3.13;这个给通用交互用)

      # Infrastructure & Cloud
      k9s
      kubectl
      kubectx # switch kubectl context/namespace (kubectx + kubens)
      kubernetes-helm # Helm: the Kubernetes package manager
      minikube # local Kubernetes
      stern
      dive # inspect & shrink container image layers
      lazydocker # terminal UI for docker/containers
      awscli2
      rclone

      # File Management & Media
      yt-dlp
      ffmpeg
      unar # archive extractor
      ouch # painless compress/decompress for many formats
      typst # document compiler

      # Shell & Navigation
      # 注:fzf / zoxide / atuin / starship / direnv 移到 shell.nix,
      #     用 programs.* 配置(自动带上 zsh 集成),所以不在这里列。
      navi # interactive cheat sheet
      rtk # CLI proxy that cuts LLM token use on common dev commands
      zellij # terminal multiplexer & workspace (modern tmux)
      yazi # blazing-fast TUI file manager
      tealdeer # fast tldr client (simplified man pages)

      # Editors
      helix
    ]
    ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [
      # Container toolkit (Linux only — rootless, daemonless)
      podman
      buildah # build OCI images without a daemon
      skopeo # inspect/copy container images
      nerd-fonts.meslo-lg # macOS 用 Homebrew cask 装,Linux 这里用 Nix
    ]
    ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
      # Container alternative
      colima # lightweight VM to run OCI containers on macOS
      docker-client # CLI to talk to the colima VM
    ];
}
