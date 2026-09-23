/// 命令行层：解析参数、取输入、交给解析器、按模式输出、决定退出码。
///
/// 退出码约定和大多数 Unix 工具一致：
///   0 正常（--check 时表示这份 diff 干净）
///   1 --check 下发现了改动，或者 --review 没拿到模型的意见
///   2 用法错误、读不到输入、或者 diff 本身解析失败

///|
enum Mode {
  Stat
  Detail
  Check
  Json
  Prompt
  Review
} derive(Eq, Debug)

///|
struct Flags {
  mode : Mode
  paths : Array[String]
} derive(Eq, Debug)

///|
enum Parsed {
  ShowHelp
  ShowVersion
  Run(Flags)
  UsageError(String)
} derive(Eq, Debug)

///|
let version : String = "0.1.0"

///|
fn print_help() -> Unit {
  [
    "moonreview \{version} —— 解析 unified diff",
    "",
    "用法: moonreview [选项] [文件 ...]",
    "",
    "不给文件、或者给 `-` 时从标准输入读。多个文件的内容会按顺序拼起来。",
    "",
    "选项:",
    "  --stat          每个文件一行变更量（默认）",
    "  --detail, -d    逐文件打印状态、hunk 头和每一行",
    "  --json          输出结构化 JSON，给别的程序读",
    "  --review-prompt 输出给大模型评审用的提示词（不调模型，只生成文本）",
    "  --review        把提示词发给模型并打印它的意见（要 curl 和外网）",
    "  --check         只校验能不能解析，不输出内容",
    "  -h, --help      显示这份帮助",
    "  -V, --version   显示版本",
    "",
    "--review 读这些环境变量：",
    "  MOONREVIEW_API_KEY   必填，等同于 OPENAI_API_KEY",
    "  MOONREVIEW_BASE_URL  接口地址，默认商汤 SenseNova 的 OpenAI 兼容端点",
    "  MOONREVIEW_MODEL     模型名，默认 sensenova-6.7-flash-lite",
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
    } else if a == "--json" {
      mode = Json
    } else if a == "--review-prompt" {
      mode = Prompt
    } else if a == "--review" {
      mode = Review
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
/// 打印并给出这个模式的退出码。`--review` 是唯一会联网的模式，
/// 它失败也算 1，和 `--check` 发现改动一样表示「有问题要看」。
fn render(d : @diff.Diff, mode : Mode) -> Int raise IoError {
  match mode {
    Stat => {
      println(d.format_stat())
      0
    }
    Detail => {
      println(d.format_detail())
      0
    }
    Json => {
      println(d.format_json())
      0
    }
    Prompt => {
      println(d.review_prompt())
      0
    }
    Review => {
      let (ok, text) = ask_for_review(d)
      println(text)
      if ok {
        0
      } else {
        1
      }
    }
    Check => if d.is_empty() { 0 } else { 1 }
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
      println("moonreview \{version}")
      0
    }
    UsageError(msg) => {
      eprintln("moonreview: \{msg}")
      2
    }
    Run(flags) =>
      run_flags(flags) catch {
        err => {
          eprintln("moonreview: \{err.message()}")
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
