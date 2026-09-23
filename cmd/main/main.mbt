/// 命令行层：解析参数、取输入、交给解析器、按模式输出、决定退出码。
///
/// 退出码约定和大多数 Unix 工具一致：
///   0 正常（--check 时表示这份 diff 干净）
///   1 --check 下发现了改动
///   2 用法错误、读不到输入、或者 diff 本身解析失败

///|
enum Mode {
  Stat
  Detail
  Check
}

///|
struct Flags {
  mode : Mode
  paths : Array[String]
}

///|
enum Parsed {
  ShowHelp
  ShowVersion
  Run(Flags)
  UsageError(String)
}

///|
let version : String = "0.1.0"

///|
fn print_help() -> Unit {
  [
    "moondiff \{version} —— 解析 unified diff",
    "",
    "用法: moondiff [选项] [文件 ...]",
    "",
    "不给文件、或者给 `-` 时从标准输入读。多个文件的内容会按顺序拼起来。",
    "",
    "选项:",
    "  --stat          每个文件一行变更量（默认）",
    "  --detail, -d    逐文件打印状态、hunk 头和每一行",
    "  --check         只校验能不能解析，不输出内容",
    "  -h, --help      显示这份帮助",
    "  -V, --version   显示版本",
    "",
    "退出码: 0 成功 / 1 --check 发现有改动 / 2 用法或解析错误",
  ].join("\n")
  |> println
}

///|
fn parse_args(argv : Array[String]) -> Parsed {
  let mut mode : Mode = Stat
  let paths : Array[String] = []
  let mut i = 0
  while i < argv.length() {
    let a = argv[i]
    i = i + 1
    if a == "--" {
      while i < argv.length() {
        paths.push(argv[i])
        i = i + 1
      }
    } else if a == "-h" || a == "--help" {
      return ShowHelp
    } else if a == "-V" || a == "--version" {
      return ShowVersion
    } else if a == "--stat" {
      mode = Stat
    } else if a == "-d" || a == "--detail" {
      mode = Detail
    } else if a == "--check" {
      mode = Check
    } else if a == "-" {
      paths.push("-")
    } else if a.has_prefix("-") {
      return UsageError("unknown option \{a}")
    } else {
      paths.push(a)
    }
  }
  Run({ mode, paths, })
}

///|
/// `-` 表示 stdin，其余当文件路径。空列表等价于只读 stdin。
fn read_all(paths : Array[String]) -> String raise IoError {
  if paths.is_empty() {
    return read_stdin()
  }
  let out : Array[String] = []
  for p in paths {
    out.push(if p == "-" { read_stdin() } else { read_file(p) })
  }
  out.join("\n")
}

///|
fn render(d : @diff.Diff, mode : Mode) -> Unit {
  match mode {
    Stat => println(d.format_stat())
    Detail => println(d.format_detail())
    Check => ()
  }
}

///|
/// 解析器报的行号错误换成 IoError::BadLine，好让上层的 catch 一次接住。
fn parse_text(text : String) -> @diff.Diff raise IoError {
  @diff.parse_diff(text) catch {
    @diff.BadDiff(no, msg) => raise BadLine(no, msg)
  }
}

///|
fn run_flags(flags : Flags) -> Int raise IoError {
  let text = read_all(flags.paths)
  let d = parse_text(text)
  render(d, flags.mode)
  match flags.mode {
    Check => if d.is_empty() { 0 } else { 1 }
    _ => 0
  }
}

///|
/// 返回进程退出码。所有 raise 都在这里收敛成 2。
fn run(argv : Array[String]) -> Int {
  match parse_args(argv) {
    ShowHelp => {
      print_help()
      0
    }
    ShowVersion => {
      println("moondiff \{version}")
      0
    }
    UsageError(msg) => {
      eprintln("moondiff: \{msg}")
      2
    }
    Run(flags) =>
      run_flags(flags) catch {
        err => {
          eprintln("moondiff: \{err.message()}")
          2
        }
      }
  }
}

///|
fn argv_without_program() -> Array[String] {
  let argv = @env.args()
  let out : Array[String] = []
  for i in 1..<argv.length() {
    out.push(argv[i])
  }
  out
}

///|
fn main {
  exit_with(run(argv_without_program()))
}
