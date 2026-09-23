// unified diff 解析器。
//
// 全部是纯函数：输入一段文本，输出结构化结果，失败则 raise 带行号的错误。
//
// 为什么用「按 @@ 声明的行数驱动」的状态机，而不是逐行看前缀？
// 因为前缀会骗人：一处被删掉的源码如果是 `-- foo`，它在 diff 里渲染成
// `--- foo`，看起来和文件头 `--- a/x` 一模一样。只有先读到 @@ 头、
// 拿到「这一块有几行」，才能判断接下来的 `--- foo` 属于 hunk 内容。

///|
/// 解析失败。`BadDiff(行号, 说明)`，行号从 1 开始，指向出错的源文本行。
pub suberror DiffError {
  BadDiff(Int, String)
} derive(Eq, Debug)

///|
pub extend DiffError with Eq::{equal, not_equal}

///|
pub extend DiffError with Debug::{to_repr}

///|
/// 从 `@@ -10,3 +10,4 @@ 函数名` 读出来的定位信息。
struct HunkHeader {
  old_start : Int
  old_count : Int
  new_start : Int
  new_count : Int
  heading : String
} derive(Eq, Debug)

///|
pub extend HunkHeader with Eq::{equal, not_equal}

///|
pub extend HunkHeader with Debug::{to_repr}

///|
/// 按行切分，兼容 `\n`、`\r\n`、`\r`。
/// 文本以换行结尾时不会多出一个空行。
pub fn split_lines(text : String) -> Array[String] {
  let normalized = text
    .replace_all(old="\r\n", new="\n")
    .replace_all(old="\r", new="\n")
  let out : Array[String] = []
  for line in normalized.split("\n") {
    out.push(line.to_owned())
  }
  if out.length() > 0 && out[out.length() - 1] == "" {
    let _ = out.pop()
  }
  out
}

///|
/// 取字符区间 `[from, to)` 拼成字符串，下标越界会被夹到合法范围。
/// 后面所有下标操作都基于 `Array[Char]`，这样中文和 emoji 路径
/// 不会按 UTF-16 码元错位。
fn chars_slice(cs : Array[Char], from : Int, to : Int) -> String {
  let len = cs.length()
  let lo = if from < 0 { 0 } else if from > len { len } else { from }
  let hi = if to < lo { lo } else if to > len { len } else { to }
  String::from_array(cs[lo:hi])
}

///|
/// 取 `prefix` 之后的内容，例如 `after("--- a/f.c", "--- ")` 得到 `a/f.c`。
/// 前缀不匹配时原样返回。
fn after(line : String, prefix : String) -> String {
  match line.strip_prefix(prefix) {
    Some(rest) => rest.to_owned()
    None => line
  }
}

///|
fn is_space_at(cs : Array[Char], i : Int) -> Bool {
  i < cs.length() && cs[i] == ' '
}

///|
fn skip_spaces(cs : Array[Char], from : Int) -> Int {
  let mut i = from
  while is_space_at(cs, i) {
    i = i + 1
  }
  i
}

///|
/// 从 `from` 起读一串十进制数字，返回（值, 结束下标, 是否成功）。
/// 超过 9 位按失败处理，避免畸形输入把 `Int` 累加溢出。
fn read_digits(cs : Array[Char], from : Int) -> (Int, Int, Bool) {
  let mut i = from
  while i < cs.length() && cs[i] >= '0' && cs[i] <= '9' {
    i = i + 1
  }
  let width = i - from
  if width == 0 || width > 9 {
    (0, i, false)
  } else {
    let mut v = 0
    for k in from..<i {
      v = v * 10 + (cs[k].to_int() - '0'.to_int())
    }
    (v, i, true)
  }
}

///|
fn strip_surrounding_quotes(text : String) -> String {
  let cs = text.to_array()
  if cs.length() >= 2 && cs[0] == '"' && cs[cs.length() - 1] == '"' {
    chars_slice(cs, 1, cs.length() - 1)
  } else {
    text
  }
}

///|
/// 读一个路径 token。git 遇到含空格的路径会加双引号，
/// 所以这里自己做引号感知的切分，而不是按空格 split。
/// 返回（路径, 结束下标）。
fn read_path_token(cs : Array[Char], from : Int) -> (String, Int) {
  if from < cs.length() && cs[from] == '"' {
    let mut i = from + 1
    while i < cs.length() && cs[i] != '"' {
      i = i + 1
    }
    (chars_slice(cs, from + 1, i), i + 1)
  } else {
    let mut i = from
    while i < cs.length() && cs[i] != ' ' {
      i = i + 1
    }
    (chars_slice(cs, from, i), i)
  }
}

///|
/// 清理 `---` / `+++` 行里的路径：
/// 1. 丢掉制表符之后的时间戳（`--- a/f.c\t2026-01-01 10:00`）
/// 2. 去掉包裹的引号
/// 3. 去掉 git 的 `a/` `b/` 前缀
///
/// `/dev/null` 会原样保留，靠它判断新增还是删除。
pub fn clean_path(raw : String) -> String {
  let no_stamp = match raw.before("\t") {
    Some(head) => head.to_owned()
    None => raw
  }
  let unquoted = strip_surrounding_quotes(no_stamp)
  if unquoted.has_prefix("a/") {
    after(unquoted, "a/")
  } else if unquoted.has_prefix("b/") {
    after(unquoted, "b/")
  } else {
    unquoted
  }
}

///|
/// 读 `diff --git a/x b/y` 去掉前缀之后的两个路径。
pub fn read_two_paths(rest : String) -> (String, String) {
  let cs = rest.to_array()
  let (p1, i1) = read_path_token(cs, skip_spaces(cs, 0))
  let (p2, _) = read_path_token(cs, skip_spaces(cs, i1))
  (clean_path(p1), clean_path(p2))
}

///|
/// 逗号后面的计数；整段 `,N` 省略时按 GNU 规则当作 1。
fn read_count(
  cs : Array[Char],
  from : Int,
  line_no : Int,
  what : String,
) -> (Int, Int) raise DiffError {
  if from < cs.length() && cs[from] == ',' {
    let (n, next, ok) = read_digits(cs, from + 1)
    guard ok else { raise BadDiff(line_no, "\{what}不是数字") }
    (n, next)
  } else {
    (1, from)
  }
}

///|
/// 只裁空格，不裁制表符——函数名提示里可能带 tab。
fn trim_spaces(s : String) -> String {
  let cs = s.to_array()
  let mut from = 0
  while is_space_at(cs, from) {
    from = from + 1
  }
  let mut to = cs.length()
  while to > from && cs[to - 1] == ' ' {
    to = to - 1
  }
  chars_slice(cs, from, to)
}

///|
/// 解析 `@@ -old_start,old_count +new_start,new_count @@ heading`。
///
/// 省略的计数按 GNU 规则当作 1。计数为 0 表示纯插入/纯删除，
/// 此时起始行号含义是「在第几行之后插入」，原样保留不做换算。
pub fn parse_hunk_header(
  line : String,
  line_no : Int,
) -> HunkHeader raise DiffError {
  let cs = line.to_array()
  let len = cs.length()
  guard chars_slice(cs, 0, 2) == "@@" else {
    raise BadDiff(line_no, "hunk 头不是以 @@ 开头")
  }
  let mut i = skip_spaces(cs, 2)
  guard i < len && cs[i] == '-' else {
    raise BadDiff(line_no, "hunk 头缺少 `-` 起始行号")
  }
  let (old_start, next, ok) = read_digits(cs, i + 1)
  guard ok else {
    raise BadDiff(line_no, "hunk 头的旧文件行号不是数字")
  }
  let (old_count, i2) = read_count(
    cs, next, line_no, "hunk 头的旧文件行数",
  )
  i = skip_spaces(cs, i2)
  guard i < len && cs[i] == '+' else {
    raise BadDiff(line_no, "hunk 头缺少 `+` 起始行号")
  }
  let (new_start, next2, ok2) = read_digits(cs, i + 1)
  guard ok2 else {
    raise BadDiff(line_no, "hunk 头的新文件行号不是数字")
  }
  let (new_count, i3) = read_count(
    cs, next2, line_no, "hunk 头的新文件行数",
  )
  i = skip_spaces(cs, i3)
  // 结尾的 `@@` 之后是函数名提示；有些工具不写，留空即可。
  let heading = if chars_slice(cs, i, i + 2) == "@@" {
    trim_spaces(chars_slice(cs, i + 2, len))
  } else {
    ""
  }
  { old_start, old_count, new_start, new_count, heading, }
}

///|
/// 一个文件的游标。`pos` 指向还没读的那一行。
priv struct Reader {
  lines : Array[String]
  mut pos : Int
}

///|
fn Reader::at_end(self : Reader) -> Bool {
  self.pos >= self.lines.length()
}

///|
/// 越界时返回空串，调用方都要先判 `at_end`，所以不会掩盖错误。
fn Reader::peek(self : Reader) -> String {
  if self.at_end() {
    ""
  } else {
    self.lines[self.pos]
  }
}

///|
fn Reader::advance(self : Reader) -> Unit {
  if !self.at_end() {
    self.pos = self.pos + 1
  }
}

///|
/// 当前行的 1 基行号，用于报错定位。
fn Reader::line_no(self : Reader) -> Int {
  self.pos + 1
}

///|
fn Reader::starts_with(self : Reader, prefix : String) -> Bool {
  !self.at_end() && self.peek().has_prefix(prefix)
}

///|
/// 一行是不是某个文件记录的起点。git 只为改动过的文件写 `---` 头，
/// 纯权限变更没有 hunk，`--- a/x` 单独出现也算起点。
fn starts_new_entry(line : String) -> Bool {
  let prefixes : Array[String] = ["diff --git ", "--- ", "@@"]
  prefixes.any(fn(p) { line.has_prefix(p) })
}

///|
/// 把一份 unified diff 解析成结构化结果。
///
/// 空文本是合法的，得到 0 个文件——代码评审里「没有改动」不是错误。
/// 无法识别的杂散行（commit 说明、`version 1.0` 之类）会被跳过，
/// 但 hunk 行数对不上会报错，因为那意味着 diff 本身被截断或损坏了。
pub fn parse_diff(text : String) -> Diff raise DiffError {
  let r : Reader = { lines: split_lines(text), pos: 0, }
  let files : Array[FileDiff] = []
  while !r.at_end() {
    let line = r.peek()
    if starts_new_entry(line) {
      let f = parse_file(r)
      files.push(f)
    } else {
      r.advance()
    }
  }
  { files, }
}

///|
fn trim_suffix(s : String, suffix : String) -> String {
  match s.strip_suffix(suffix) {
    Some(head) => head.to_owned()
    None => s
  }
}

///|
/// `index` / `similarity index` 这类头只影响哈希值，对评审没有信息量。
fn is_noise_header(line : String) -> Bool {
  let prefixes : Array[String] = [
    "index ", "similarity index ", "dissimilarity index ",
  ]
  prefixes.any(fn(p) { line.has_prefix(p) })
}

///|
fn parse_file(r : Reader) -> FileDiff raise DiffError {
  let start_line = r.line_no()
  let mut old_path = ""
  let mut new_path = ""
  let mut status : FileStatus = Modified
  let mut binary = false
  let mut old_mode : String? = None
  let mut new_mode : String? = None
  let hunks : Array[Hunk] = []

  if r.starts_with("diff --git ") {
    let (a, b) = read_two_paths(after(r.peek(), "diff --git "))
    old_path = a
    new_path = b
    r.advance()
  }

  // git 扩展头，顺序不固定，逐条吃到不匹配为止
  while !r.at_end() {
    let line = r.peek()
    if line.has_prefix("new file mode ") {
      status = NewFile
      new_mode = Some(after(line, "new file mode "))
      r.advance()
    } else if line.has_prefix("deleted file mode ") {
      status = Deleted
      old_mode = Some(after(line, "deleted file mode "))
      r.advance()
    } else if line.has_prefix("old mode ") {
      old_mode = Some(after(line, "old mode "))
      r.advance()
    } else if line.has_prefix("new mode ") {
      new_mode = Some(after(line, "new mode "))
      r.advance()
    } else if line.has_prefix("rename from ") {
      old_path = clean_path(after(line, "rename from "))
      status = Renamed
      r.advance()
    } else if line.has_prefix("rename to ") {
      new_path = clean_path(after(line, "rename to "))
      status = Renamed
      r.advance()
    } else if line.has_prefix("copy from ") {
      old_path = clean_path(after(line, "copy from "))
      status = Copied
      r.advance()
    } else if line.has_prefix("copy to ") {
      new_path = clean_path(after(line, "copy to "))
      status = Copied
      r.advance()
    } else if line.has_prefix("Binary files ") {
      // Binary files a/x.png and b/x.png differ
      binary = true
      let parts = after(line, "Binary files ").split(" and ").to_array()
      if parts.length() >= 2 {
        old_path = clean_path(parts[0].to_owned())
        new_path = clean_path(trim_suffix(parts[1].to_owned(), " differ"))
      }
      r.advance()
    } else if line.has_prefix("GIT binary patch") {
      binary = true
      r.advance()
    } else if is_noise_header(line) {
      r.advance()
    } else {
      break
    }
  }

  if r.starts_with("--- ") {
    old_path = clean_path(after(r.peek(), "--- "))
    r.advance()
    if r.starts_with("+++ ") {
      new_path = clean_path(after(r.peek(), "+++ "))
      r.advance()
    }
  }

  // 靠 /dev/null 推断新增与删除，比只看 `new file mode` 覆盖面更广
  if old_path == "/dev/null" {
    status = NewFile
  } else if new_path == "/dev/null" {
    status = Deleted
  }

  while r.starts_with("@@") {
    let h = parse_hunk(r)
    hunks.push(h)
  }

  if hunks.is_empty() && !binary {
    if status == Modified && old_mode != new_mode {
      status = ModeOnly
    } else if old_path == "" && new_path == "" {
      raise BadDiff(start_line, "看起来不是一个 diff 记录")
    }
  }

  { old_path, new_path, status, binary, old_mode, new_mode, hunks, }
}

///|
/// 读一个 hunk。调用方保证游标正停在 `@@` 行上。
fn parse_hunk(r : Reader) -> Hunk raise DiffError {
  let header_line = r.line_no()
  let header = parse_hunk_header(r.peek(), header_line)
  let old_start = header.old_start
  let old_count = header.old_count
  let new_start = header.new_start
  let new_count = header.new_count
  let heading = header.heading
  r.advance()

  let mut old_left = old_count
  let mut new_left = new_count
  let mut old_ln = old_start
  let mut new_ln = new_start
  let lines : Array[Line] = []
  let mut no_newline_old = false
  let mut no_newline_new = false

  while true {
    let line = r.peek()
    let line_no = r.line_no()
    // `\ No newline` 不吃行数，而且可能出现在计数已经归零之后，
    // 所以必须优先于「计数读完」这个退出条件判断。
    if !r.at_end() && line.has_prefix("\\") {
      guard lines.length() > 0 else {
        raise BadDiff(line_no, "缺少换行符标记前面没有内容行")
      }
      match lines[lines.length() - 1].kind {
        Removed => no_newline_old = true
        Added => no_newline_new = true
        Context => {
          no_newline_old = true
          no_newline_new = true
        }
      }
      r.advance()
    } else if old_left == 0 && new_left == 0 {
      break
    } else if r.at_end() {
      raise BadDiff(
        header_line, "hunk 声明的行数还没读完就到了文本结尾",
      )
    } else if line.has_prefix("-") && old_left > 0 {
      lines.push({
        kind: Removed,
        content: after(line, "-"),
        old_lineno: Some(old_ln),
        new_lineno: None,
      })
      old_left = old_left - 1
      old_ln = old_ln + 1
      r.advance()
    } else if line.has_prefix("+") && new_left > 0 {
      lines.push({
        kind: Added,
        content: after(line, "+"),
        old_lineno: None,
        new_lineno: Some(new_ln),
      })
      new_left = new_left - 1
      new_ln = new_ln + 1
      r.advance()
    } else if (line.has_prefix(" ") || line == "") &&
      old_left > 0 &&
      new_left > 0 {
      // 有的工具会剥掉行尾空格，于是空上下文行就成了空串
      lines.push({
        kind: Context,
        content: after(line, " "),
        old_lineno: Some(old_ln),
        new_lineno: Some(new_ln),
      })
      old_left = old_left - 1
      new_left = new_left - 1
      old_ln = old_ln + 1
      new_ln = new_ln + 1
      r.advance()
    } else {
      raise BadDiff(line_no, "hunk 内容与 @@ 声明的行数不符")
    }
  }

  {
    old_start,
    old_count,
    new_start,
    new_count,
    heading,
    lines,
    no_newline_old,
    no_newline_new,
  }
}
