#!/usr/bin/env python3
"""jsonl2log.py —— 把 *.jsonl 渲染成 *.log（仅用 Python 标准库）。

输出格式与 seriald 写出的 .log 一致：

    [2026-10-20 00:00:00.313] [RX] 正文
    [2026-10-20 00:00:00.700] [TX:human] echo "nihk"
    [2026-10-20 00:00:00.702] [EVENT] SERIALD_START instance=...

清洗规则（与 seriald 写 log 时保持一致）：

    - 去掉 CSI / OSC / 字符集切换等 ANSI 序列、BEL；
    - \\r 只保留最后一段（模拟终端"回到行首覆盖"的效果）。

用法：

    python3 jsonl2log.py                # 处理脚本所在目录
    python3 jsonl2log.py w14            # 处理指定目录
    python3 jsonl2log.py w14 --force    # 覆盖已有 .log
    python3 jsonl2log.py w14 --dry-run  # 只报告，不写文件
"""

import argparse
import json
import re
import sys
from datetime import datetime
from pathlib import Path

CSI_RE = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]")
OSC_RE = re.compile(r"\x1b\][^\x07]*(?:\x07|\x1b\\)")
CHARSET_RE = re.compile(r"\x1b[()][A-Za-z0-9]")
ESC_OTHER_RE = re.compile(r"\x1b[@-Z\\-_]")


def clean_text(text: str) -> str:
    """去掉控制序列；\\r 按行处理，只保留该行最后一段。"""
    text = OSC_RE.sub("", text)
    text = CSI_RE.sub("", text)
    text = CHARSET_RE.sub("", text)
    text = ESC_OTHER_RE.sub("", text)
    text = text.replace("\x07", "")

    lines = []
    for line in text.split("\n"):
        line = line.rstrip("\r")
        if "\r" in line:
            line = line.split("\r")[-1]
        lines.append(line)

    return "\n".join(lines)


def format_ts(raw: str) -> str:
    """ISO 时间 -> 本地墙钟 'YYYY-mm-dd HH:MM:SS.mmm'。"""
    try:
        dt = datetime.fromisoformat(raw)
        if dt.tzinfo is not None:
            dt = dt.astimezone()
        return dt.strftime("%Y-%m-%d %H:%M:%S.%f")[:-3]
    except ValueError:
        return raw


def tag_of(record: dict) -> str:
    kind = record.get("type", "")
    if kind == "rx":
        return "RX"
    if kind == "tx":
        return f"TX:{record.get('actor') or 'unknown'}"
    return "EVENT"


def render_record(record: dict) -> list:
    """一条 jsonl 记录 -> 若干行 .log 文本。"""
    ts = format_ts(record.get("ts", ""))
    tag = tag_of(record)

    text = record.get("data") or ""
    if record.get("event"):
        text = record["event"] + (f" {text}" if text else "")

    text = clean_text(text)
    parts = text.split("\n")

    return [
        f"[{ts}] [{tag}] {part}"
        for i, part in enumerate(parts)
        if part != "" or len(parts) == 1
    ]


def render_file(src: Path, dst: Path, dry_run: bool) -> tuple:
    """返回 (行数, 跳过行数, 字节数)。"""
    lines = 0
    bad = 0
    size = 0
    out = []

    with src.open("r", encoding="utf-8", errors="replace") as f:
        for raw in f:
            raw = raw.strip()
            if not raw:
                continue
            try:
                record = json.loads(raw)
            except json.JSONDecodeError:
                bad += 1
                continue

            for line in render_record(record):
                out.append(line + "\n")
                size += len(line.encode("utf-8")) + 1
                lines += 1

    if not dry_run:
        dst.write_text("".join(out), encoding="utf-8")

    return lines, bad, size


def main() -> int:
    ap = argparse.ArgumentParser(
        description="把 *.jsonl 渲染成 *.log（仅标准库）",
    )
    ap.add_argument(
        "directory",
        nargs="?",
        default=None,
        help="目标目录（默认脚本所在目录）",
    )
    ap.add_argument("--force", action="store_true", help="覆盖已存在的 .log")
    ap.add_argument("--dry-run", action="store_true", help="只报告，不写文件")
    args = ap.parse_args()

    base = Path(args.directory) if args.directory else Path(__file__).resolve().parent
    if not base.is_dir():
        print(f"目录不存在: {base}", file=sys.stderr)
        return 2

    sources = sorted(base.glob("*.jsonl"))
    if not sources:
        print(f"{base}: 没有 *.jsonl")
        return 0

    done = skipped = total_lines = total_bad = total_bytes = 0

    for src in sources:
        dst = src.with_suffix(".log")

        if dst.exists() and not args.force and dst.stat().st_mtime >= src.stat().st_mtime:
            skipped += 1
            continue

        lines, bad, size = render_file(src, dst, args.dry_run)
        done += 1
        total_lines += lines
        total_bad += bad
        total_bytes += size

        action = "将生成" if args.dry_run else "已生成"
        print(
            f"{action}: {dst.name}  "
            f"{lines} 行, {size / 1024:.1f} KB"
            + (f", 跳过 {bad} 行坏数据" if bad else "")
        )

    print(
        f"\n汇总: 生成 {done} 个, 跳过 {skipped} 个, "
        f"共 {total_lines} 行, {total_bytes / 1024 / 1024:.1f} MB"
        + (f", 坏数据 {total_bad} 行" if total_bad else "")
    )
    if args.dry_run:
        print("（--dry-run：未写入任何文件）")

    return 0


if __name__ == "__main__":
    sys.exit(main())
