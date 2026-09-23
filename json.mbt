// JSON 输出层。给机器读的，所以字段名固定、值不带颜色和对齐这些给人看的东西。
//
// Map 按写入顺序输出，所以字段先后就是下面构造时写的顺序。同一份 diff
// 每次序列化出来的字节都一样，快照测试可以直接写死。

///|
fn jstr(s : String) -> Json {
  Json::string(s)
}

///|
fn jint(n : Int) -> Json {
  Json::number(n.to_double())
}

///|
fn jbool(b : Bool) -> Json {
  Json::boolean(b)
}

///|
fn jopt_int(n : Int?) -> Json {
  match n {
    None => Json::null()
    Some(v) => jint(v)
  }
}

///|
fn jopt_str(s : String?) -> Json {
  match s {
    None => Json::null()
    Some(v) => jstr(v)
  }
}

///|
fn jarr(items : Array[Json]) -> Json {
  Json::array(items)
}

///|
/// 按名字装一个 JSON 对象。
fn jobj(fields : Array[(String, Json)]) -> Json {
  let obj : Map[String, Json] = Map([])
  for (k, v) in fields {
    obj[k] = v
  }
  Json::object(obj)
}

///|
fn LineKind::kind_name(self : LineKind) -> String {
  match self {
    Context => "context"
    Added => "added"
    Removed => "removed"
  }
}

///|
fn line_json(l : Line) -> Json {
  jobj([
    ("kind", jstr(l.kind.kind_name())),
    ("old_line", jopt_int(l.old_lineno)),
    ("new_line", jopt_int(l.new_lineno)),
    ("content", jstr(l.content)),
  ])
}

///|
fn hunk_json(h : Hunk) -> Json {
  jobj([
    ("old_start", jint(h.old_start)),
    ("old_count", jint(h.old_count)),
    ("new_start", jint(h.new_start)),
    ("new_count", jint(h.new_count)),
    ("heading", jstr(h.heading)),
    ("no_newline_old", jbool(h.no_newline_old)),
    ("no_newline_new", jbool(h.no_newline_new)),
    ("lines", jarr(h.lines.map(line_json))),
  ])
}

///|
fn file_json(f : FileDiff) -> Json {
  jobj([
    ("old_path", jstr(f.old_path)),
    ("new_path", jstr(f.new_path)),
    ("path", jstr(f.display_path())),
    ("status", jstr(f.status.label())),
    ("binary", jbool(f.binary)),
    ("old_mode", jopt_str(f.old_mode)),
    ("new_mode", jopt_str(f.new_mode)),
    ("added", jint(f.added_count())),
    ("removed", jint(f.removed_count())),
    ("hunks", jarr(f.hunks.map(hunk_json))),
  ])
}

///|
pub fn Diff::to_json(self : Diff) -> Json {
  jobj([
    (
      "summary",
      jobj([
        ("file_count", jint(self.file_count())),
        ("hunk_count", jint(self.hunk_count())),
        ("added", jint(self.added_count())),
        ("removed", jint(self.removed_count())),
      ]),
    ),
    ("files", jarr(self.files.map(file_json))),
  ])
}

///|
/// 缩进两格的可读 JSON，给命令行 `--json` 用。
pub fn Diff::format_json(self : Diff) -> String {
  self.to_json().stringify(indent=2)
}
