#!/usr/bin/env bash
# 真进程层面的冒烟测试：单测覆盖不到 stdin、退出码和临时文件清理。
# 用法：bash scripts/smoke.sh   （需要先装 moon）
set -uo pipefail

cd "$(dirname "$0")/.."
SAMPLE=sample.diff
BAD=$(mktemp)
printf 'diff --git a/x b/x\n--- a/x\n+++ b/x\n@@ -1,9 +1,1 @@\n只有这一行\n' > "$BAD"
trap 'rm -f "$BAD"' EXIT
fail=0

moon build --target native >/dev/null 2>&1 || { echo "构建失败"; exit 1; }
EXE=$(find _build/native -name 'main.exe' -o -name 'main' -type f | grep -v '\.c$' | head -1)
[ -n "$EXE" ] || { echo "找不到 native 可执行文件"; exit 1; }

check() { # check <说明> <期望退出码> <命令...>
  local label=$1 want=$2
  shift 2
  local out
  out=$("$@" 2>&1)
  local got=$?
  if [ "$got" = "$want" ]; then
    echo "ok   $label"
  else
    echo "FAIL $label：退出码 $got，期望 $want"
    echo "$out" | sed 's/^/       /'
    fail=1
  fi
}

expect_out() { # expect_out <说明> <要包含的子串> <命令...>
  local label=$1 want=$2
  shift 2
  local out
  out=$("$@" 2>&1)
  if printf '%s' "$out" | grep -qF -- "$want"; then
    echo "ok   $label"
  else
    echo "FAIL $label：输出里没有「$want」"
    echo "$out" | sed 's/^/       /'
    fail=1
  fi
}

# 输入方式
expect_out "stdin 走管道"        "3 files changed" sh -c "$EXE < $SAMPLE"
expect_out "单个 - 也表示 stdin"  "3 files changed" sh -c "cat $SAMPLE | $EXE -"
expect_out "多文件按顺序拼接"     "6 files changed" "$EXE" "$SAMPLE" "$SAMPLE"
# 模式和退出码
check "--check 有改动返回 1"     1 "$EXE" --check "$SAMPLE"
check "--stat 返回 0"            0 "$EXE" "$SAMPLE"
check "--json 返回 0"            0 "$EXE" --json "$SAMPLE"
check "--detail 返回 0"          0 "$EXE" -d "$SAMPLE"
check "-h 返回 0"                 0 "$EXE" --help
check "-V 返回 0"                 0 "$EXE" --version
check "未知选项返回 2"           2 "$EXE" --nope
check "解析失败返回 2"           2 "$EXE" bad.diff
check "读不到的文件返回 2"       2 "$EXE" does-not-exist.diff
check "空输入 --check 返回 0"     0 sh -c "printf '' | $EXE --check -"
# 输出内容
expect_out "--stat 摘要"          "src/a.txt |    3 ++-" "$EXE" --stat "$SAMPLE"
expect_out "--detail 带 hunk 头"  "@@ -1,3 +1,4 @@"      "$EXE" --detail "$SAMPLE"
expect_out "--json 有 summary"    '"file_count": 3'      "$EXE" --json "$SAMPLE"
expect_out "--review-prompt 带行号列和输出约定" "LGTM"    "$EXE" --review-prompt "$SAMPLE"
# --review 在没有密钥时不该碰网络，也不该留下临时文件
rm -f .moondiff-review-body.json .moondiff-review-curl.cfg .moondiff-review-response.json
expect_out "--review 缺密钥时给出提示" "MOONDIFF_API_KEY" \
  env -u MOONDIFF_API_KEY -u OPENAI_API_KEY "$EXE" --review "$SAMPLE"
leftovers=$(ls -a | grep '^\.moondiff-review' || true)
if [ -z "$leftovers" ]; then
  echo "ok   没有残留临时文件"
else
  echo "FAIL 残留了临时文件：$leftovers"
  fail=1
fi

[ "$fail" = 0 ] && echo "全部通过" || echo "有失败项"
exit $fail
