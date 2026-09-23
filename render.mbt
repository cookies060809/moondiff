// 输出层：把解析结果渲染成文本。
//
// 和解析层一样是纯函数，不碰 stdin、不碰文件，所以全部可以单测。

///|
/// 一行在 diff 里的行首符号。
pub fn LineKind::prefix(self : LineKind) -> String {
  match self {
    Context => " "
    Added => "+"
    Removed => "-"
  }
}

///|
/// 人话版的状态名，用在详细视图的标题行上。
pub fn FileStatus::label(self : FileStatus) -> String {
  match self {
    Modified => "modified"
    NewFile => "new file"
    Deleted => "deleted"
    Renamed => "renamed"
    Copied => "copied"
    ModeOnly => "mode change"
  }
}

///|
fn bar(plus : Int, minus : Int) -> String {
  // 条太长会挤掉文件名，两侧各截到 20 个字符就够了
  let p = if plus > 20 { 20 } else { plus }
  let m = if minus > 20 { 20 } else { minus }
  "+".repeat(p) + "-".repeat(m)
}

///|
fn plural(n : Int, word : String) -> String {
  if n == 1 {
    "\{n} \{word}"
  } else {
    "\{n} \{word}s"
  }
}

///|
/// git diffstat 风格：每个文件一行，末尾跟一条总计。
///
/// 二进制文件和只改权限的文件没有 hunk，计数自然是 0，照样占一行。
pub fn Diff::format_stat(self : Diff) -> String {
  let files = self.files
  let n = files.length()
  if n == 0 {
    return "no changes"
  }
  // 文件名对齐到最长的那个，竖线才能对上
  let width = files.fold(init=0, fn(acc, f) {
    let len = f.display_path().length()
    if len > acc {
      len
    } else {
      acc
    }
  })
  let out : Array[String] = []
  for f in files {
    let added = f.added_count()
    let removed = f.removed_count()
    let b = bar(added, removed)
    let tail = if b == "" { "" } else { " \{b}" }
    out.push(
      "\{f.display_path().pad_start(width + 1, ' ')} | \{(added + removed).to_string().pad_start(4, ' ')}\{tail}",
    )
  }
  out.push(
    "\{plural(n, "file")} changed, \{self.added_count()} insertion(+), \{self.removed_count()} deletion(-)",
  )
  out.join("\n")
}

///|
/// 按文件、按 hunk 展开的视图，保留 diff 自己的行首符号。
pub fn Diff::format_detail(self : Diff) -> String {
  let out : Array[String] = []
  for f in self.files {
    out.push("\{f.status.label()}  \{f.display_path()}")
    if f.binary {
      out.push("  (binary)")
    }
    if f.status == ModeOnly {
      let old = f.old_mode.unwrap_or("?")
      let new = f.new_mode.unwrap_or("?")
      out.push("  mode \{old} -> \{new}")
    }
    for h in f.hunks {
      let hint = if h.heading == "" { "" } else { " \{h.heading}" }
      out.push(
        "@@ -\{h.old_start},\{h.old_count} +\{h.new_start},\{h.new_count} @@\{hint}",
      )
      for l in h.lines {
        out.push("\{l.kind.prefix()}\{l.content}")
      }
      if h.no_newline_old || h.no_newline_new {
        out.push("\\ No newline at end of file")
      }
    }
  }
  out.join("\n")
}
