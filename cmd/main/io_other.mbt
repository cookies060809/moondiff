// 非 native 目标的兜底实现。
//
// 上一版的 `moonbit_*` 符号只在 native 运行时里，js/wasm 编不出 FILE*。
// 这个包按 native 用（moon.mod 里 preferred_target 就是 native），
// 留这几个桩是为了别人换 target 时还能编译过，只是读不了东西。

///|
pub fn read_stdin() -> String raise IoError {
  raise CannotRead("-")
}

///|
pub fn read_file(path : String) -> String raise IoError {
  raise CannotRead(path)
}

///|
/// 非 native 下没有 exit 可调，只能正常返回。
pub fn exit_with(code : Int) -> Unit {
  if code != 0 {
    eprintln(
      "moondiff: 退出码 \{code}（当前构建目标无法设置退出码）",
    )
  }
}
