# Serial Logs / 多实例串口工具

本目录是一套给 **人类、Luna / OpenCode、Codex 等 Agent 共用**的串口访问与日志工具。

核心原则：**不要让多个程序直接打开真实串口。** 每个串口实例由一个 `seriald` 后台服务独占；所有人工或 Agent 操作统一通过 `serialctl` 完成。

## 实例模型

一个实例 = 一份配置 + 一个 `seriald` 服务 + 一个日志目录。

| 实例名 | 设备 | 情况 |
| --- | --- | --- |
| `rv1126b` | RV1126B 开发板（FTDI FT232R，`1500000 8N1`） | 板子当前不在本机，服务等待设备 |
| `s41-5-18` | s41-5-18 摄像头样机（CH340，`115200 8N1`） | 已连接，但样机已交测试同事，串口当前无输出 |
| `atk1126b` | 正点原子 ATK-DLRV1126B | 待接板，配置里 `device` 仍是占位符，服务未启用 |
| `w14` | w14 板（预留） | 未接入，服务未启用 |

> 历史说明：`logs/w14/` 旧目录里的日志其实属于 s41-5-18，已迁移到 `logs/s41-5-18/`。

查当前所有实例：

```bash
serialctl list
```

输出中的状态含义：

- `已连接`：`seriald` 在跑，且串口设备打开成功
- `等待设备`：`seriald` 在跑，但 USB 串口没插上（或 `device` 路径不对）
- `未运行`：对应 `seriald@<实例名>` 服务没启动

## 目录结构

```text
~/work/serial-logs/
├── README.md
├── bin/
│   ├── seriald          # 后台串口 broker，唯一直接打开真实串口的程序
│   └── serialctl        # 人类 / Agent 使用的命令行客户端
├── config/
│   ├── example.conf     # 配置模板（带逐字段注释，复制改名即用）
│   ├── rv1126b.conf
│   ├── s41-5-18.conf
│   ├── atk1126b.conf
│   └── w14.conf
├── logs/                # 按实例分目录，日志不入库
│   └── <实例名>/
│       ├── YYYY-MM-DD.log
│       ├── YYYY-MM-DD.jsonl
│       └── latest.log -> 当天日志
├── systemd/
│   └── seriald@.service # 模板单元（软链到 ~/.config/systemd/user/）
```

## 新增一个实例

```bash
cd ~/work/serial-logs
cp config/example.conf config/<实例名>.conf   # 名字只允许小写字母、数字、_、-
vi config/<实例名>.conf                       # 改 device / baud / prompt
ls -l /dev/serial/by-id/                      # 先确认设备的稳定路径
systemctl --user enable --now seriald@<实例名>
serialctl list
serialctl attach -s <实例名>
```

配置分三段：

| 段 | 字段 | 说明 |
| --- | --- | --- |
| `[serial]` | `device` | **必须用 `/dev/serial/by-id/...`**，`/dev/ttyUSB0` 编号会变 |
| | `baud` | 常用值：9600 / 115200 / 921600 / 1500000（Rockchip 调试口）/ 3000000 |
| | `databits` / `parity` / `stopbits` | 5-8 / none-even-odd-mark-space / 1-1.5-2，默认 `8N1` |
| | `flow` | `none` / `rtscts` / `xonxoff` |
| `[log]` | `dir` | 留空 = `logs/<实例名>/`；填路径则覆盖 |
| | `wait_log_interval` | 设备不在时多久记一条 `WAITING_DEVICE`（秒），默认 600 |
| | `retention_days` | 日志保留天数，0 = 永久 |
| `[attach]` | `prompt` | 行模式识别板端提示符的 bytes 正则；留空 = 内置通用规则 |

配置文件支持行尾 `#` 注释，例如：

```ini
baud = 1500000     # Rockchip 调试口
```

## 给 Agent 的规则

如果你是 Luna、OpenCode、Codex 或其他自动化 Agent：

1. **不要直接打开** `/dev/ttyUSB*` 或 `/dev/serial/by-id/...`。
2. **不要启动** `tio`、`minicom`、`screen`、SecureCRT 等程序去抢占真实串口。
3. 所有串口收发统一使用 `serialctl -s <实例名>`。
4. 操作前先 `serialctl list` 或 `serialctl -s <实例名> status` 确认状态。
5. Linux shell 已登录时，执行命令优先使用 `serialctl -s <实例名> exec`。
6. 等待未来出现的串口内容使用 `serialctl -s <实例名> wait`。
7. 调查过去的事情用 `serialctl -s <实例名> tail` / `grep`，或直接读 `logs/<实例名>/*.log`、`*.jsonl`。
8. 发送时标记操作者：`--actor luna` / `--actor codex` / `--actor opencode`。
9. `reboot`、改系统、写 Flash、U-Boot 操作等破坏性动作，遵循 Agent 自身的确认规则，不要因为串口可用就绕过确认。

## 常用命令

`-s/--serial` 是所有命令（除 `list`）的必需参数；不带时报错并列出可用实例。
实例名就是 `config/<名字>.conf` 里的 `<名字>`，**不要带 `.conf`，也不要写路径**。

`-s` 写在子命令前后都可以：

```bash
serialctl -s atk1126b status      # 推荐写法
serialctl status -s atk1126b      # 等价
```

检查服务与连接状态：

```bash
serialctl -s rv1126b status
serialctl -s s41-5-18 status
```

查看最近 100 行日志：

```bash
serialctl -s s41-5-18 tail 100
```

实时观察串口：

```bash
serialctl -s s41-5-18 watch
```

进入实时交互终端（默认底部固定输入行）：

```bash
serialctl -s rv1126b attach
```

固定输入模式把串口输出放在上方滚动区，输入行始终保持在终端底部；按 Enter 发送整行，按 `Ctrl+]` 退出。识别到板端的 `user@host:/path#`、`%` 或 `$` 提示符后，底部会同步用户、主机、当前路径和提示符字符；`#` 为加粗红色，`%` 使用较平缓的加粗蓝色，命令首词使用加粗青色。

需要逐字节透传时使用原始模式（U-Boot、密码提示、全屏交互程序）：

```bash
serialctl -s rv1126b attach --raw
```

发送一行文本（默认自动追加换行）：

```bash
serialctl -s rv1126b send 'uname -a'
```

发送原始文本，不自动追加换行：

```bash
serialctl -s rv1126b send --raw ' '
```

等待从现在开始新出现的字符串：

```bash
serialctl -s rv1126b wait 'login:' -t 60
serialctl -s rv1126b wait --regex 'U-Boot|Hit any key' -t 30
```

在已经进入 Linux shell 的串口上执行命令并等待结束：

```bash
serialctl -s rv1126b exec 'uname -a'
serialctl -s rv1126b exec 'dmesg | tail -n 50' -t 60
```

查找当前日志中的错误：

```bash
serialctl -s rv1126b grep -i 'error|fail|panic|oops'
```

## Agent 身份标记

推荐显式指定发送者：

```bash
serialctl -s rv1126b --actor luna exec 'uname -a'
serialctl -s rv1126b --actor opencode send 'help'
```

也可以在当前 Agent shell 环境设置：

```bash
export SERIAL_ACTOR=luna
```

TX 日志会记录发送者：

```text
[2026-09-08 11:30:01.123] [TX:luna] uname -a
[2026-09-08 11:30:01.150] [RX] Linux elf1126b-debian ...
```

## 日志

按实例分目录：

```text
logs/<实例名>/YYYY-MM-DD.log     # 人类可读
logs/<实例名>/YYYY-MM-DD.jsonl   # JSON Lines
logs/<实例名>/latest.log         # 当天日志的软链
```

典型事件：

```text
[2026-09-08 11:20:00.001] [EVENT] SERIALD_START instance=rv1126b device=... baud=1500000
[2026-09-08 11:20:00.120] [EVENT] CONNECT /dev/serial/by-id/... -> /dev/ttyUSB0 baud=1500000
[2026-09-08 11:21:05.300] [RX] elf1126b-debian login:
[2026-09-08 11:22:10.410] [TX:luna] uname -a
[2026-09-08 11:25:00.000] [EVENT] WAITING_DEVICE [Errno 2] could not open port ...
```

要调查昨天或更早的事故，直接搜历史日志：

```bash
grep -Ein 'panic|oops|error|fail' ~/work/serial-logs/logs/rv1126b/*.log
```

JSONL 可用 `jq` 分析，例如只看某个操作者的发送记录：

```bash
jq 'select(.type == "tx" and .actor == "luna")' ~/work/serial-logs/logs/rv1126b/*.jsonl
```

设备不在时，`seriald` 默认每 600 秒才记一条 `WAITING_DEVICE`（可在配置里改 `wait_log_interval`）。

保留策略：`retention_days = 30` 时，服务启动会删除 30 天前的 `*.log`/`*.jsonl`。
历史日志可以手工归档成 `YYYY-Www.jsonl.tar.gz`，见下一节。

### 两种文件的分工

| 文件 | 内容 | 用途 |
|---|---|---|
| `YYYY-MM-DD.log` | **清洗过**：去掉 ANSI/OSC/BEL，`\r` 按行只保留最后一段 | 人看：`tail`/`grep`/VS Code 直接打开 |
| `YYYY-MM-DD.jsonl` | **原始**：一条记录 = 一次串口读写，`\u001b` 等控制字符完整保留 | 机器看：唯一事实来源、可重建 `.log` |

`.log` 是"渲染物"，丢了可以随时从 `.jsonl` 重建；`.jsonl` 不要手工改。

## 日志归档与重建

### 从 jsonl 重建 log

```bash
cd ~/work/serial-logs/logs

python3 jsonl2log.py                # 处理脚本所在目录
python3 jsonl2log.py w14            # 处理指定实例目录
python3 jsonl2log.py w14 --force    # 覆盖已有 .log
python3 jsonl2log.py w14 --dry-run  # 只报告
```

- 仅用 Python 标准库；
- 输出格式、清洗规则与 `seriald` 写 `.log` 时完全一致；
- 默认跳过"已存在且不比 jsonl 旧"的 `.log`。

### 按完整 ISO 周归档

```bash
cd ~/work/serial-logs/logs

bash archive.sh                                  # 演练：列出将归档的周
bash archive.sh --apply                          # 真正执行
bash archive.sh --instance w14 --apply           # 只处理某个实例
bash archive.sh --week 2026-W42 --apply          # 补打指定周
```

规则：

- 只归档**已经结束的完整周**（该周周日 < 今天）；本周和当天文件不动；
- 每个实例单独打包：`logs/<实例>/archive/<YYYY-Www>.jsonl.tar.gz`；
- 只装 `.jsonl`，包内附 `manifest`（日期/字节/行数）；
- 流程固定：打包 → `tar -tzf` 校验 → 写 `archive/MD5.txt` → 删该周 `.jsonl` 与 `.log`；
- 任何一步失败就停，不删任何文件。

自动触发（默认不启用，需要时自己加）：

```ini
# ~/.config/systemd/user/serial-archive.service
[Unit]
Description=Serial log weekly archive

[Service]
Type=oneshot
ExecStart=/bin/bash %h/work/serial-logs/logs/archive.sh --apply
```

```ini
# ~/.config/systemd/user/serial-archive.timer
[Unit]
Description=Weekly serial archive (Monday 00:10)

[Timer]
OnCalendar=Mon *-*-* 00:10:00
Persistent=true

[Install]
WantedBy=timers.target
```

```bash
systemctl --user daemon-reload
systemctl --user enable --now serial-archive.timer
```

## serialctl 命令语义

### `list`

列出 `config/*.conf` 里的所有实例，以及它们当前是 `已连接` / `等待设备` / `未运行`。不需要 `-s`。

### `status`

查看实例的 `seriald` 是否在跑、串口是否连接、设备路径、波特率、日志目录。

### `send`

单纯向串口发送数据，适合登录、U-Boot、交互式程序。默认追加 `\n`；需要精确发送时使用 `--raw`。

### `wait`

等待**调用之后新收到的 RX** 出现指定文本，不是历史日志搜索工具。

```bash
serialctl -s rv1126b wait 'login:' -t 120
```

### `exec`

用于已经处于 Linux shell 的串口。发送命令并追加唯一结束标记，从而判断命令何时结束以及取得退出码。

如果当前处于 U-Boot、登录界面、密码提示或其他交互程序，应使用 `send` + `wait`。

### `attach`

人工实时交互终端。默认固定输入行模式，本地支持左右移动、Home/End、Backspace 和上下历史，按 Enter 才发送整行；`Ctrl+]` 退出。

固定模式会对板端提示符、已发送命令回显和少量高频网络状态做高亮：`[network.c][rk_network_get_cable_state]` 使用 256 色 `214`，`[wlan0] link down` 使用加粗橙色；错误关键词红色，成功/启动节点绿色或青色，高频 `MD: md_area` 暗灰色。高亮只作用于终端画面，不修改日志文件、JSONL 或 `--raw` 输出。

Agent 或脚本不应使用 `attach` 代替 `exec`。

### `tail` / `grep` / `watch`

读取实例的落盘日志（`logs/<实例名>/`），不直接访问真实串口。

`grep` 的 pattern 是 Python 正则；`-i` 忽略大小写，`-c` 只输出匹配行数：

```bash
serialctl -s atk1126b grep -i 'error|fail'
serialctl -s atk1126b grep -c '已发现设备'
```

## 服务管理

模板单元源码在本仓库 `systemd/seriald@.service`，通过软链挂到 systemd：

```text
~/.config/systemd/user/seriald@.service -> ~/work/serial-logs/systemd/seriald@.service
```

常用操作：

```bash
systemctl --user status  seriald@s41-5-18
systemctl --user start   seriald@s41-5-18
systemctl --user stop    seriald@s41-5-18
systemctl --user restart seriald@s41-5-18
systemctl --user enable --now seriald@atk1126b     # 接板后启用
journalctl --user -u seriald@s41-5-18 -n 100
```

`journalctl` 只用于检查 `seriald` 服务本身；板端 UART 历史看 `logs/<实例名>/`。

改完模板单元需要重新加载：

```bash
systemctl --user daemon-reload
systemctl --user restart seriald@<实例名>
```

## 故障排查

`serialctl -s <实例名> status` 报 socket 不存在：

```bash
systemctl --user status seriald@<实例名>
journalctl --user -u seriald@<实例名> -n 100
```

提示串口权限不足：

```bash
id
ls -l /dev/serial/by-id/<设备>
```

设备通常属于 `root:dialout`，运行用户需要 `dialout` 组权限；改组后需重新登录会话。模板单元用 `sg dialout -c ...` 启动，正常不需要额外处理。

USB 拔掉时 `seriald` 会等待设备并自动重连。不要因为 `/dev/ttyUSB0` 编号改变而改配置——配置用的是 `by-id` 稳定路径。

## 并发注意事项

`seriald` 解决了“多个程序同时直接占用串口设备”的问题，但当前版本**还没有完整的高层 Session/Transaction Lock**。

因此 Luna 和 Codex 不应在同一时刻对同一个交互式 shell 执行互相冲突的命令。尤其不要在另一个 Agent 正执行 `exec` 时插入登录、重启、U-Boot 或其他交互输入。

不同实例之间互不影响（各自独立的 socket、日志、服务）。

## Git 协作与提交规则

### 授权规则

- 未经用户明确同意，不得执行 `git commit`。
- 未经用户明确同意，不得执行 `git push`，包括普通推送、带标签推送和强制推送。
- 用户没有明确要求时，只进行代码修改、测试以及 `git status`、`git diff`、`git log` 等检查。
- 不得因为测试通过、任务完成或仓库已初始化而自动提交或推送。

### 提交类型

```text
<type>(<scope>): <简短说明>
```

| type | 用途 | 示例 |
| --- | --- | --- |
| `feat` | 新功能 | `feat(auth): 增加微信登录功能` |
| `fix` | 修补 Bug | `fix(menu): 修复下拉菜单在移动端不显示的错误` |
| `refactor` | 重构，不新增功能且不修复 Bug | `refactor: 简化逻辑判断函数` |
| `perf` | 性能优化 | `perf: 提高渲染效率` |
| `docs` | 文档变动 | `docs: 更新 API 使用说明` |
| `test` | 增加或调整测试 | `test: 添加登录模块单元测试` |
| `chore` | 构建过程或辅助工具变动 | `chore: 升级依赖库` |
| `wip` | 工作进行中 | `wip: 正在处理搜索建议逻辑` |

以下词语不得作为提交类型：`add`、`update`、`modify`、`big`。

### 不入库的内容

`logs/` 下的运行日志属于本地证据，已在 `.gitignore` 中排除。

## 一句话给 Agent

> 串口由 `seriald@<实例名>` 独占管理。不要直接访问 tty；用 `serialctl list` 找实例，然后 `serialctl -s <实例名> status/tail/watch/send/wait/exec/attach/grep`。实例配置在 `config/<实例名>.conf`，日志在 `logs/<实例名>/`。
