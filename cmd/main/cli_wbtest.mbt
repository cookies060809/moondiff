// 命令行参数解析的白盒测试。只测 parse_args 和错误文案，
// 不碰 stdin——那部分要在真进程里测，放在脚本里。

///|
fn run_with(mode : Mode, paths : Array[String]) -> Parsed {
  Run({ mode, paths, })
}

///|
test "no arguments means read stdin in stat mode" {
  assert_eq(parse_args([]), run_with(Stat, []))
}

///|
test "each output flag picks its mode" {
  assert_eq(parse_args(["--stat"]), run_with(Stat, []))
  assert_eq(parse_args(["-d"]), run_with(Detail, []))
  assert_eq(parse_args(["--detail"]), run_with(Detail, []))
  assert_eq(parse_args(["--check"]), run_with(Check, []))
}

///|
test "the last mode flag wins" {
  assert_eq(parse_args(["--detail", "--check"]), run_with(Check, []))
}

///|
test "bare words and dash are collected as input sources" {
  assert_eq(parse_args(["a.diff"]), run_with(Stat, ["a.diff"]))
  assert_eq(parse_args(["-", "b.diff"]), run_with(Stat, ["-", "b.diff"]))
  assert_eq(parse_args(["x", "-", "y"]), run_with(Stat, ["x", "-", "y"]))
}

///|
test "double dash turns the rest into paths" {
  assert_eq(parse_args(["--", "--stat"]), run_with(Stat, ["--stat"]))
  assert_eq(parse_args(["--detail", "--", "-d"]), run_with(Detail, ["-d"]))
}

///|
test "unknown options are rejected" {
  assert_eq(parse_args(["--nope"]), UsageError("unknown option --nope"))
}

///|
test "help and version short-circuit, but not before an error" {
  assert_eq(parse_args(["x", "-h"]), ShowHelp)
  assert_eq(parse_args(["x", "--version"]), ShowVersion)
  assert_eq(parse_args(["--nope", "-h"]), UsageError("unknown option --nope"))
}

///|
test "io errors carry the offending line number" {
  assert_eq(CannotRead("gone.txt").message(), "cannot read gone.txt")
  assert_eq(
    BadLine(7, "hunk 声明的行数还没读完就到了文本结尾").message(),
    "line 7: hunk 声明的行数还没读完就到了文本结尾",
  )
}
