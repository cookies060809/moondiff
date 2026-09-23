// 非 native 目标（wasm / wasm-gc / js）没有进程和文件系统，`--review` 在这
// 些后端只能明说做不到；离线生成提示词的 `--review-prompt` 不受影响。

///|
pub fn write_text_file(path : String, _ : String) -> Unit raise IoError {
  raise CannotWrite(path)
}

///|
pub fn run_command(_ : String) -> Int {
  -1
}

///|
pub fn remove_file(_ : String) -> Unit {

}
