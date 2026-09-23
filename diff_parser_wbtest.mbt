// 白盒测试：和解析器同一个包，能直接调用内部函数。
//
// 样例用 `src([...])` 逐行拼，而不是多行原始字符串——这样每一行的
// 行首空格、反斜杠都是显式的，不会被字符串语法吃掉。
//
// 快照内容用 `moon test --update` 生成后需要人工逐条核对，
// 否则等于把当下的错误行为固化成期望值。

///|
fn src(lines : Array[String]) -> String {
  lines.join("\n")
}

///|
fn parse(text : String) -> Diff raise DiffError {
  parse_diff(text)
}

///|
fn parse_err(text : String) -> String {
  try {
    let d = parse_diff(text)
    "no error, got \{d.file_count()} file(s)"
  } catch {
    BadDiff(no, msg) => "line \{no}: \{msg}"
  }
}

///|
test "modified file" {
  let d = parse(
    src([
      "diff --git a/f.txt b/f.txt", "index 1234567..89abcde 100644", "--- a/f.txt",
      "+++ b/f.txt", "@@ -1,3 +1,3 @@", " ctx a", "-gone", "+added", " ctx b",
    ]),
  )
  debug_inspect(
    d,
    content=(
      #|{
      #|  files: [
      #|    {
      #|      old_path: "f.txt",
      #|      new_path: "f.txt",
      #|      status: Modified,
      #|      binary: false,
      #|      old_mode: None,
      #|      new_mode: None,
      #|      hunks: [
      #|        {
      #|          old_start: 1,
      #|          old_count: 3,
      #|          new_start: 1,
      #|          new_count: 3,
      #|          heading: "",
      #|          lines: [
      #|            {
      #|              kind: Context,
      #|              content: "ctx a",
      #|              old_lineno: Some(1),
      #|              new_lineno: Some(1),
      #|            },
      #|            {
      #|              kind: Removed,
      #|              content: "gone",
      #|              old_lineno: Some(2),
      #|              new_lineno: None,
      #|            },
      #|            {
      #|              kind: Added,
      #|              content: "added",
      #|              old_lineno: None,
      #|              new_lineno: Some(2),
      #|            },
      #|            {
      #|              kind: Context,
      #|              content: "ctx b",
      #|              old_lineno: Some(3),
      #|              new_lineno: Some(3),
      #|            },
      #|          ],
      #|          no_newline_old: false,
      #|          no_newline_new: false,
      #|        },
      #|      ],
      #|    },
      #|  ],
      #|}
    ),
  )
}

///|
test "new file" {
  let d = parse(
    src([
      "diff --git a/new.txt b/new.txt", "new file mode 100644", "index 0000000..1234567",
      "--- /dev/null", "+++ b/new.txt", "@@ -0,0 +1,2 @@", "+hello", "+world",
    ]),
  )
  debug_inspect(
    d.files[0].status,
    content=(
      #|NewFile
    ),
  )
  debug_inspect(
    d.files[0].old_path,
    content=(
      #|"/dev/null"
    ),
  )
  debug_inspect(
    d.added_count(),
    content=(
      #|2
    ),
  )
}

///|
test "deleted file" {
  let d = parse(
    src([
      "diff --git a/gone.txt b/gone.txt", "deleted file mode 100644", "--- a/gone.txt",
      "+++ /dev/null", "@@ -1,1 +0,0 @@", "-bye",
    ]),
  )
  debug_inspect(
    d.files[0].status,
    content=(
      #|Deleted
    ),
  )
  debug_inspect(
    d.files[0].display_path(),
    content=(
      #|"gone.txt"
    ),
  )
  debug_inspect(
    d.removed_count(),
    content=(
      #|1
    ),
  )
}

///|
test "rename with mode change" {
  let d = parse(
    src([
      "diff --git a/old.txt b/new.txt", "similarity index 87%", "rename from old.txt",
      "rename to new.txt", "old mode 100644", "new mode 100755", "index abc1234..def5678",
      "@@ -1,2 +1,2 @@", " keep", "-x", "+y",
    ]),
  )
  debug_inspect(
    d.files[0].status,
    content=(
      #|Renamed
    ),
  )
  debug_inspect(
    d.files[0].old_path,
    content=(
      #|"old.txt"
    ),
  )
  debug_inspect(
    d.files[0].new_path,
    content=(
      #|"new.txt"
    ),
  )
  debug_inspect(
    d.files[0].new_mode,
    content=(
      #|Some("100755")
    ),
  )
}

///|
test "binary file" {
  let d = parse(
    src([
      "diff --git a/logo.png b/logo.png", "index 1111111..2222222 100644", "Binary files a/logo.png and b/logo.png differ",
    ]),
  )
  debug_inspect(
    d.files[0].binary,
    content=(
      #|true
    ),
  )
  debug_inspect(
    d.files[0].hunks.length(),
    content=(
      #|0
    ),
  )
  debug_inspect(
    d.files[0].display_path(),
    content=(
      #|"logo.png"
    ),
  )
}

///|
test "mode only change has no hunks" {
  let d = parse(
    src([
      "diff --git a/script.sh b/script.sh", "old mode 100644", "new mode 100755",
    ]),
  )
  debug_inspect(
    d.files[0].status,
    content=(
      #|ModeOnly
    ),
  )
}

///|
test "no newline marker on added line" {
  let d = parse(
    src([
      "--- a/f.txt", "+++ b/f.txt", "@@ -1,1 +1,1 @@", "-old", "+new", "\\ No newline at end of file",
    ]),
  )
  let h = d.files[0].hunks[0]
  debug_inspect(
    h.no_newline_old,
    content=(
      #|false
    ),
  )
  debug_inspect(
    h.no_newline_new,
    content=(
      #|true
    ),
  )
}

///|
test "no newline marker on context line" {
  let d = parse(
    src([
      "--- a/f.txt", "+++ b/f.txt", "@@ -1,2 +1,2 @@", " same", " ctx", "\\ No newline at end of file",
    ]),
  )
  let h = d.files[0].hunks[0]
  debug_inspect(
    h.no_newline_old,
    content=(
      #|true
    ),
  )
  debug_inspect(
    h.no_newline_new,
    content=(
      #|true
    ),
  )
}

///|
test "removed line that looks like a file header" {
  // diff 里的 `--- dangerous` 是一行被删掉的 `-- dangerous`，
  // 不是文件头。只有靠 @@ 声明的行数驱动才不会认错。
  let d = parse(
    src([
      "diff --git a/a.txt b/a.txt", "--- a/a.txt", "+++ b/a.txt", "@@ -1,3 +1,2 @@",
      " line one", "--- dangerous", " line three",
    ]),
  )
  debug_inspect(
    d.file_count(),
    content=(
      #|1
    ),
  )
  let l = d.files[0].hunks[0].lines[1]
  debug_inspect(
    l.kind,
    content=(
      #|Removed
    ),
  )
  debug_inspect(
    l.content,
    content=(
      #|"-- dangerous"
    ),
  )
}

///|
test "omitted counts mean one line" {
  let h = parse_hunk_header("@@ -7 +7 @@ int main()", 1)
  debug_inspect(
    h,
    content=(
      #|{
      #|  old_start: 7,
      #|  old_count: 1,
      #|  new_start: 7,
      #|  new_count: 1,
      #|  heading: "int main()",
      #|}
    ),
  )
}

///|
test "zero count is pure insert after a line" {
  let d = parse(
    src(["--- a/f.txt", "+++ b/f.txt", "@@ -5,0 +6,2 @@", "+first", "+second"]),
  )
  let h = d.files[0].hunks[0]
  debug_inspect(
    h.old_count,
    content=(
      #|0
    ),
  )
  debug_inspect(
    h.lines.length(),
    content=(
      #|2
    ),
  )
  debug_inspect(
    h.lines[0].new_lineno,
    content=(
      #|Some(6)
    ),
  )
}

///|
test "stray lines around the diff are skipped" {
  let d = parse(
    src([
      "commit 000111222333", "Author: someone", "", "    a commit message", "", "diff --git a/f.txt b/f.txt",
      "--- a/f.txt", "+++ b/f.txt", "@@ -1,1 +1,1 @@", "-a", "+b",
    ]),
  )
  debug_inspect(
    d.file_count(),
    content=(
      #|1
    ),
  )
  debug_inspect(
    d.hunk_count(),
    content=(
      #|1
    ),
  )
}

///|
test "empty text parses to zero files" {
  let d = parse("")
  assert_true(d.is_empty())
  assert_true(d.file_count() == 0)
}

///|
test "split_lines normalizes line endings" {
  debug_inspect(
    split_lines("a\r\nb\rc\n"),
    content=(
      #|["a", "b", "c"]
    ),
  )
  debug_inspect(
    split_lines("a\n"),
    content=(
      #|["a"]
    ),
  )
  debug_inspect(
    split_lines(""),
    content=(
      #|[]
    ),
  )
}

///|
test "hunk count mismatch is an error" {
  debug_inspect(
    parse_err(
      src(["--- a/f.txt", "+++ b/f.txt", "@@ -1,5 +1,5 @@", " only", " two"]),
    ),
    content=(
      #|"line 3: hunk 声明的行数还没读完就到了文本结尾"
    ),
  )
}

///|
test "truncated hunk at end of text is an error" {
  debug_inspect(
    parse_err(src(["--- a/f.txt", "+++ b/f.txt", "@@ -1,3 +1,3 @@", " one"])),
    content=(
      #|"line 3: hunk 声明的行数还没读完就到了文本结尾"
    ),
  )
}

///|
test "bad hunk header is an error" {
  debug_inspect(
    parse_err("@@ +1,2 @@ x"),
    content=(
      #|"line 1: hunk 头缺少 `-` 起始行号"
    ),
  )
  debug_inspect(
    parse_err("@@ -a,2 +1,2 @@"),
    content=(
      #|"line 1: hunk 头的旧文件行号不是数字"
    ),
  )
  debug_inspect(
    parse_err("--- a/f.txt\n+++ b/f.txt\n@@@ nope"),
    content=(
      #|"line 3: hunk 头缺少 `-` 起始行号"
    ),
  )
}

///|
test "clean_path handles git quoting and prefixes" {
  debug_inspect(
    clean_path("a/dir/f.c"),
    content=(
      #|"dir/f.c"
    ),
  )
  debug_inspect(
    clean_path("b/dir/f.c"),
    content=(
      #|"dir/f.c"
    ),
  )
  debug_inspect(
    clean_path("/dev/null"),
    content=(
      #|"/dev/null"
    ),
  )
  debug_inspect(
    clean_path("\"a/my file.txt\""),
    content=(
      #|"my file.txt"
    ),
  )
  debug_inspect(
    clean_path("a/f.c\t2026-01-01 10:00:00 +0800"),
    content=(
      #|"f.c"
    ),
  )
}

///|
test "read_two_paths splits quoted paths with spaces" {
  debug_inspect(
    read_two_paths("a/one.txt b/two.txt"),
    content=(
      #|("one.txt", "two.txt")
    ),
  )
  debug_inspect(
    read_two_paths("\"a/with space.txt\" \"b/other name.txt\""),
    content=(
      #|("with space.txt", "other name.txt")
    ),
  )
}

///|
test "side text reconstruction and aggregates" {
  let d = parse(
    src([
      "diff --git a/a.txt b/a.txt", "--- a/a.txt", "+++ b/a.txt", "@@ -1,3 +1,4 @@",
      " keep", "-drop", "+add1", "+add2", " tail",
    ]),
  )
  let f = d.files[0]
  debug_inspect(
    f.hunks[0].old_side_text(),
    content=(
      #|"keep\ndrop\ntail"
    ),
  )
  debug_inspect(
    f.hunks[0].new_side_text(),
    content=(
      #|"keep\nadd1\nadd2\ntail"
    ),
  )
  debug_inspect(
    f.changed_line_count(),
    content=(
      #|3
    ),
  )
  debug_inspect(
    d.touched_paths(),
    content=(
      #|["a.txt"]
    ),
  )
  debug_inspect(
    d.added_count(),
    content=(
      #|2
    ),
  )
  debug_inspect(
    d.removed_count(),
    content=(
      #|1
    ),
  )
}

///|
test "multiple files in one diff" {
  let d = parse(
    src([
      "diff --git a/one.txt b/one.txt", "--- a/one.txt", "+++ b/one.txt", "@@ -1,1 +1,1 @@",
      "-1", "+11", "diff --git a/two.txt b/two.txt", "--- a/two.txt", "+++ b/two.txt",
      "@@ -1,1 +1,1 @@", "-2", "+22", "@@ -9,1 +9,1 @@", "-9", "+99",
    ]),
  )
  debug_inspect(
    d.file_count(),
    content=(
      #|2
    ),
  )
  debug_inspect(
    d.hunk_count(),
    content=(
      #|3
    ),
  )
  debug_inspect(
    d.files[1].hunks.length(),
    content=(
      #|2
    ),
  )
  debug_inspect(
    d.files[1].hunks[1].lines[0].old_lineno,
    content=(
      #|Some(9)
    ),
  )
}

///|
test "line numbers advance per side" {
  let d = parse(
    src([
      "--- a/f.txt", "+++ b/f.txt", "@@ -10,4 +20,5 @@", " c1", "-r1", "+a1", "+a2",
      " c2", " c3",
    ]),
  )
  debug_inspect(
    d.files[0].hunks[0].lines.map(fn(l) {
      "\{l.kind.to_repr()} old=\{l.old_lineno.unwrap_or(-1)} new=\{l.new_lineno.unwrap_or(-1)}"
    }),
    content=(
      #|[
      #|  "Context old=10 new=20",
      #|  "Removed old=11 new=-1",
      #|  "Added old=-1 new=21",
      #|  "Added old=-1 new=22",
      #|  "Context old=12 new=23",
      #|  "Context old=13 new=24",
      #|]
    ),
  )
}
