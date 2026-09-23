// `--review` 的执行流程：写请求体和 curl 配置 → 调 curl → 读响应 → 删临时文件。
//
// 只有这一层碰环境和文件系统；怎么造请求、怎么解响应都在库包里，可以离线测。
// 密钥从环境变量读，绝不从命令行参数走——命令行在整机进程列表里可见。
//
// 临时文件放在当前目录（点开头的隐藏文件），跑完就删。用相对路径是因为
// Windows 的反斜杠会被 curl 配置当成转义符，固定文件名又让要执行的命令
// 变成一个不含任何外部输入的常量字符串。

///|
/// 密钥变量的读取顺序：自己的在前，通用的在后。
let key_vars : Array[String] = ["MOONDIFF_API_KEY", "OPENAI_API_KEY"]

///|
fn nonempty_env(name : String) -> String? {
  match @env.get_env_var(name) {
    Some(v) => if v == "" { None } else { Some(v) }
    None => None
  }
}

///|
/// 按顺序找第一个非空的变量；`--review` 之外的地方不读环境，避免误用。
fn first_env(names : Array[String]) -> String? {
  for n in names {
    match nonempty_env(n) {
      Some(v) => return Some(v)
      None => ()
    }
  }
  None
}

///|
/// 读不到就当没有：curl 没跑起来时响应文件本来就不存在，不该让它变成崩溃。
fn try_read(path : String) -> String? {
  Some(read_file(path)) catch {
    _ => None
  }
}

///|
/// (是否成功, 给人看的输出)。失败原因也走这个元组，好让调用方统一决定退出码。
pub fn ask_for_review(d : @diff.Diff) -> (Bool, String) raise IoError {
  let api_key = match first_env(key_vars) {
    Some(k) => k
    None =>
      return (
        false, "没有 API Key：先 export MOONDIFF_API_KEY=...（也认 OPENAI_API_KEY）",
      )
  }
  let base_url = @diff.resolve_base_url(nonempty_env("MOONDIFF_BASE_URL"))
  let model = @diff.resolve_model(nonempty_env("MOONDIFF_MODEL"))
  write_text_file(@diff.body_file, d.chat_body(model))
  write_text_file(@diff.config_file, @diff.curl_config(base_url, api_key))
  let rc = run_command(@diff.curl_command)
  let response = try_read(@diff.response_file)
  remove_file(@diff.config_file)
  remove_file(@diff.body_file)
  remove_file(@diff.response_file)
  guard rc == 0 else {
    return (
      false,
      "curl 退出码 \{rc}：检查网络、代理，或者本机有没有 curl",
    )
  }
  match response {
    None => (false, "curl 没有写出响应文件 \{@diff.response_file}")
    Some(text) => @diff.chat_reply(text)
  }
}
