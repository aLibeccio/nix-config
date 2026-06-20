{ config, lib, pkgs, ... }:
# 周期性用 rclone bisync 把 agentmemory 的记忆库 ~/data 跨设备同步,
# 让一台机器上 remember 的事实能在另一台 recall 命中。
#
# 为什么数据走单独通道、不进 git 仓库:~/data 是数据(可能敏感的二进制 KV/事件流)
# 而非配置,git 对二进制库支持差;配置进仓库随 home-manager 复现,数据只走这条通道。
#
# 关键 rationale:
#  - 首次 --resync 以本地为基准建基线(不是双向合并,故只跑一次,用标记文件区分)。
#  - 没配 remote 的机器整体 no-op,不报错。
#  - 常规双向 bisync,冲突按 newer(修改时间较新者为准)取舍。
#
# secret:rclone 凭据(rclone.conf)机器本地、不进仓库,故不泄漏到 public GitHub。
let
  home = config.home.homeDirectory;
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
  isLinux = pkgs.stdenv.hostPlatform.isLinux;

  # 同步约定 —— 改这里即可调整源/远端/周期。
  remote = "agentmemory"; # `rclone config` 里要建的 remote 名(脚本会拼成 agentmemory:)
  remotePath = "agentmemory:agentmemory-data"; # 云端落地路径(remote 下的目录)
  localDir = "${home}/data"; # 本地共享记忆库(agentmemory 的数据目录)
  stateDir = "${home}/.agentmemory"; # 标记文件 + 日志放这(与 agent-harness 同目录)
  initMarker = "${stateDir}/.bisync-initialized"; # 区分「首次 --resync」与「常规 bisync」
  logFile = "${stateDir}/rclone-bisync.log"; # rclone 日志

  # 同步脚本(纯 store-path 引用二进制,不依赖 launchd/systemd 那套精简 PATH)。
  #   - 守卫:listremotes 里没有 `agentmemory:` 就直接 exit 0 → 没配 remote 的机器 no-op。
  #   - 幂等:首次(无 initMarker)走 --resync 建基线,成功后 touch 标记;之后走常规 bisync。
  #   - 日志:全部 append 到 ~/.agentmemory/rclone-bisync.log。
  rclone = "${pkgs.rclone}/bin/rclone";
  coreutils = pkgs.coreutils;
  syncScript = pkgs.writeShellScript "agentmemory-bisync" ''
    set -u
    RCLONE=${rclone}
    PATH=${coreutils}/bin:$PATH   # date/mkdir/touch/test 等,确保最小环境下也能跑
    export PATH

    LOG=${logFile}
    mkdir -p ${stateDir} ${localDir}

    log() { echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')] $*" >> "$LOG"; }

    # ── 守卫:没配 `${remote}:` remote(新机 / CI / 还没 rclone config)→ 静默 no-op ──
    if ! "$RCLONE" listremotes 2>/dev/null | grep -qx '${remote}:'; then
      log "remote '${remote}:' 未配置(rclone config 缺失),跳过同步(no-op)"
      exit 0
    fi

    # 公共 flags:--log-file 让 rclone 自身的进度/错误也进同一份日志。
    COMMON="--log-file=$LOG --log-level INFO"

    if [ ! -f ${initMarker} ]; then
      # ── 首次:建立同步基线。--resync 以本地 ${localDir} 为基准,不是双向合并 ──
      log "首次同步:rclone bisync --resync(以本地 ${localDir} 为基准建立基线)"
      if "$RCLONE" bisync ${localDir} ${remotePath} --resync $COMMON; then
        touch ${initMarker}
        log "首次 --resync 成功,已写标记 ${initMarker}"
      else
        log "首次 --resync 失败(保留无标记,下次重试);见上方 rclone 日志"
        exit 1
      fi
    else
      # ── 常规:双向 bisync。newer = 冲突按修改时间取较新;resilient = 尽量自愈 ──
      log "常规同步:rclone bisync --resilient --conflict-resolve newer"
      if "$RCLONE" bisync ${localDir} ${remotePath} --resilient --conflict-resolve newer $COMMON; then
        log "常规 bisync 成功"
      else
        # 常规 bisync 失败常因基线损坏(例如上次中断)。不 touch、不删标记,
        # 留给用户在日志里看到提示后,必要时手动 `rclone bisync ... --resync` 修复。
        log "常规 bisync 失败:基线可能损坏,可手动跑一次 --resync 修复;见上方 rclone 日志"
        exit 1
      fi
    fi
  '';
in
{
  # 公共:确保状态目录存在(日志/标记文件的家);两个平台都需要。
  home.activation.memorySyncDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "${stateDir}" "${localDir}"
  '';

  # ── macOS:launchd agent,每 StartInterval 秒跑一次同步脚本 ──
  # 注:optionalAttrs 放在 value 里(launchd/systemd 顶层 key 固定),不能在顶层 mkMerge
  #     里按 pkgs 条件增删属性,否则「模块声明哪些属性」依赖 pkgs → 无限递归。
  launchd.agents = lib.optionalAttrs isDarwin {
    "com.agentmemory.bisync" = {
      enable = true;
      config = {
        ProgramArguments = [ "${syncScript}" ];
        EnvironmentVariables = {
          # 脚本内部已用 store-path 引用二进制,这里给个保底 PATH + HOME 即可。
          PATH = "${coreutils}/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin";
          HOME = home;
        };
        WorkingDirectory = home;
        RunAtLoad = true; # 登录/加载即对一次账
        StartInterval = 900; # 之后每 900 秒(15 分钟)一次
        # 脚本自己写 ~/.agentmemory/rclone-bisync.log;这里再兜住 launchd 层面的 stdio。
        StandardOutPath = "${stateDir}/bisync.launchd.log";
        StandardErrorPath = "${stateDir}/bisync.launchd.err.log";
      };
    };
  };

  # ── Linux:systemd user service(oneshot)+ timer(每 15 分钟触发)──
  systemd.user.services = lib.optionalAttrs isLinux {
    "agentmemory-bisync" = {
      Unit = {
        Description = "agentmemory 共享记忆库 ~/data 的 rclone bisync 同步";
        # 弱依赖网络(user 级 network-online 不一定存在,故不强 Requires)。
        After = [ "network-online.target" ];
        Wants = [ "network-online.target" ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${syncScript}";
        # 没配 remote 时脚本 exit 0,systemd 视为成功 → no-op,不报错。
      };
    };
  };
  systemd.user.timers = lib.optionalAttrs isLinux {
    "agentmemory-bisync" = {
      Unit.Description = "定时触发 agentmemory ~/data bisync(每 15 分钟)";
      Timer = {
        OnBootSec = "5min"; # 开机/登录后 5 分钟先跑一次
        OnUnitActiveSec = "15min"; # 之后每 15 分钟一次
        Persistent = true; # 错过的触发在唤醒后补跑
      };
      Install.WantedBy = [ "timers.target" ];
    };
  };
}
