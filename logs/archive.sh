#!/bin/bash
# archive.sh —— 按"完整 ISO 周"归档串口日志
#
# 规则：
#   - 只归档已经结束的周（该周周日 < 今天）；本周和当天文件一律不动
#   - 每个实例目录单独打包：<实例>/archive/<YYYY-Www>.jsonl.tar.gz
#   - 只打包 .jsonl；包内附 manifest（日期/字节/行数）
#   - 流程：打包 -> tar -tzf 校验 -> 写 archive/MD5.txt -> 删除该周的 .jsonl 与 .log
#   - 任何一步失败即停止，不删除任何文件
#
# 默认只演练（dry-run）；加 --apply 才真正执行。
#
# 用法：
#   bash archive.sh                           # 所有实例，列出将归档的周
#   bash archive.sh --apply                   # 真正执行
#   bash archive.sh --instance w14 --apply    # 只处理 w14
#   bash archive.sh --week 2026-W42 --apply   # 只处理指定周（补打）
#
# 自动触发（可选，未启用）：
#   ~/.config/systemd/user/serial-archive.service + .timer
#   [Timer]
#   OnCalendar=Mon *-*-* 00:10:00
#   Persistent=true
#   ExecStart=/bin/bash %h/work/serial-logs/logs/archive.sh --apply

set -uo pipefail

BASE_DIR=$(cd "$(dirname "$0")" && pwd)
TODAY=$(date +%F)
APPLY=0
ONLY_INSTANCE=""
ONLY_WEEK=""

usage() {
    sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
}

log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*"; }

fmt_size() {
    local b=$1
    if [ "$b" -ge 1048576 ]; then
        echo "$(( b / 1048576 )) MB"
    elif [ "$b" -ge 1024 ]; then
        echo "$(( b / 1024 )) KB"
    else
        echo "$b B"
    fi
}

while [ $# -gt 0 ]; do
    case "$1" in
        --apply)    APPLY=1; shift ;;
        --instance) ONLY_INSTANCE=${2:?缺少实例名}; shift 2 ;;
        --week)     ONLY_WEEK=${2:?缺少周编号}; shift 2 ;;
        -h|--help)  usage; exit 0 ;;
        *)          echo "未知参数: $1" >&2; usage; exit 1 ;;
    esac
done

week_of_date() { date -d "$1" +%G-W%V 2>/dev/null; }
sunday_of_date() {
    local wd
    wd=$(date -d "$1" +%u) || return 1
    date -d "$1 +$(( 7 - wd )) days" +%F
}
monday_of_date() {
    local wd
    wd=$(date -d "$1" +%u) || return 1
    date -d "$1 -$(( wd - 1 )) days" +%F
}

process_week() {
    local dir=$1 week=$2
    shift 2
    local files=("$@")

    local first_date monday sunday archive_dir archive
    first_date=${files[0]%.jsonl}
    monday=$(monday_of_date "$first_date") || { log "  跳过 $week（日期无法解析）"; return 0; }
    sunday=$(sunday_of_date "$first_date") || { log "  跳过 $week（日期无法解析）"; return 0; }

    if [ ! "$sunday" \< "$TODAY" ]; then
        log "  跳过 $week（未结束，周日 $sunday）"
        return 0
    fi

    archive_dir="$dir/archive"
    archive="$archive_dir/$week.jsonl.tar.gz"

    local bytes=0 f
    for f in "${files[@]}"; do
        bytes=$(( bytes + $(stat -c %s "$dir/$f") ))
    done

    if [ -e "$archive" ]; then
        log "  $week 已归档，跳过（$(basename "$archive")）"
        return 0
    fi

    log "  $week：${#files[@]} 天，$(fmt_size "$bytes") -> $(basename "$archive")"

    if [ "$APPLY" -ne 1 ]; then
        for f in "${files[@]}"; do
            log "    - $f"
        done
        return 0
    fi

    mkdir -p "$archive_dir"

    local manifest="$dir/$week.manifest.txt"
    {
        echo "# week      : $week"
        echo "# range     : $monday .. $sunday"
        echo "# generated : $(date '+%F %T')"
        printf '# %-14s %10s %8s\n' "file" "bytes" "lines"
        for f in "${files[@]}"; do
            printf '  %-14s %10s %8s\n' \
                "$f" \
                "$(stat -c %s "$dir/$f")" \
                "$(wc -l < "$dir/$f")"
        done
    } > "$manifest"

    local tmp="$archive_dir/.$week.tmp.tar.gz"
    if ! tar -czf "$tmp" -C "$dir" "${files[@]}" "$(basename "$manifest")"; then
        log "  打包失败，保留原文件"
        rm -f "$tmp" "$manifest"
        return 1
    fi

    local expect got
    expect=$(( ${#files[@]} + 1 ))
    got=$(tar -tzf "$tmp" | wc -l)
    if [ "$got" -ne "$expect" ]; then
        log "  校验失败（条目 $got != $expect），保留原文件"
        rm -f "$tmp" "$manifest"
        return 1
    fi

    mv "$tmp" "$archive"
    ( cd "$archive_dir" && md5sum "$(basename "$archive")" >> MD5.txt )
    rm -f "$manifest"

    for f in "${files[@]}"; do
        rm -f "$dir/$f" "$dir/${f%.jsonl}.log"
    done

    log "  完成：$(basename "$archive") $(du -h "$archive" | cut -f1)，删除 ${#files[@]} 天的原文件"
    return 0
}

total_weeks=0
failed=0

for dir in "$BASE_DIR"/*/; do
    dir=${dir%/}
    [ -d "$dir" ] || continue

    name=$(basename "$dir")
    [ "$name" = "archive" ] && continue
    if [ -n "$ONLY_INSTANCE" ] && [ "$name" != "$ONLY_INSTANCE" ]; then
        continue
    fi

    jsonls=("$dir"/*.jsonl)
    [ -e "${jsonls[0]}" ] || continue

    unset weeks
    declare -A weeks=()

    for f in "${jsonls[@]}"; do
        [ -e "$f" ] || continue
        d=$(basename "$f" .jsonl)
        w=$(week_of_date "$d")
        if [ -z "$w" ]; then
            log "$name: 无法解析日期，跳过 $(basename "$f")"
            continue
        fi
        weeks[$w]="${weeks[$w]:-} $d.jsonl"
    done

    if [ ${#weeks[@]} -eq 0 ]; then
        continue
    fi

    log "实例 $name：${#weeks[@]} 个周"
    for w in $(printf '%s\n' "${!weeks[@]}" | sort); do
        if [ -n "$ONLY_WEEK" ] && [ "$w" != "$ONLY_WEEK" ]; then
            continue
        fi
        read -r -a flist <<< "${weeks[$w]}"
        total_weeks=$(( total_weeks + 1 ))
        process_week "$dir" "$w" "${flist[@]}" || failed=$(( failed + 1 ))
    done
done

if [ "$total_weeks" -eq 0 ]; then
    log "没有可归档的完整周"
else
    if [ "$APPLY" -eq 1 ]; then
        log "结束：处理 $total_weeks 个周，失败 $failed 个"
    else
        log "演练结束：$total_weeks 个周待归档（加 --apply 执行）"
    fi
fi

[ "$failed" -eq 0 ]
