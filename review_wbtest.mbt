// 评审提示词的白盒测试。重点盯两列行号：新增行只有改动后行号，
// 删除行只有改动前行号，模型靠这两列才能把意见指到准确的行。
// prompt_rules 那一大段不逐字快照，只断言它出现在开头。

///|
fn one_hunk() -> Hunk raise DiffError {
  let d = parse(
    src([
      "diff --git a/f.txt b/f.txt", "--- a/f.txt", "+++ b/f.txt", "@@ -1,2 +1,3 @@",
      " keep", "-gone", "+here", "+more",
    ]),
  )
  d.files[0].hunks[0]
}

///|
test "hunk_text puts both line numbers in front of every line" {
  debug_inspect(
    hunk_text(one_hunk()),
    content=(
      #|"@@ -1,2 +1,3 @@\n   1   1  keep\n   2     -gone\n       2 +here\n       3 +more"
    ),
  )
}

///|
test "file_text labels the path, status and counts" {
  let d = parse(
    src([
      "diff --git a/f.txt b/f.txt", "--- a/f.txt", "+++ b/f.txt", "@@ -1,1 +1,1 @@",
      "-a", "+b",
    ]),
  )
  debug_inspect(
    file_text(d.files[0]),
    content=(
      #|"### f.txt (modified, +1 -1)\n@@ -1,1 +1,1 @@\n   1     -a\n       1 +b"
    ),
  )
}

///|
test "file_text says so when there is nothing to read" {
  let binary = parse(
    src([
      "diff --git a/logo.png b/logo.png", "Binary files a/logo.png and b/logo.png differ",
    ]),
  )
  let renamed = parse(
    src([
      "diff --git a/old.txt b/new.txt", "rename from old.txt", "rename to new.txt",
    ]),
  )
  debug_inspect(
    [file_text(binary.files[0]), file_text(renamed.files[0])],
    content=(
      #|[
      #|  "### logo.png (modified, +0 -0)\n(二进制文件，没有可比对的文本)",
      #|  "### new.txt (renamed, +0 -0)\n(没有内容改动)",
      #|]
    ),
  )
}

///|
test "review_prompt starts with the rules and then lists each file" {
  let d = parse(
    src([
      "diff --git a/a.txt b/a.txt", "--- a/a.txt", "+++ b/a.txt", "@@ -1,1 +1,1 @@",
      "-a", "+b", "diff --git a/b.txt b/b.txt", "--- a/b.txt", "+++ b/b.txt", "@@ -1,1 +1,1 @@",
      "-c", "+d",
    ]),
  )
  let p = d.review_prompt()
  assert_true(p.has_prefix(prompt_rules))
  assert_true(p.contains("### a.txt (modified, +1 -1)"))
  assert_true(p.contains("### b.txt (modified, +1 -1)"))
}
