---
name: configure-codex-yd
description: 当需要在 macOS 上配置独立的 Codex YD / 有道版 Codex 启动入口时使用，包括 CODEX_HOME 分离、codex/codex-yd shell 包装、Codex YD.app 桌面入口、直连有道 API base_url、以及避免泄露 token。
---

# 配置 Codex YD

这个 skill 用来把同一个 `Codex.app` 拆成两套启动配置：

- 普通版：`CODEX_HOME=$HOME/.codex`
- YD 版：`CODEX_HOME=$HOME/.codex-yd`

这是配置隔离，不是安装两个 Codex。两套入口可以共用 `/Applications/Codex.app`，但使用不同的配置目录、登录状态、会话、可信项目、浏览器用户数据和启动环境。

## 快速使用

1. 标准 YD 配置方式：
   ```bash
   CODEX_YOUDAO_AUTH_TOKEN='使用者自己的 token' \
     /path/to/this-skill/scripts/setup-configure-codex-yd.zsh
   ```

2. 配置完成后自动执行（无需手动操作）：
   - 检查 `/Applications/Codex.app`：缺失时打印安装指引并退出（本脚本只做配置隔离，不替你安装 Codex.app）。
   - 默认把 `~/.codex-yd/config.toml` 的 `base_url` 直接配置为有道 API 地址：`https://newapi.inner.youdao.com/v1`。
   - 不启动本地代理，不安装 Node.js，不创建代理 LaunchAgent。
   - 自动打开「Codex YD」做一次启动验证。
   - 在终端打印「安装位置」和「怎么使用 Codex YD」说明（这是本 skill 的默认输出）。

3. 让 shell 生效（或新开终端窗口）：
   ```bash
   source "$HOME/.zshrc"
   ```

4. 验证：
   ```bash
   codex-yd --help          # YD 版 CLI
   codex --help             # 普通版 CLI（互不影响）
   ```
## 路由说明

默认直连有道 API base_url，不走本地代理：

```toml
[model_providers.custom]
base_url = "https://newapi.inner.youdao.com/v1"
env_key = "CODEX_YOUDAO_AUTH_TOKEN"
wire_api = "responses"
```

`env_key` 让 Codex 从本机环境变量读取 token，并以 Authorization 头发送请求。token 不写入 `config.toml`。

上游 API 地址已内置默认值（`https://newapi.inner.youdao.com/v1`），可用 `--youdao-api-url` 或 `CODEX_YD_UPSTREAM` 覆盖。个人 token 不内置，需使用者按下方「Token 配置」自行提供。

本 skill 不再提供本地 responses 到 chat/completions 代理路径；Codex YD 始终直接请求有道 base URL。

## 脚本会创建什么

安装脚本会创建或更新：

- `~/.codex-yd/config.toml`：YD 版模型配置。
- `~/.codex-yd/env.zsh`：本机 token 文件，权限为 `600`。
- `~/.zshrc`：受控代码块，定义 `codex`、`codex-cli`、`codex-yd`、`codex-yd-cli`。
- `~/Applications/Codex YD.app`：可双击的 YD 版 GUI 入口，带独立用户数据目录。

脚本只替换下面这个受控代码块，保留使用者自己的 shell 配置：

```text
# >>> configure-codex-yd >>>
# <<< configure-codex-yd <<<
```

## 入口行为

`codex` 打开普通版 GUI：

```bash
open -n -a "Codex" --env "CODEX_HOME=$HOME/.codex" --env "CODEX_YOUDAO_AUTH_TOKEN="
```

`codex-yd` 打开 YD 版 GUI：

```bash
open -n -a "Codex" \
  --env "CODEX_HOME=$HOME/.codex-yd" \
  --env "CODEX_YOUDAO_AUTH_TOKEN=$CODEX_YOUDAO_AUTH_TOKEN" \
  --args --user-data-dir="$HOME/Library/Application Support/Codex YD"
```

`codex exec ...` 走普通版 CLI，`codex-yd exec ...` 走 YD 版 CLI。

## 安全规则

- 不要把 token 写进 `config.toml`。
- 不要把个人 token、个人用户名写进 skill。上游 API 域名已内置默认值。
- 不要覆盖已有 `~/.codex-yd/config.toml`，除非使用者明确要求 `--force-config`。
- 不要把 `base_url` 改成本机代理地址；应保持为有道 API base URL 或使用者显式传入的有道兼容 base URL。
- 脚本会拒绝 localhost、127.0.0.1、0.0.0.0、::1 这类本机地址作为上游 base URL。
- 如果系统搜不到 `Codex YD.app`，先确认 app bundle 存在，再用 LaunchServices 注册或放到 `~/Applications`。

## 常用参数

查看完整帮助：

```bash
/path/to/this-skill/scripts/setup-configure-codex-yd.zsh --help
```

常用参数：

- `--model 模型名`
- `--youdao-api-url 上游 API base URL`（默认 `https://newapi.inner.youdao.com/v1`，可覆盖）
- `--force-config`
- `--no-app`

`--youdao-api-url` 默认值为 `https://newapi.inner.youdao.com/v1`，可用 `--youdao-api-url` 或环境变量 `CODEX_YD_UPSTREAM` 覆盖。

## Token 配置（小白友好）

Codex YD 需要一个「有道 API token」才能调用模型。这个 token 不内置在 skill 里，需你自己提供。脚本会自动引导你配置，优先级如下：

1. **已通过环境变量传入** → 直接写入，无需再问。
2. **之前已配过** → 复用 `~/.codex-yd/env.zsh`，不再追问。
3. **真实终端且未配过** → 脚本会先解释「token 是什么、去哪拿」，再用 `请粘贴你的有道 API token，然后按回车:` 交互询问（隐藏回显），粘上 token 按回车即可，无需懂命令行。
4. **非交互环境（如被 Codex agent 调用，stdin 不是 TTY）** → 脚本打印通俗指引后退出，告诉你：把 token 发给当前 Codex 对话，agent 会用环境变量方式帮你配好；或自己复制命令粘贴到终端。

**token 是什么 / 怎么获取**
- 它是有道内部 OpenAI 兼容 API 的鉴权凭证，通常是一串字母数字。
- 由团队管理员或内部门口分配；还没有就找管理员要。

**安全**
- token 只写到权限 600 的 `~/.codex-yd/env.zsh`，不进 `config.toml`，不在终端回显。
- 配一次后复用，之后运行脚本不会再问。

## 自动检查与安装

- Codex.app：缺失时不会自动安装，而是打印明确的安装步骤并退出，提示用户手动把 `Codex.app` 放进 `/Applications`。
- Node.js：不需要。本脚本不安装 Node.js，也不创建本地代理进程。

## 自动验证与默认输出

配置完成后，脚本会：

- 自动打开「Codex YD」做一次启动验证（优先用 GUI 启动器 `Codex YD.app`，没有则直接 `open -n -a Codex`）。
- 在终端打印一段「Codex YD 配置完成」横幅，包含「安装位置」和「怎么使用 Codex YD」两节，这是本 skill 的默认输出，用户无需再手动查询。
