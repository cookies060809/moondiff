// unified diff 解析器。
//
// 全部是纯函数：输入一段文本，输出结构化结果或带行号的错误。
//
// 为什么用「按 @@ 声明的行数驱动」的状态机，而不是逐行看前缀？
// 因为前缀会骗人：一处被删掉的源码如果是 `-- foo`，它在 diff 里渲染成
// `--- foo`，看起来和文件头 `--- a/x` 一模一样。只有先读到 @@ 头、
// 拿到「这一块有几行」，才能判断接下来的 `--- foo` 属于 hunk 内容。

///|
/// 解析失败的信息。`line_no` 从 1 开始，指向出错的源文本行。
struct ParseError {
  line_no : Int
  message : String
} deriving(Eq, Show, Debug)

///|
/// 从 `@@ -10,3 +10,4 @@ 函数名` 读出来的定位信息。
struct HunkHeader {
  old_start : Int
  old_count : Int
  new_start : Int
  new_count : Int
  heading : String
} deriving(Eq, Show, Debug)

///|
/// 按行切分，兼容 `\n`、`\r\n`、`\r`。
/// 文本以换行结尾时不会多出一个空行。
pub fn split_lines(text : String) -> Array[String] {
  let normalized = text.replace("\r\n", "\n").replace("\r", "\n")
  let out = normalized.split("\n")
  let n = out.length
  if n > 0 && out[n - 1] == "" {
    let _ = out.pop()
  }
  out
}

///|
/// 把字符串拆成字符数组，后面所有下标操作都基于它，
/// 这样中文和 emoji 路径不会按字节错位。
fn chars_of(text : String) -> Array[Char] {
  let out = Array::new()
  for ch in text {
    out.push(ch)
  }
  out
}

///|
fn join_chars_between(cs : Array[Char], from : Int, to : Int) -> String {
  let buf = Buffer::new()
  let mut i = from
  while i < to && i < cs.length {
    buf.push_char(cs[i])
    i = i + 1
  }
  buf.to_string()
}

///|
/// 取 `prefix` 之后的内容，例如 `after("--- a/f.c", "--- ")` 得到 `a/f.c`。
fn after(line : String, prefix : String) -> String {
  let cs = chars_of(line)
  let skip = chars_of(prefix).length
  join_chars_between(cs, skip, cs.length)
}

///|
fn is_space_at(cs : Array[Char], i : Int) -> Bool {
  i < cs.length && cs[i] == ' '
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
fn read_digits(cs : Array[Char], from : Int) -> (Int, Int, Bool) {
  let mut i = from
  while i < cs.length && cs[i] >= '0' && cs[i] <= '9' {
    i = i + 1
  }
  if i == from {
    (0, from, false)
  } else {
    match Int::from_string_opt(join_chars_between(cs, from, i)) {
      Some(v) -> (v, i, true)
      None -> (0, i, false)
    }
  }
}

///|
fn strip_surrounding_quotes(text : String) -> String {
  let cs = chars_of(text)
  if cs.length >= 2 && cs[0] == '"' && cs[cs.length - 1] == '"' {
    join_chars_between(cs, 1, cs.length - 1)
  } else {
    text
  }
}

///|
/// 读一个路径 token。git 遇到含空格的路径会加双引号，
/// 所以这里自己做引号感知的切分，而不是按空格 split。
/// 返回（路径, 结束下标）。
fn read_path_token(cs : Array[Char], from : Int) -> (String, Int) {
  if from < cs.length && cs[from] == '"' {
    let mut i = from + 1
    while i < cs.length && cs[i] != '"' {
      i = i + 1
    }
    (join_chars_between(cs, from + 1, i), i + 1)
  } else {
    let mut i = from
    while i < cs.length && cs[i] != ' ' {
      i = i + 1
    }
    (join_chars_between(cs, from, i), i)
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
  let no_stamp = match raw.split("\t") {
    [] -> raw
    parts -> parts[0]
  }
  let unquoted = strip_surrounding_quotes(no_stamp)
  if unquoted.starts_with("a/") || unquoted.starts_with("b/") {
    after(unquoted, if unquoted.starts_with("a/") { "a/" } else { "b/" })
  } else {
    unquoted
  }
}

///|
/// 读 `diff --git a/x b/y` 去掉前缀之后的两个路径。
pub fn read_two_paths(rest : String) -> (String, String) {
  let cs = chars_of(rest)
  let (p1, i1) = read_path_token(cs, skip_spaces(cs, 0))
  let (p2, _) = read_path_token(cs, skip_spaces(cs, i1))
  (clean_path(p1), clean_path(p2))
}

///|
fn err(line_no : Int, message : String) -> ParseError {
  { line_no, message }
}

///|
/// 解析 `@@ -old_start,old_count +new_start,new_count @@ heading`。
///
/// 省略的计数按 GNU 规则当作 1。计数为 0 表示纯插入/纯删除，
/// 此时起始行号含义是「在第几行之后插入」，原样保留不做换算。
pub fn parse_hunk_header(
  line : String,
  line_no : Int
) -> Result[HunkHeader, ParseError] {
  let cs = chars_of(line)
  if join_chars_between(cs, 0, 2) != "@@" {
    return Err(err(line_no, "hunk 头不是以 @@ 开头"))
  }
  let mut i = skip_spaces(cs, 2)
  if i >= cs.length || cs[i] != '-' {
    return Err(err(line_no, "hunk 头缺少 `-` 起始行号"))
  }
  let (old_start, i, ok1) = read_digits(cs, i + 1)
  if !ok1 {
    return Err(err(line_no, "hunk 头的旧文件行号不是数字"))
  }
  let mut old_count = 1
  let mut i = i
  if i < cs.length && cs[i] == ',' {
    let (n, j, ok) = read_digits(cs, i + 1)
    if !ok {
      return Err(err(line_no, "hunk 头的旧文件行数不是数字"))
    }
    old_count = n
    i = j
  }
  i = skip_spaces(cs, i)
  if i >= cs.length || cs[i] != '+' {
    return Err(err(line_no, "hunk 头缺少 `+` 起始行号"))
  }
  let (new_start, i, ok2) = read_digits(cs, i + 1)
  if !ok2 {
    return Err(err(line_no, "hunk 头的新文件行号不是数字"))
  }
  let mut new_count = 1
  let mut i = i
  if i < cs.length && cs[i] == ',' {
    let (n, j, ok) = read_digits(cs, i + 1)
    if !ok {
      return Err(err(line_no, "hunk 头的新文件行数不是数字"))
    }
    new_count = n
    i = j
  }
  i = skip_spaces(cs, i)
  // 结尾的 `@@` 之后是函数名提示；有些工具不写，留空即可。
  let heading = if join_chars_between(cs, i, i + 2) == "@@" {
    trim_spaces(join_chars_between(cs, i + 2, cs.length))
  } else {
    ""
  }
  if old_count < 0 || new_count < 0 {
    return Err(err(line_no, "hunk 头的行数不能为负"))
  }
  Ok({ old_start, old_count, new_start, new_count, heading })
}

///|
fn trim_spaces(s : String) -> String {
  let cs = chars_of(s)
  let mut from = 0
  while is_space_at(cs, from) {
    from = from + 1
  }
  let mut to = cs.length
  while to > from && cs[to - 1] == ' ' {
    to = to - 1
  }
  join_chars_between(cs, from, to)
}

///|
/// 一个文件的游标。`pos` 指向还没读的那一行。
struct Reader {
  lines : Array[String]
  mut pos : Int
}

///|
impl Reader {
  fn at_end(self : Reader) -> Bool {
    self.pos >= self.lines.length
  }

  /// 越界时返回空串，调用方都要先判 `at_end`，所以不会掩盖错误。
  fn peek(self : Reader) -> String {
    if self.at_end() {
      ""
    } else {
      self.lines[self.pos]
    }
  }

  fn advance(self : Reader) -> Unit {
    if !self.at_end() {
      self.pos = self.pos + 1
    }
  }

  /// 当前行的 1 基行号，用于报错定位。
  fn line_no(self : Reader) -> Int {
    self.pos + 1
  }

  fn starts_with(self : Reader, prefix : String) -> Bool {
    !self.at_end() && self.peek().starts_with(prefix)
  }
}

///|
/// 把一份 unified diff 解析成结构化结果。
///
/// 空文本是合法的，得到 0 个文件——代码评审里「没有改动」不是错误。
/// 无法识别的杂散行（commit 说明、`version 1.0` 之类）会被跳过，
/// 但 hunk 行数对不上会报错，因为那意味着 diff 本身被截断或损坏了。
pub fn parse_diff(text : String) -> Result[Diff, ParseError] {
  let r = Reader({ lines: split_lines(text), pos: 0 })
  let files = Array::new()
  while !r.at_end() {
    if r.starts_with("diff --git ") || r.starts_with("--- ") || r.starts_with("@@") {
      files.push(parse_file(r)?)
    } else {
      r.advance()
    }
  }
  Ok(Diff({ files }))
}

///|
fn parse_file(r : Reader) -> Result[FileDiff, ParseError] {
  let start_line = r.line_no()
  let mut old_path = ""
  let mut new_path = ""
  let mut status : FileStatus = Modified
  let mut binary = false
  let mut old_mode : String? = None
  let mut new_mode : String? = None
  let hunks = Array::new()

  if r.starts_with("diff --git ") {
    let (a, b) = read_two_paths(after(r.peek(), "diff --git "))
    old_path = a
    new_path = b
    r.advance()
  }

  // git 扩展头，顺序不固定，逐条吃到不匹配为止
  while !r.at_end() {
    let line = r.peek()
    if line.starts_with("new file mode ") {
      status = NewFile
      new_mode = Some(after(line, "new file mode "))
      r.advance()
    } else if line.starts_with("deleted file mode ") {
      status = Deleted
      old_mode = Some(after(line, "deleted file mode "))
      r.advance()
    } else if line.starts_with("old mode ") {
      old_mode = Some(after(line, "old mode "))
      r.advance()
    } else if line.starts_with("new mode ") {
      new_mode = Some(after(line, "new mode "))
      r.advance()
    } else if line.starts_with("rename from ") {
      old_path = clean_path(after(line, "rename from "))
      status = Renamed
      r.advance()
    } else if line.starts_with("rename to ") {
      new_path = clean_path(after(line, "rename to "))
      status = Renamed
      r.advance()
    } else if line.starts_with("copy from ") {
      old_path = clean_path(after(line, "copy from "))
      status = Copied
      r.advance()
    } else if line.starts_with("copy to ") {
      new_path = clean_path(after(line, "copy to "))
      status = Copied
      r.advance()
    } else if line.starts_with("Binary files ") {
      // Binary files a/x.png and b/x.png differ
      binary = true
      let body = after(line, "Binary files ")
      match body.split(" and ") {
        [a, b, ...] -> {
          old_path = clean_path(a)
          new_path = clean_path(trim_suffix(b, " differ"))
        }
        _ -> ()
      }
      r.advance()
    } else if line.starts_with("GIT binary patch") {
      binary = true
      r.advance()
    } else if line.starts_with("index ")
          || line.starts_with("similarity index ")
          || line.starts_with("dissimilarity index ") {
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
    hunks.push(parse_hunk(r)?)
  }

  if hunks.is_empty() && !binary {
    if status == Modified && old_mode != new_mode {
      status = ModeOnly
    } else if old_path == "" && new_path == "" {
      return Err(err(start_line, "看起来不是一个 diff 记录"))
    }
  }

  Ok(FileDiff({ old_path, new_path, status, binary, old_mode, new_mode, hunks }))
}

///|
fn trim_suffix(s : String, suffix : String) -> String {
  if s.ends_with(suffix) {
    let cs = chars_of(s)
    let keep = cs.length - chars_of(suffix).length
    join_chars_between(cs, 0, keep)
  } else {
    s
  }
}

///|
/// 读一个 hunk。调用方保证游标正停在 `@@` 行上。
fn parse_hunk(r : Reader) -> Result[Hunk, ParseError] {
  let header_line = r.line_no()
  let header = parse_hunk_header(r.peek(), header_line)?
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
  let lines = Array::new()
  let mut no_newline_old = false
  let mut no_newline_new = false

  while true {
    // `\ No newline` 不吃行数，而且可能出现在计数已经归零之后，
    // 所以必须优先于「计数读完」这个退出条件判断。
    if !r.at_end() && r.peek().starts_with("\\") {
      if lines.length == 0 {
        return Err(err(r.line_no(), "缺少换行符标记前面没有内容行"))
      }
      match lines[lines.length - 1].kind {
        Removed -> no_newline_old = true
        Added -> no_newline_new = true
        Context -> {
          no_newline_old = true
          no_newline_new = true
        }
      }
      r.advance()
    } else if old_left == 0 && new_left == 0 {
      break
    } else if r.at_end() {
      return Err(err(header_line, "hunk 声明的行数还没读完就到了文本结尾"))
    } else {
      let line = r.peek()
      let line_no = r.line_no()
      if line.starts_with("-") && old_left > 0 {
        lines.push(Line({
          kind: Removed,
          content: after(line, "-"),
          old_lineno: Some(old_ln),
          new_lineno: None,
        }))
        old_left = old_left - 1
        old_ln = old_ln + 1
        r.advance()
      } else if line.starts_with("+") && new_left > 0 {
        lines.push(Line({
          kind: Added,
          content: after(line, "+"),
          old_lineno: None,
          new_lineno: Some(new_ln),
        }))
        new_left = new_left - 1
        new_ln = new_ln + 1
        r.advance()
      } else if (line.starts_with(" ") || line == "") && old_left > 0 && new_left > 0 {
        // 有的工具会剥掉行尾空格，于是空上下文行就成了空串
        lines.push(Line({
          kind: Context,
          content: if line == "" { "" } else { after(line, " ") },
          old_lineno: Some(old_ln),
          new_lineno: Some(new_ln),
        }))
        old_left = old_left - 1
        new_left = new_left - 1
        old_ln = old_ln + 1
        new_ln = new_ln + 1
        r.advance()
      } else {
        return Err(err(line_no, "hunk 内容与 @@ 声明的行数不符"))
      }
    }
  }

  Ok(Hunk({
    old_start,
    old_count,
    new_start,
    new_count,
    heading,
    lines,
    no_newline_old,
    no_newline_new,
  }))
}
