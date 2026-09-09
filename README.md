# Serial Logs / RV1126B 串口工具

本目录是一套给 **人类、Luna / OpenCode、Codex 等 Agent 共用**的 RV1126B 串口访问与日志工具。

核心原则：**不要让多个程序直接打开真实串口。** `seriald` 是唯一持有 FTDI 串口的后台服务；所有人工或 Agent 操作统一通过 `serialctl` 完成。

## 当前设备配置

- 开发板：RV1126B
- USB-UART：FTDI FT232R
- USB VID:PID：`0403:6001`
- USB Serial：`AL0783ER`
- 稳定设备路径：`/dev/serial/by-id/usb-FTDI_FT232R_USB_UART_AL0783ER-if00-port0`
- 波特率：`1500000`
- 格式：`8N1`
- 日志目录：`~/work/serial-logs/rv1126b/`

## 目录结构

```text
~/work/serial-logs/
├── README.md
├── bin/
│   ├── seriald       # 后台串口 broker，唯一直接打开真实串口的程序
│   └── serialctl     # 人类 / Agent 使用的命令行客户端
└── rv1126b/
    ├── YYYY-MM-DD.log
    ├── YYYY-MM-DD.jsonl
    └── latest.log -> 当天日志
```

systemd 用户服务位于：

```text
~/.config/systemd/user/seriald-rv1126b.service
```

## 给 Agent 的重要规则

如果你是 Luna、OpenCode、Codex 或其他自动化 Agent：

1. **不要直接打开** `/dev/ttyUSB0` 或 `/dev/serial/by-id/...`。
2. **不要启动** `tio`、`minicom`、`screen`、SecureCRT 等程序去抢占真实串口。
3. 所有串口收发统一使用 `serialctl`。
4. 操作前优先执行 `serialctl status` 确认连接状态。
5. Linux shell 已登录时，执行命令优先使用 `serialctl exec`。
6. 等待未来出现的串口内容使用 `serialctl wait`。
7. 调查过去发生的事情使用 `serialctl tail` / `serialctl grep`，必要时直接读取 `rv1126b/*.log` 或 `*.jsonl`。
8. 发送数据时尽量标记操作者，例如 `--actor luna`、`--actor codex`、`--actor opencode`。
9. `reboot`、修改系统、写 Flash、U-Boot 操作等具有破坏性的命令，应遵循当前 Agent 自身的权限/确认规则，不要因为串口工具可用就绕过确认。

## 常用命令

检查串口服务和连接状态：

```bash
serialctl status
```

查看最近 100 行日志：

```bash
serialctl tail 100
```

查看最近 500 行：

```bash
serialctl tail 500
```

实时观察串口：

```bash
serialctl watch
```

进入实时交互终端（默认使用底部固定输入行）：

```bash
serialctl attach
```

固定输入模式会把串口输出放在上方滚动区，输入行始终保持在终端底部；按 Enter 后发送整行，按 `Ctrl+]` 退出。底部提示符使用与 zsh 相近但不同的配色：`serialctl` 为青色、设备标识为紫色、`attach` 为蓝色、输入提示符为黄色。

需要逐字节透传时使用原始模式：

```bash
serialctl attach --raw
```

原始模式适合 U-Boot、密码提示、全屏交互程序和必须立即响应单个按键的场景。

发送一行文本（默认自动追加换行）：

```bash
serialctl send 'uname -a'
```

发送原始文本，不自动追加换行：

```bash
serialctl send --raw ' '
```

等待从现在开始新出现的字符串：

```bash
serialctl wait 'login:' -t 60
```

正则等待：

```bash
serialctl wait --regex 'U-Boot|Hit any key' -t 30
```

在已经进入 Linux shell 的串口中执行命令并等待结束：

```bash
serialctl exec 'uname -a'
serialctl exec 'cat /etc/os-release'
serialctl exec 'dmesg | tail -n 50' -t 60
```

查找当前日志中的错误：

```bash
serialctl grep -i 'error|fail|panic|oops'
```

## Agent 身份标记

推荐显式指定发送者：

```bash
serialctl --actor luna exec 'uname -a'
serialctl --actor codex exec 'dmesg | tail -n 30'
serialctl --actor opencode send 'help'
```

也可以在当前 Agent shell 环境设置：

```bash
export SERIAL_ACTOR=luna
```

之后直接：

```bash
serialctl exec 'uname -a'
```

TX 日志会记录发送者，例如：

```text
[2026-09-08 11:30:01.123] [TX:luna] uname -a
[2026-09-08 11:30:01.150] [RX] Linux elf1126b-debian ...
```

## 日志

人类可读日志：

```text
~/work/serial-logs/rv1126b/YYYY-MM-DD.log
```

机器可读 JSON Lines：

```text
~/work/serial-logs/rv1126b/YYYY-MM-DD.jsonl
```

当前日志快捷入口：

```text
~/work/serial-logs/rv1126b/latest.log
```

典型事件：

```text
[2026-09-08 11:20:00.001] [EVENT] SERIALD_START ...
[2026-09-08 11:20:00.120] [EVENT] CONNECT ... baud=1500000
[2026-09-08 11:21:05.300] [RX] elf1126b-debian login:
[2026-09-08 11:22:10.410] [TX:luna] uname -a
[2026-09-08 11:22:10.430] [RX] Linux elf1126b-debian ...
[2026-09-08 11:25:00.000] [EVENT] DISCONNECT ...
```

要调查昨天或更早的事故，不要只使用 `serialctl tail`，直接搜索历史日志，例如：

```bash
grep -Ein 'panic|oops|error|fail' ~/work/serial-logs/rv1126b/*.log
```

JSONL 可以使用 `jq` 分析，例如只看 Luna 的发送记录：

```bash
jq 'select(.type == "tx" and .actor == "luna")' ~/work/serial-logs/rv1126b/*.jsonl
```

## serialctl 命令语义

### `status`

查看 `seriald` 是否运行、真实串口是否连接、设备路径和波特率。

### `send`

单纯向串口发送数据。适合登录、U-Boot、交互式程序等场景。

默认追加 `\n`；需要精确发送时使用 `--raw`。

### `wait`

等待**调用之后新收到的 RX** 出现指定文本。它不是历史日志搜索工具。

例如等待设备重启后的登录提示：

```bash
serialctl wait 'login:' -t 120
```

### `exec`

用于已经处于 Linux shell 的串口。它发送命令并追加唯一结束标记，从而判断命令何时结束以及取得退出码。

它不是通用 RPC；如果当前处于 U-Boot、登录界面、密码提示或其他交互程序中，应使用 `send` + `wait`。

### `attach`

打开人工实时交互终端：

```bash
serialctl attach
```

默认是固定输入行模式。串口异步输出显示在上方，当前输入不会被输出冲散；本地支持左右移动、Home/End、Backspace 和上下历史，按 Enter 才发送整行。

固定模式还会对少量高频网络状态做快速高亮：`[network.c][rk_network_get_cable_state]` 使用 256 色 `214`，`[wlan0] link down` 使用加粗橙色。错误关键词使用红色，成功/启动节点使用绿色或青色，高频 `MD: md_area` 信息使用暗灰色。高亮只作用于终端画面，不修改串口日志文件、JSONL 或 `--raw` 输出。

以下场景使用原始逐字节模式：

```bash
serialctl attach --raw
```

退出两种模式都使用 `Ctrl+]`。Agent 或脚本不应使用 `attach` 代替 `exec`；非交互命令优先使用 `serialctl exec`。

### `tail` / `grep`

用于查看已经落盘的日志，不直接访问真实串口。

### `watch`

持续跟随 `latest.log`，适合人工旁观串口输出。

## 服务管理

查看服务：

```bash
systemctl --user status seriald-rv1126b
```

启动：

```bash
systemctl --user start seriald-rv1126b
```

停止：

```bash
systemctl --user stop seriald-rv1126b
```

重启：

```bash
systemctl --user restart seriald-rv1126b
```

查看服务自身日志：

```bash
journalctl --user -u seriald-rv1126b -n 100
```

持续查看服务日志：

```bash
journalctl --user -u seriald-rv1126b -f
```

注意：`journalctl` 主要用于检查 `seriald` 服务本身；开发板 UART 历史应查看 `~/work/serial-logs/rv1126b/`。

## 故障排查

如果 `serialctl status` 报 socket 不存在：

```bash
systemctl --user status seriald-rv1126b
journalctl --user -u seriald-rv1126b -n 100
```

如果提示串口权限不足：

```bash
id
ls -l /dev/serial/by-id/usb-FTDI_FT232R_USB_UART_AL0783ER-if00-port0
```

当前 Debian 设备通常属于 `root:dialout`，运行用户需要拥有 `dialout` 组权限；修改组后需要重新登录会话。

如果 USB 拔掉，`seriald` 设计为等待设备并在设备重新出现后重新连接。不要因为 `/dev/ttyUSB0` 编号改变而修改配置；配置使用的是 FT232R 的稳定 `by-id` 路径。

## 并发注意事项

`seriald` 解决了“多个程序同时直接占用 FTDI”的问题，但当前版本**还没有完整的高层 Session/Transaction Lock**。

因此 Luna 和 Codex 不应在同一时刻对同一个交互式 shell 执行互相冲突的命令。尤其不要在另一个 Agent 正执行 `exec` 时插入登录、重启、U-Boot 或其他交互输入。

如需多 Agent 高频并发控制，后续应给 `seriald` 增加 session lock / transaction lock。

## Git 协作与提交规则

Git 操作必须遵守用户授权边界。良好的提交习惯是协作与维护的基础。

### 授权规则

- 未经用户明确同意，不得执行 `git commit`。
- 未经用户明确同意，不得执行 `git push`，包括普通推送、带标签推送和强制推送。
- 用户没有明确要求时，只进行代码修改、测试以及 `git status`、`git diff`、`git log` 等检查。
- 不得因为测试通过、任务完成或仓库已初始化而自动提交或推送。

### 提交类型

提交消息格式建议为：

```text
<type>(<scope>): <简短说明>
```

| type | 用途 | 示例 |
| --- | --- | --- |
| `feat` | 新功能（feature） | `feat(auth): 增加微信登录功能` |
| `fix` | 修补 Bug | `fix(menu): 修复下拉菜单在移动端不显示的错误` |
| `refactor` | 重构，不新增功能也不修复 Bug | `refactor: 简化逻辑判断函数` |
| `perf` | 性能优化 | `perf: 提高渲染效率` |
| `docs` | 文档变动 | `docs: 更新 API 使用说明` |
| `test` | 增加或修改测试 | `test: 添加登录模块单元测试` |
| `chore` | 构建过程或辅助工具变动 | `chore: 升级依赖库` |
| `wip` | 工作进行中（Work In Progress） | `wip: 正在处理搜索建议逻辑` |

### 禁止使用的类型

以下词语不得作为提交类型：

```text
add
update
modify
big
```

## 一句话给 Agent

> RV1126B 串口由 `seriald` 独占管理。不要直接访问 tty；使用 `serialctl status/tail/watch/send/wait/exec/attach/grep`。人工交互默认使用 `serialctl attach`，需要逐字节透传时使用 `serialctl attach --raw`。设备是 FTDI FT232R，1500000 8N1。历史日志位于 `~/work/serial-logs/rv1126b/`。
