{ config, lib, pkgs, ... }:
let
  home = config.home.homeDirectory;
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
  isLinux = pkgs.stdenv.hostPlatform.isLinux;

  # ── 运行时:Nix 为准(脱钩 Homebrew)──
  # agentmemory 用 Nix 的 node 跑,并装进 home-manager 自有的 npm 前缀 ~/.npm-global,
  # 这样守护进程不再依赖 /opt/homebrew 的 node/npm,跨设备可复现、版本可锁。
  node = pkgs.nodejs_22;
  npmPrefix = "${home}/.npm-global";
  amVersion = "0.9.27"; # ← 锁版本;要升级就改这里再 hms
  amDir = "${npmPrefix}/lib/node_modules/@agentmemory/agentmemory";
  amEntry = "${amDir}/dist/cli.mjs"; # daemon 入口(node 跑它)
  amBin = "${npmPrefix}/bin/agentmemory"; # CLI(connect 等用)

  # headroom 走 uv tool(独立 Python venv,与 node 无关),同样锁版本。
  hrVersion = "0.26.0";
  hrBin = "${home}/.local/bin/headroom";
  hrSpec = "headroom-ai[proxy,ml,pytorch-mps]==${hrVersion}";

  # 存在性保护:目标文件(二进制/入口)还没装好时(新机首次 hms,npm/uv 安装尚未完成),
  # 不让 launchd 每 ThrottleInterval 就 crash-loop —— 轮询等待最多 ~5 分钟,
  # 文件一出现立刻 exec;超时才 exit 1 交给 launchd 重试。
  guardedExec = waitFor: cmd:
    [
      "/bin/sh"
      "-c"
      "for _ in $(seq 1 60); do [ -e \"${waitFor}\" ] && exec ${cmd}; sleep 5; done; echo \"[launchd] ${waitFor} missing after 5min\" >&2; exit 1"
    ];
in
{
  # ════════════════ macOS:launchd 两个常驻 daemon ════════════════
  #   agentmemory : Claude Code ↔ Codex 共享记忆(REST :3111)—— Nix node 跑
  #   headroom    : 上下文压缩 proxy(:8787)—— uv 装的 Python 工具
  launchd.agents = lib.optionalAttrs isDarwin {
    "com.agentmemory.daemon" = {
      enable = true;
      config = {
        ProgramArguments = guardedExec amEntry ''"${node}/bin/node" "${amEntry}"'';
        EnvironmentVariables = {
          PATH = "${node}/bin:/usr/bin:/bin:/usr/sbin:/sbin"; # 只给 Nix node,不再含 /opt/homebrew
          HOME = home;
        };
        WorkingDirectory = home; # 记忆库以相对路径 ./data 解析到 ~/data
        RunAtLoad = true;
        KeepAlive = true;
        ThrottleInterval = 10;
        StandardOutPath = "${home}/.agentmemory/daemon.log";
        StandardErrorPath = "${home}/.agentmemory/daemon.err.log";
      };
    };
    "com.headroom.proxy" = {
      enable = true;
      config = {
        ProgramArguments = guardedExec hrBin ''"${hrBin}" proxy --port 8787'';
        EnvironmentVariables = {
          PATH = "${home}/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin";
          HOME = home;
          HEADROOM_TELEMETRY = "off"; # 关匿名遥测
        };
        WorkingDirectory = home;
        RunAtLoad = true;
        KeepAlive = true;
        ThrottleInterval = 10;
        StandardOutPath = "${home}/.headroom/logs/proxy.daemon.log";
        StandardErrorPath = "${home}/.headroom/logs/proxy.daemon.err.log";
      };
    };
  };

  # ════════════════ Linux:systemd user services(同 entrypoint)════════════════
  # 没有 launchd 的 guarded 轮询;靠 Restart=always 在二进制就绪前不断重试。
  systemd.user.services = lib.optionalAttrs isLinux {
    agentmemory = {
      Unit = {
        Description = "agentmemory cross-agent memory daemon (:3111)";
        After = [ "network.target" ];
      };
      Service = {
        ExecStart = "${node}/bin/node ${amEntry}";
        WorkingDirectory = home;
        Restart = "always";
        RestartSec = 10;
      };
      Install.WantedBy = [ "default.target" ];
    };
    headroom = {
      Unit.Description = "headroom context-compression proxy (:8787)";
      Service = {
        ExecStart = "${hrBin} proxy --port 8787";
        WorkingDirectory = home;
        Environment = [ "HEADROOM_TELEMETRY=off" ];
        Restart = "always";
        RestartSec = 10;
      };
      Install.WantedBy = [ "default.target" ];
    };
  };

  # ════════════════ 幂等安装二进制 + 注册 MCP(macOS/Linux 都跑)════════════════
  # 缺工具时各步 guard 自动 no-op;版本不符才装,所以老机器上重复 hms 基本是 no-op。
  home.activation = {
    harnessServiceDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      mkdir -p "$HOME/.headroom/logs" "$HOME/.agentmemory"
    '';

    # agentmemory:用 Nix npm 装进 ~/.npm-global(脱钩 Homebrew),版本不符才装。
    installAgentmemory = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      have="$(${node}/bin/node -e 'try{process.stdout.write(require("${amDir}/package.json").version)}catch(e){process.stdout.write("none")}' 2>/dev/null || echo none)"
      if [ "$have" != "${amVersion}" ]; then
        echo "[activation] installing @agentmemory/agentmemory@${amVersion} via Nix npm -> ${npmPrefix} (have=$have)..."
        # 关键:把 Nix node 放进 PATH —— 依赖的 postinstall 脚本会调用裸 `node`(否则 code 127)。
        PATH="${node}/bin:$PATH" ${node}/bin/npm install -g --prefix "${npmPrefix}" "@agentmemory/agentmemory@${amVersion}" || true
      fi
    '';

    # headroom:uv tool 装(锁版本),版本不符才装(--force 覆盖旧版)。
    installHeadroom = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      have="$("${hrBin}" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
      if [ "$have" != "${hrVersion}" ]; then
        echo "[activation] installing headroom==${hrVersion} via uv (one-time, pulls PyTorch; have=$have)..."
        ${pkgs.uv}/bin/uv tool install --force --python 3.13 "${hrSpec}" || true
      fi
    '';

    # 幂等注册整套 harness MCP 到 Claude(~/.claude.json)和 Codex(~/.codex/config.toml)。
    # 用各 agent 的原生 CLI(mcp add / connect),已存在则 grep 守卫跳过 → 老机器全 no-op。
    # 配置文件本身每机本地,这里用「注册动作」实现跟仓库同步。
    registerHarnessMcps = lib.hm.dag.entryAfter [ "installHeadroom" "installAgentmemory" ] ''
      C="$HOME/.local/bin/claude"; X="$HOME/.local/bin/codex"
      HR="${hrBin}"; AM="${amBin}"
      CJ="$HOME/.claude.json"; CT="$HOME/.codex/config.toml"
      # agentmemory(记忆)
      if [ -x "$AM" ]; then
        grep -q '"agentmemory"' "$CJ" 2>/dev/null || "$AM" connect claude-code >/dev/null 2>&1 || true
        grep -q 'mcp_servers.agentmemory' "$CT" 2>/dev/null || "$AM" connect codex >/dev/null 2>&1 || true
      fi
      # headroom MCP(CCR 取回);codex 的 headroom MCP 由 shell.nix 的 codex() 自愈分支注入
      [ -x "$HR" ] && { grep -q '"headroom"' "$CJ" 2>/dev/null || "$HR" mcp install --agent claude --proxy-url http://127.0.0.1:8787 >/dev/null 2>&1 || true; }
      # context7(最新库文档)+ kubernetes(只读,EKS 排障)
      if [ -x "$C" ]; then
        grep -q '"context7"'   "$CJ" 2>/dev/null || "$C" mcp add -s user context7   -- npx -y @upstash/context7-mcp >/dev/null 2>&1 || true
        grep -q '"kubernetes"' "$CJ" 2>/dev/null || "$C" mcp add -s user kubernetes -- npx -y kubernetes-mcp-server@latest --read-only >/dev/null 2>&1 || true
      fi
      if [ -x "$X" ]; then
        grep -q 'mcp_servers.context7'   "$CT" 2>/dev/null || "$X" mcp add context7   -- npx -y @upstash/context7-mcp >/dev/null 2>&1 || true
        grep -q 'mcp_servers.kubernetes' "$CT" 2>/dev/null || "$X" mcp add kubernetes -- npx -y kubernetes-mcp-server@latest --read-only >/dev/null 2>&1 || true
      fi
    '';
  };
}
