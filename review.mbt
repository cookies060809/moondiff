// 评审提示词的拼装：把解析好的 Diff 变成给模型看的文本。
//
// 只做数据到文本的转换，不联网，所以可以单独测。分成这两层是有原因的：
// MoonBit native 侧没有现成的 HTTPS 包，发请求要靠外部程序，
// 那就先把「给模型看什么」做实，传输那一层单独接。
//
// 每行前面带两列行号（改动前 / 改动后），模型给意见时才能指到准确的行；
// 这两个值来自解析器，不是这里现算的。

///|
fn lineno_column(n : Int?) -> String {
  match n {
    None => ""
    Some(v) => v.to_string()
  }
}

///|
fn hunk_text(h : Hunk) -> String {
  let out : Array[String] = []
  out.push(
    "@@ -\{h.old_start},\{h.old_count} +\{h.new_start},\{h.new_count} @@",
  )
  for l in h.lines {
    let old = lineno_column(l.old_lineno).pad_start(4, ' ')
    let new = lineno_column(l.new_lineno).pad_start(4, ' ')
    out.push("\{old}\{new} \{l.kind.prefix()}\{l.content}")
  }
  out.join("\n")
}

///|
fn file_text(f : FileDiff) -> String {
  let head = "### \{f.display_path()} (\{f.status.label()}, +\{f.added_count()} -\{f.removed_count()})"
  let body = if f.binary {
    "(二进制文件，没有可比对的文本)"
  } else if f.hunks.is_empty() {
    "(没有内容改动)"
  } else {
    f.hunks.map(hunk_text).join("\n")
  }
  head + "\n" + body
}

///|
/// 给模型的指令。写在这里而不是散在命令行里，方便换供应商时一起替换。
let prompt_rules : String = [
  "你在评审一个 git 改动。下面是 unified diff 解析出来的结果：每段以一个文件开头，",
  "行首两列分别是改动前和改动后的行号，之后是 diff 的 `+` / `-` / 空格标记。",
  "", "只针对新增和删除的行提意见，重点看正确性、边界条件、并发和资源泄漏、",
  "以及和周围代码不一致的地方。格式和命名这类工具能查的问题不用提。",
  "", "按这个格式逐条输出，一条一行，不要额外解释：", "  文件路径:行号: 意见",
  "行号用改动后的行号；意见针对被删掉的内容时，用改动前的行号。",
  "没有意见就只输出 LGTM。",
].join("\n")

///|
pub fn Diff::review_prompt(self : Diff) -> String {
  let out : Array[String] = [prompt_rules, ""]
  for f in self.files {
    out.push(file_text(f))
    out.push("")
  }
  out.join("\n")
}
