// JSON 输出的白盒测试。快照用 `moon test --update` 生成之后逐条核对过，
// 尤其是行号为 null 的那几处——新增行不该有改动前行号，删除行不该有改动后行号。

///|
test "format_json carries the summary and both line numbers" {
  let d = parse(
    src([
      "diff --git a/f.txt b/f.txt", "--- a/f.txt", "+++ b/f.txt", "@@ -1,2 +1,2 @@",
      " keep", "-gone", "+here",
    ]),
  )
  debug_inspect(
    d.format_json(),
    content=(
      #|"{\n  \"summary\": {\n    \"file_count\": 1,\n    \"hunk_count\": 1,\n    \"added\": 1,\n    \"removed\": 1\n  },\n  \"files\": [\n    {\n      \"old_path\": \"f.txt\",\n      \"new_path\": \"f.txt\",\n      \"path\": \"f.txt\",\n      \"status\": \"modified\",\n      \"binary\": false,\n      \"old_mode\": null,\n      \"new_mode\": null,\n      \"added\": 1,\n      \"removed\": 1,\n      \"hunks\": [\n        {\n          \"old_start\": 1,\n          \"old_count\": 2,\n          \"new_start\": 1,\n          \"new_count\": 2,\n          \"heading\": \"\",\n          \"no_newline_old\": false,\n          \"no_newline_new\": false,\n          \"lines\": [\n            {\n              \"kind\": \"context\",\n              \"old_line\": 1,\n              \"new_line\": 1,\n              \"content\": \"keep\"\n            },\n            {\n              \"kind\": \"removed\",\n              \"old_line\": 2,\n              \"new_line\": null,\n              \"content\": \"gone\"\n            },\n            {\n              \"kind\": \"added\",\n              \"old_line\": null,\n              \"new_line\": 2,\n              \"content\": \"here\"\n            }\n          ]\n        }\n      ]\n    }\n  ]\n}"
    ),
  )
}

///|
test "format_json of an empty diff" {
  debug_inspect(
    Diff::empty().format_json(),
    content=(
      #|"{\n  \"summary\": {\n    \"file_count\": 0,\n    \"hunk_count\": 0,\n    \"added\": 0,\n    \"removed\": 0\n  },\n  \"files\": []\n}"
    ),
  )
}

///|
test "binary files show up in JSON with zero counts" {
  let d = parse(
    src([
      "diff --git a/logo.png b/logo.png", "new file mode 100644", "Binary files /dev/null and b/logo.png differ",
    ]),
  )
  debug_inspect(
    d.format_json(),
    content=(
      #|"{\n  \"summary\": {\n    \"file_count\": 1,\n    \"hunk_count\": 0,\n    \"added\": 0,\n    \"removed\": 0\n  },\n  \"files\": [\n    {\n      \"old_path\": \"/dev/null\",\n      \"new_path\": \"logo.png\",\n      \"path\": \"logo.png\",\n      \"status\": \"new file\",\n      \"binary\": true,\n      \"old_mode\": null,\n      \"new_mode\": \"100644\",\n      \"added\": 0,\n      \"removed\": 0,\n      \"hunks\": []\n    }\n  ]\n}"
    ),
  )
}
