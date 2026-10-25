export const CWD_OSC_ID = 777
export const OSC7_ID = 7
export const INIT_DONE_OSC_ID = 778

/**
 * 解析 OSC 7 载荷：`file://host/path`，路径按 URI 规则解码。
 * 无法识别时返回 null。
 */
export function parseOsc7Path(data: string): string | null {
  const match = /^file:\/\/[^/]*(\/.*)$/.exec(data.trim())
  if (!match) {
    return null
  }

  const raw = match[1]
  try {
    return decodeURIComponent(raw)
  } catch {
    return raw
  }
}

/**
 * 单行 bash/zsh 钩子：每次出现提示符前输出 OSC 7，让前端持续跟踪 cwd。
 * 已安装时跳过（重连不会重复注册），非 bash/zsh 时静默无效。
 * `%` 先转成 `%25`，与 parseOsc7Path 的解码对应。
 */
export function buildCwdHookCommand() {
  const zsh = `__hd_cwd(){ printf '\\033]7;file://%s%s\\033\\\\' "$HOST" "\${PWD//\\%/%25}"; }; precmd_functions+=(__hd_cwd)`
  const bash = `__hd_cwd(){ printf '\\033]7;file://%s%s\\033\\\\' "$HOSTNAME" "\${PWD//\\%/%25}"; }; PROMPT_COMMAND="__hd_cwd\${PROMPT_COMMAND:+;$PROMPT_COMMAND}"`

  return (
    ` type __hd_cwd >/dev/null 2>&1 || { if [ -n "$ZSH_VERSION" ]; then ${zsh}; ` +
    `elif [ -n "$BASH_VERSION" ]; then ${bash}; fi; }; ` +
    `type __hd_cwd >/dev/null 2>&1 && __hd_cwd`
  )
}

/**
 * 初始化收尾：清屏抹掉前面命令的回显，并输出 OSC 778 通知前端初始化完成。
 * 单独一行发送，避免前一行在 fish 等 shell 中语法错误时连带失效。
 */
export function buildInitFinishCommand() {
  return ` clear; printf '\\033]${INIT_DONE_OSC_ID};ready\\007'`
}
