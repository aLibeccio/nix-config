{ config, lib, pkgs, ... }:
# agent-config —— 幂等注入 Claude Code / Codex 配置里我们关心的少数 key。
# 为什么只注入切片、不接管整文件:这些配置文件把少量配置和大量机器本地状态/密钥
# 混在一起,整文件托管会把状态塞进公开仓库、或冲掉别处的写入。所以只校正在意的几个
# key,其余字节原样不动;MCP 注册、trust_level、proxy 注入块等机器状态由别处管理。
# 每步先比较现值,已满足则 no-op(不写盘、不动 mtime);macOS / Linux 通用。
let
  jq = "${pkgs.jq}/bin/jq";

  # Codex 缺失时才补的「合理默认」。只在 key 完全缺失时写入,绝不覆盖用户已有选择。
  # 取舍:model 取一个保守、广泛可用的值;reasoning effort 取中档。换机器后用户随时
  #       可在文件里改成自己想要的(改了之后本模块就不再动它,因为不再缺失)。
  codexDefaultModel = "gpt-5.5";
  codexDefaultReasoningEffort = "medium";
in
{
  home.activation = {
    # ── 1. Claude ~/.claude/settings.json ────────────────────────────────────
    # 确保 enabledPlugins."superpowers@claude-plugins-official" = true 且 theme = "auto"。
    # 只动这两个 key,其它(如 skipDangerousModePermissionPrompt)原样保留。
    # 文件不存在 → 以 {} 起底;用 jq setpath 写到临时文件再 mv(原子替换)。
    # 先比较现值,两个 key 都已满足则不写盘(no-op)。
    claudeSettingsSlice = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      JQ=${lib.escapeShellArg jq}
      SETTINGS="$HOME/.claude/settings.json"
      # 没装 jq 就跳过(理论上 jq 在 home.packages,但保持守卫习惯)。
      if ! [ -x "$JQ" ]; then
        echo "[agent-config] jq 不可用,跳过 Claude settings 注入"
      else
        mkdir -p "$HOME/.claude"
        # 起底:文件不存在/为空时用 {};否则用现有内容(若 JSON 损坏则 jq 读取失败 → 跳过,不破坏文件)。
        if [ -s "$SETTINGS" ]; then
          if ! "$JQ" -e . "$SETTINGS" >/dev/null 2>&1; then
            echo "[agent-config] $SETTINGS 不是合法 JSON,跳过(不覆盖)"
            CUR=""
          else
            CUR=$(cat "$SETTINGS")
          fi
        else
          CUR='{}'
        fi
        if [ -n "''${CUR:-}" ]; then
          # 先判断是否已满足:superpowers 插件为 true 且 theme 为 "auto"。
          if printf '%s' "$CUR" | "$JQ" -e '
                (.enabledPlugins["superpowers@claude-plugins-official"] == true)
                and (.theme == "auto")
              ' >/dev/null 2>&1; then
            : # 已满足,no-op,不写盘
          else
            TMP=$(mktemp "''${SETTINGS}.XXXXXX")
            if printf '%s' "$CUR" | "$JQ" '
                  setpath(["enabledPlugins","superpowers@claude-plugins-official"]; true)
                  | setpath(["theme"]; "auto")
                ' > "$TMP" 2>/dev/null && [ -s "$TMP" ]; then
              mv "$TMP" "$SETTINGS"
              echo "[agent-config] 已更新 Claude settings(superpowers + theme=auto)"
            else
              rm -f "$TMP"
              echo "[agent-config] 写 Claude settings 失败,保持原文件不变"
            fi
          fi
        fi
      fi
    '';

    # ── 2. Codex ~/.codex/config.toml ────────────────────────────────────────
    # 确保 model 与 model_reasoning_effort 存在;只在顶层完全缺失时补默认,绝不覆盖已有值。
    # 用 grep 守卫 + 顶部插入而非 dasel:dasel v3 移除了写功能,只读;且 TOML 顶层键必须
    # 出现在第一个 [table] 之前,故插到文件最顶端是唯一合法位置。
    # 若 config.toml 不存在则不创建(Codex 首次运行会自建;我们不抢先造一个半成品)。
    codexConfigSlice = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      CONFIG="$HOME/.codex/config.toml"
      if ! [ -f "$CONFIG" ]; then
        # 文件不存在 → Codex 还没初始化过,跳过(不创建半成品配置)。
        echo "[agent-config] $CONFIG 不存在,跳过 Codex config 注入"
      else
        # $1=key 名,$2=缺失时要补的默认值。仅当顶层赋值缺失时,把键插到文件最顶端。
        ensure_codex_key() {
          if grep -Eq "^[[:space:]]*$1[[:space:]]*=" "$CONFIG"; then
            : # 顶层已有该键(用户的选择),no-op,不写盘
          else
            TMP=$(mktemp "''${CONFIG}.XXXXXX")
            if { printf '%s = "%s"\n' "$1" "$2"; cat "$CONFIG"; } > "$TMP" && [ -s "$TMP" ]; then
              mv "$TMP" "$CONFIG"
              echo "[agent-config] Codex 缺 $1,已补默认 \"$2\""
            else
              rm -f "$TMP"
              echo "[agent-config] 写 Codex $1 失败,保持原文件不变"
            fi
          fi
        }
        ensure_codex_key model ${lib.escapeShellArg codexDefaultModel}
        ensure_codex_key model_reasoning_effort ${lib.escapeShellArg codexDefaultReasoningEffort}
      fi
    '';
  };
}
