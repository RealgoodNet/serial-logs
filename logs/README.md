# logs/ —— 串口实例数据与日志工具

每个子目录 = 一个串口实例的日志数据（实例名与 `../config/<名字>.conf` 对应）。
根目录下还有两个脚本：`jsonl2log.py`（渲染）和 `archive.sh`（按周归档）。

## 目录结构

```text
logs/
├── README.md              # 本文件
├── jsonl2log.py           # 把 *.jsonl 渲染成 *.log（仅标准库）
├── archive.sh             # 按完整 ISO 周归档（默认演练）
├── atk1126b/
│   ├── 2026-10-20.log     # 人读日志（已清洗）
│   ├── 2026-10-20.jsonl   # 原始记录（唯一事实来源）
│   ├── latest.log -> 2026-10-20.log
│   └── archive/
│       ├── 2026-W42.jsonl.tar.gz
│       └── MD5.txt
├── s41-5-18/
├── rv1126b/
└── w14/
```

## 两种文件的分工

| 文件 | 内容 | 谁在用 |
| --- | --- | --- |
| `YYYY-MM-DD.log` | **清洗过**：去掉 ANSI/OSC/BEL，`\r` 按行只保留最后一段 | 人：`serialctl tail/grep`、VS Code 直接打开 |
| `YYYY-MM-DD.jsonl` | **原始**：一条记录 = 一次串口读写，`\u001b` 等控制字符完整保留 | 机器：`jq`、脚本、重建 `.log` |

`.log` 是渲染物，删了可以随时从 `.jsonl` 重建；`.jsonl` 不要手工修改。

## 常见操作

看今天：

```bash
serialctl -s atk1126b tail 100
serialctl -s atk1126b grep -i 'error|fail'
```

重建某个实例的全部 `.log`：

```bash
python3 ~/work/serial-logs/logs/jsonl2log.py atk1126b
```

看归档里的某一周：

```bash
cd ~/work/serial-logs/logs/atk1126b/archive
tar -tzf 2026-W42.jsonl.tar.gz              # 先看清单
mkdir -p /tmp/w42 && tar -xzf 2026-W42.jsonl.tar.gz -C /tmp/w42
python3 ~/work/serial-logs/logs/jsonl2log.py /tmp/w42
less /tmp/w42/2026-10-12.log
```

## 归档：按完整 ISO 周

```bash
cd ~/work/serial-logs/logs

bash archive.sh                                  # 演练：只列出将做什么
bash archive.sh --apply                          # 真正执行
bash archive.sh --instance w14 --apply           # 只处理某个实例
bash archive.sh --week 2026-W42 --apply          # 补打指定周
```

规则：

1. 只归档**已经结束的完整周**（该周周日 < 今天），本周与当天文件不动；
2. 每个实例单独打包：`<实例>/archive/<YYYY-Www>.jsonl.tar.gz`；
3. 包内只有 `.jsonl` + 一份 `manifest`（日期/字节/行数）；
4. 流程固定：打包 → `tar -tzf` 校验 → 写 `archive/MD5.txt` → 删该周的 `.jsonl` 与 `.log`；
5. 任一步失败即停止，不删除任何文件；
6. 默认演练，必须显式 `--apply` 才动文件。

校验归档：

```bash
cd ~/work/serial-logs/logs/atk1126b/archive
md5sum -c MD5.txt
```

## 磁盘与保留

- 配置项 `retention_days`（默认 30）在服务启动时删除超期的 `*.log` / `*.jsonl`；
- `archive/` 下的包不参与自动清理，需要自己管理；
- 体积参考：`.jsonl` 压缩比约 15 倍（高度重复的日志可到 80 倍），归档后不再保留 `.log`。

## 不要做

- 不要手工编辑 `.jsonl`（它是重建 `.log` 的唯一来源）；
- 不要删除 `latest.log`，它是软链，重建当天日志时会自动恢复；
- 不要把 `jsonl2log.py` / `archive.sh` 移出本目录（`archive.sh` 以自身所在目录为根）；
- 不要在归档脚本运行时手工移动 `<实例>/` 下的日期文件。

## 常见疑问

**设备时间和主机时间不一致**：`.log` 前缀是我们接收的时间；正文里设备自己打的
`[2026/10/20/00:00:30:435]` 是设备时钟，部分板子没有 RTC 或未校时，两者可能差几秒到几年。

**一条消息被拆成多行**：`.log` 按换行切分并逐行加前缀；`.jsonl` 保持"一次 read 一条记录"。

**渲染时提示跳过坏数据**：`.jsonl` 末尾可能有一条写了一半的记录（服务被杀），跳过即可。

**为什么 `.log` 有时比 `.jsonl` 还大**：`.log` 每行都带 `[时间] [标签]` 前缀，多行消息会重复前缀。
