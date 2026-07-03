#!/bin/zsh
set -euo pipefail

normal_home="${CODEX_NORMAL_HOME:-$HOME/.codex}"
yd_home="${CODEX_YD_HOME:-$HOME/.codex-yd}"
model="${CODEX_YD_MODEL:-glm-5.2}"
youdao_api_url="${CODEX_YD_UPSTREAM:-https://newapi.inner.youdao.com/v1}"
shell_config="${CONFIGURE_CODEX_YD_SHELL_CONFIG:-${CODEX_PROFILE_SPLIT_SHELL_CONFIG:-$HOME/.zshrc}}"
app_name="${CODEX_YD_APP_NAME:-Codex YD}"
app_dir="${CODEX_YD_APP_DIR:-$HOME/Applications/${app_name}.app}"
user_data_dir="${CODEX_YD_USER_DATA_DIR:-$HOME/Library/Application Support/Codex YD}"
create_app=1
force_config=0

usage() {
  cat <<'USAGE'
在 macOS 上配置普通 Codex 与 Codex YD 两套启动入口。

行为说明：
  - 自动检查 /Applications/Codex.app，缺失时打印安装指引并退出。
  - 直接把 Codex YD 的 base_url 配成有道 API 地址，不启动本地代理。
  - 配置完成后自动打开 Codex YD 做启动验证。
  - 退出前打印安装位置与使用说明。

用法：
  CODEX_YOUDAO_AUTH_TOKEN='使用者自己的 token' setup-configure-codex-yd.zsh [选项]

选项：
  --normal-home PATH       普通版 Codex home。默认：~/.codex
  --yd-home PATH           YD 版 Codex home。默认：~/.codex-yd
  --model NAME             YD 版模型名。默认：glm-5.2
  --youdao-api-url URL     上游 API base URL。默认：https://newapi.inner.youdao.com/v1
  --shell-config PATH      要更新的 shell 配置。默认：~/.zshrc
  --app-dir PATH           App 启动器路径。默认：~/Applications/Codex YD.app
  --user-data-dir PATH     YD GUI 用户数据目录。默认：~/Library/Application Support/Codex YD
  --force-config           覆盖 ~/.codex-yd/config.toml
  --no-app                 不创建 Codex YD.app
  --help                   显示帮助
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --normal-home) normal_home="$2"; shift 2 ;;
    --yd-home) yd_home="$2"; shift 2 ;;
    --model) model="$2"; shift 2 ;;
    --youdao-api-url) youdao_api_url="$2"; shift 2 ;;
    --shell-config) shell_config="$2"; shift 2 ;;
    --app-dir) app_dir="$2"; shift 2 ;;
    --user-data-dir) user_data_dir="$2"; shift 2 ;;
    --force-config) force_config=1; shift ;;
    --no-app) create_app=0; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "这个脚本只支持 macOS。" >&2
  exit 1
fi

if [[ ! -d "/Applications/Codex.app" ]]; then
  cat >&2 <<'CODEX_APP_HELP'
未找到 /Applications/Codex.app。请先安装 Codex 桌面应用：

  1. 打开 Codex 官网或分发页面下载安装包；
  2. 将 Codex.app 拖入 /Applications 目录；
  3. 首次运行如被 Gatekeeper 拦截，到「系统设置 > 隐私与安全性」点击「仍要打开」；
  4. 安装完成后重新执行本脚本。

本脚本只做配置隔离，不会替你安装 Codex.app。
CODEX_APP_HELP
  exit 1
fi

if [[ -z "$youdao_api_url" ]]; then
  echo "缺少上游 API URL，且环境变量 CODEX_YD_UPSTREAM 未设置。" >&2
  echo "请用 --youdao-api-url 指定，或设置 CODEX_YD_UPSTREAM。" >&2
  exit 1
elif [[ "$youdao_api_url" == http://localhost* \
  || "$youdao_api_url" == https://localhost* \
  || "$youdao_api_url" == http://127.* \
  || "$youdao_api_url" == https://127.* \
  || "$youdao_api_url" == http://0.0.0.0* \
  || "$youdao_api_url" == https://0.0.0.0* \
  || "$youdao_api_url" == http://\[::1\]* \
  || "$youdao_api_url" == https://\[::1\]* ]]; then
  echo "拒绝使用本机代理地址作为上游 API：$youdao_api_url" >&2
  echo "请使用有道 API base URL，例如：https://newapi.inner.youdao.com/v1" >&2
  exit 2
else
  echo "使用上游 API：$youdao_api_url（可用 --youdao-api-url 覆盖）"
fi

mkdir -p "$normal_home" "$yd_home" "$(dirname -- "$shell_config")"

# Token 配置：友好引导，照顾不熟悉命令行的用户
token_ready=0
if [[ -n "${CODEX_YOUDAO_AUTH_TOKEN:-}" ]]; then
  # 已通过环境变量传入
  printf 'export CODEX_YOUDAO_AUTH_TOKEN=%q\n' "$CODEX_YOUDAO_AUTH_TOKEN" > "$yd_home/env.zsh"
  chmod 600 "$yd_home/env.zsh"
  token_ready=1
elif [[ -f "$yd_home/env.zsh" ]]; then
  # 之前已配过，复用，不再追问
  echo "复用已有 token 文件：$yd_home/env.zsh"
  token_ready=1
elif [[ -t 0 ]]; then
  # 真实终端：交互式友好询问
  cat <<'TOKEN_PROMPT'

你需要一个「有道 API token」来让 Codex YD 调用模型。
说明：
  - 这是有道内部 OpenAI 兼容 API 的鉴权凭证，通常是一串字母数字。
  - 由团队管理员或内部门口分配；如果你还没有，请联系管理员获取。
  - 输入时不会显示字符，保护隐私；写入后只存于权限 600 的 env.zsh，
    不会写进 config.toml，也不会回显在终端。

TOKEN_PROMPT
  read -rs "?请粘贴你的有道 API token，然后按回车: " token
  echo
  if [[ -z "$token" ]]; then
    echo "未输入 token，已取消。请获取 token 后重新运行本脚本。" >&2
    exit 1
  fi
  printf 'export CODEX_YOUDAO_AUTH_TOKEN=%q\n' "$token" > "$yd_home/env.zsh"
  chmod 600 "$yd_home/env.zsh"
  echo "token 已保存到 $yd_home/env.zsh（权限 600）。"
  token_ready=1
fi

if [[ "$token_ready" -eq 0 ]]; then
  # 非交互环境（如被 Codex agent 调用）：打印通俗指引后退出
  cat >&2 <<TOKEN_HELP
未检测到有道 API token，且当前不是交互终端，无法直接询问你。

【这个 token 是什么？】
  它是调用有道内部模型的鉴权凭证（一串字母数字），由管理员分配。
  没有它，Codex YD 无法请求模型。

【怎么获取？】
  联系你的团队管理员，或在内部门口申请「有道 API token」。

【拿到 token 后怎么用？（最简单）】
  复制下面命令，把 你的token 替换成你拿到的 token，然后粘贴到终端运行：
    CODEX_YOUDAO_AUTH_TOKEN='你的token' 脚本绝对路径

【想一次配好，以后不用每次输？】
  手动创建 ~/.codex-yd/env.zsh，写入一行（注意保留单引号）：
      export CODEX_YOUDAO_AUTH_TOKEN='你的token'
  然后执行：chmod 600 ~/.codex-yd/env.zsh
  再重新运行本脚本即可。

【如果你是在 Codex 对话里触发的本 skill】
  把 token 直接发给当前对话，我会用环境变量方式帮你配置好，
  你无需手动操作任何命令。token 只会写到本机权限 600 的文件，
  不会出现在 config.toml 或对话记录里。
TOKEN_HELP
  exit 1
fi

base_url="$youdao_api_url"

config_path="$yd_home/config.toml"
if [[ ! -f "$config_path" || "$force_config" -eq 1 ]]; then
  cat > "$config_path" <<EOF_CONFIG
model = "$model"
model_provider = "custom"
model_reasoning_effort = "xhigh"
disable_response_storage = true
personality = "pragmatic"

[model_providers.custom]
name = "custom"
base_url = "$base_url"
env_key = "CODEX_YOUDAO_AUTH_TOKEN"
wire_api = "responses"
EOF_CONFIG
else
  echo "保留现有 $config_path。如需重写，使用 --force-config。"
fi

tmp_shell="$(mktemp)"
if [[ -f "$shell_config" ]]; then
  awk '
    BEGIN { skip = 0 }
    /^# >>> (codex-profile-split|configure-codex-yd) >>>$/ { skip = 1; next }
    /^# <<< (codex-profile-split|configure-codex-yd) <<<$/{ skip = 0; next }
    skip == 0 { print }
  ' "$shell_config" > "$tmp_shell"
else
  : > "$tmp_shell"
fi

cat >> "$tmp_shell" <<EOF_SHELL

# >>> configure-codex-yd >>>
_codex_is_cli_invocation() {
  case "\$1" in
    exec|e|review|login|logout|mcp|plugin|mcp-server|app|app-server|completion|sandbox|debug|apply|a|resume|fork|cloud|exec-server|features|help|-*|--*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

codex() {
  if [ "\$#" -gt 0 ] && _codex_is_cli_invocation "\$1"; then
    codex-cli "\$@"
  else
    open -n -a "Codex" \\
      --env "CODEX_HOME=$normal_home" \\
      --env "CODEX_YOUDAO_AUTH_TOKEN=" \\
      "\$@"
  fi
}

codex-cli() {
  CODEX_HOME="$normal_home" CODEX_YOUDAO_AUTH_TOKEN= command codex "\$@"
}

codex-yd() {
  if [ "\$#" -gt 0 ] && _codex_is_cli_invocation "\$1"; then
    codex-yd-cli "\$@"
  else
    if [ -f "$yd_home/env.zsh" ]; then
      . "$yd_home/env.zsh"
    fi
    open -n -a "Codex" \\
      --env "CODEX_HOME=$yd_home" \\
      --env "CODEX_YOUDAO_AUTH_TOKEN=\$CODEX_YOUDAO_AUTH_TOKEN" \\
      "\$@" \\
      --args --user-data-dir="$user_data_dir"
  fi
}

codex-yd-cli() {
  if [ -f "$yd_home/env.zsh" ]; then
    . "$yd_home/env.zsh"
  fi
  CODEX_HOME="$yd_home" command codex "\$@"
}
# <<< configure-codex-yd <<<
EOF_SHELL

mv "$tmp_shell" "$shell_config"

if [[ "$create_app" -eq 1 ]]; then
  mkdir -p "$(dirname -- "$app_dir")"
  tmp_osascript="$(mktemp)"
  shell_command="if [ -f '$yd_home/env.zsh' ]; then . '$yd_home/env.zsh'; fi; open -n -a 'Codex' --env 'CODEX_HOME=$yd_home' --env \"CODEX_YOUDAO_AUTH_TOKEN=\$CODEX_YOUDAO_AUTH_TOKEN\" --args --user-data-dir='$user_data_dir'"
  apple_shell_command="${shell_command//\\/\\\\}"
  apple_shell_command="${apple_shell_command//\"/\\\"}"
  print -r -- "do shell script \"/bin/zsh -lc \" & quoted form of \"$apple_shell_command\"" > "$tmp_osascript"
  osacompile -o "$app_dir" "$tmp_osascript"
  rm -f "$tmp_osascript"
  codesign --force --deep --sign - "$app_dir" >/dev/null 2>&1 || true
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app_dir" >/dev/null 2>&1 || true
fi

echo "已配置 Codex YD profile。"
echo "普通版 CODEX_HOME: $normal_home"
echo "YD 版 CODEX_HOME: $yd_home"
echo "YD 配置文件: $config_path"
echo "YD 直连有道 base_url: $youdao_api_url"
echo "已更新 shell 配置: $shell_config"
if [[ "$create_app" -eq 1 ]]; then
  echo "App 启动器: $app_dir"
fi

# 自动打开 Codex YD 进行验证
echo ""
echo "正在自动打开 Codex YD 进行验证..."
if [[ "$create_app" -eq 1 && -d "$app_dir" ]]; then
  open "$app_dir" >/dev/null 2>&1 || true
else
  if [[ -f "$yd_home/env.zsh" ]]; then
    . "$yd_home/env.zsh"
  fi
  open -n -a "Codex"     --env "CODEX_HOME=$yd_home"     --env "CODEX_YOUDAO_AUTH_TOKEN=$CODEX_YOUDAO_AUTH_TOKEN"     --args --user-data-dir="$user_data_dir" >/dev/null 2>&1 || true
fi

cat <<USAGE_BANNER

============================================================
 Codex YD 配置完成
============================================================
【安装位置】
  - YD 配置目录 (CODEX_HOME): $yd_home
  - YD 配置文件:                $config_path
  - 本机 token 文件 (600):       $yd_home/env.zsh
  - 有道 API base_url:          $youdao_api_url
USAGE_BANNER
if [[ "$create_app" -eq 1 ]]; then
cat <<USAGE_BANNER
  - GUI 启动器 (可双击):         $app_dir
USAGE_BANNER
fi
cat <<USAGE_BANNER
  - Shell 配置 (已更新受控块):  $shell_config
  - GUI 用户数据目录:            $user_data_dir

【怎么使用 Codex YD】
  方式一（推荐，GUI）：
    双击「$app_name」(位置: $app_dir)
    或在终端执行:  open -a "$app_name"

  方式二（终端命令）：
    先让 shell 生效:  source "$shell_config"  (或新开终端窗口)
    打开 YD 版 GUI:   codex-yd
    YD 版 CLI:        codex-yd exec "你的需求"
    YD 版 CLI 帮助:   codex-yd --help

  普通版 Codex 互不影响:
    普通版 GUI:       codex
    普通版 CLI:       codex exec "..."

【验证】
  - YD CLI:    codex-yd --help
  - YD GUI:    codex-yd

如需更换模型或上游地址，重新运行本脚本并加 --force-config 覆盖配置。
============================================================
USAGE_BANNER
