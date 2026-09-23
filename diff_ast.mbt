// unified diff 的数据模型。
//
// 这里只有纯数据和纯函数，不碰文件、不碰网络、不碰大模型，
// 所以整套结构可以脱离 LLM 单独做断言测试。

///|
/// 一行源码在 diff 里扮演的角色。
enum LineKind {
  Context
  Added
  Removed
} derive(Eq, Debug)

///|
/// diff 中的单行。
///
/// 行号在对应一侧不存在时为 `None`：新增行没有「改动前」的行号，
/// 删除行没有「改动后」的行号，上下文行两侧都有。
struct Line {
  kind : LineKind
  /// 去掉行首 `-` / `+` / 空格之后的原始内容
  content : String
  old_lineno : Int?
  new_lineno : Int?
} derive(Eq, Debug)

///|
/// 一个 `@@` 块。
struct Hunk {
  old_start : Int
  old_count : Int
  new_start : Int
  new_count : Int
  /// `@@ ... @@` 后面的函数名提示，git 自动生成，可能为空
  heading : String
  lines : Array[Line]
  /// 标记 `\ No newline at end of file` 落在改动前的文件上
  no_newline_old : Bool
  /// 标记 `\ No newline at end of file` 落在改动后的文件上
  no_newline_new : Bool
} derive(Eq, Debug)

///|
/// 这个文件整体发生了什么。
enum FileStatus {
  Modified
  NewFile
  Deleted
  Renamed
  Copied
  /// 只改了权限，内容一行没动
  ModeOnly
} derive(Eq, Debug)

///|
/// 一个文件的完整改动记录。
struct FileDiff {
  /// 新增文件时为 `/dev/null`
  old_path : String
  /// 删除文件时为 `/dev/null`
  new_path : String
  status : FileStatus
  binary : Bool
  /// 形如 `100644`；diff 里没写就是 `None`
  old_mode : String?
  new_mode : String?
  hunks : Array[Hunk]
} derive(Eq, Debug)

///|
/// 一份完整的 diff，也就是 `git diff` 一次的输出。
struct Diff {
  files : Array[FileDiff]
} derive(Eq, Debug)

///|
// `derive` 出来的 trait 方法不会自动变成点号方法，要显式提升一次，
// 调用方才能写 `a == b`。
pub extend LineKind with Eq::{equal, not_equal}

///|
pub extend Line with Eq::{equal, not_equal}

///|
pub extend Hunk with Eq::{equal, not_equal}

///|
pub extend FileStatus with Eq::{equal, not_equal}

///|
pub extend FileDiff with Eq::{equal, not_equal}

///|
pub extend Diff with Eq::{equal, not_equal}

///|
pub extend LineKind with Debug::{to_repr}

///|
pub extend Line with Debug::{to_repr}

///|
pub extend Hunk with Debug::{to_repr}

///|
pub extend FileStatus with Debug::{to_repr}

///|
pub extend FileDiff with Debug::{to_repr}

///|
pub extend Diff with Debug::{to_repr}

///|
/// 是不是改动行（上下文行不算）。
pub fn Line::is_change(self : Line) -> Bool {
  self.kind != Context
}

///|
pub fn Hunk::added(self : Hunk) -> Array[Line] {
  self.lines.filter(fn(l) { l.kind == Added })
}

///|
pub fn Hunk::removed(self : Hunk) -> Array[Line] {
  self.lines.filter(fn(l) { l.kind == Removed })
}

///|
/// 只看真正改动的行，跳过上下文
pub fn Hunk::changed(self : Hunk) -> Array[Line] {
  self.lines.filter(fn(l) { l.kind != Context })
}

///|
pub fn Hunk::added_count(self : Hunk) -> Int {
  self.added().length()
}

///|
pub fn Hunk::removed_count(self : Hunk) -> Int {
  self.removed().length()
}

///|
/// 重建「改动前」的代码片段：上下文 + 删除行。
pub fn Hunk::old_side_text(self : Hunk) -> String {
  self.side_text(Added)
}

///|
/// 重建「改动后」的代码片段：上下文 + 新增行。
/// 喂给大模型看的应该就是这段。
pub fn Hunk::new_side_text(self : Hunk) -> String {
  self.side_text(Removed)
}

///|
fn Hunk::side_text(self : Hunk, exclude : LineKind) -> String {
  let buf : Array[String] = []
  for l in self.lines {
    if l.kind != exclude {
      buf.push(l.content)
    }
  }
  buf.join("\n")
}

///|
/// 展示用的路径：优先给改动后的，被删除的文件退回改动前的。
pub fn FileDiff::display_path(self : FileDiff) -> String {
  if self.new_path == "/dev/null" {
    self.old_path
  } else {
    self.new_path
  }
}

///|
pub fn FileDiff::changed_line_count(self : FileDiff) -> Int {
  let mut n = 0
  for h in self.hunks {
    n = n + h.changed().length()
  }
  n
}

///|
pub fn Diff::empty() -> Diff {
  { files: [], }
}

///|
pub fn Diff::is_empty(self : Diff) -> Bool {
  self.files.is_empty()
}

///|
pub fn Diff::file_count(self : Diff) -> Int {
  self.files.length()
}

///|
pub fn Diff::hunk_count(self : Diff) -> Int {
  let mut n = 0
  for f in self.files {
    n = n + f.hunks.length()
  }
  n
}

///|
pub fn Diff::added_count(self : Diff) -> Int {
  let mut n = 0
  for f in self.files {
    for h in f.hunks {
      n = n + h.added_count()
    }
  }
  n
}

///|
pub fn Diff::removed_count(self : Diff) -> Int {
  let mut n = 0
  for f in self.files {
    for h in f.hunks {
      n = n + h.removed_count()
    }
  }
  n
}

///|
/// 这次改动碰到了哪些文件
pub fn Diff::touched_paths(self : Diff) -> Array[String] {
  let out : Array[String] = []
  for f in self.files {
    out.push(f.display_path())
  }
  out
}
