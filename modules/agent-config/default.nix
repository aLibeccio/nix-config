{ config, lib, pkgs, ... }:
# agent-config: idempotently patch selected Claude/Codex settings.
# Do not own whole config files; they also contain local state.
let
  jq = "${pkgs.jq}/bin/jq";

  # Only fill missing Codex defaults.
  codexDefaultModel = "gpt-5.5";
  codexDefaultReasoningEffort = "xhigh";
in
{
  home.activation = {
    # ── 1. Claude ~/.claude/settings.json ────────────────────────────────────
    # Claude settings defaults.
    claudeSettingsSlice = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      JQ=${lib.escapeShellArg jq}
      SETTINGS="$HOME/.claude/settings.json"
      # 没装 jq 就跳过(理论上 jq 在 home.packages,但保持守卫习惯)。
      if ! [ -x "$JQ" ]; then
        echo "[agent-config] jq 不可用,跳过 Claude settings 注入"
      else
        mkdir -p "$HOME/.claude"
          # Start from valid JSON or {}.
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
    # Insert missing top-level TOML keys.
    codexConfigSlice = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      CONFIG="$HOME/.codex/config.toml"
      if ! [ -f "$CONFIG" ]; then
        # Skip before Codex creates the file.
        echo "[agent-config] $CONFIG 不存在,跳过 Codex config 注入"
      else
        # Insert a missing top-level TOML key.
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
