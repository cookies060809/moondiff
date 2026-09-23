// native 目标的进程与文件原语：发请求要靠外部程序（curl），所以要能写文件、
// 执行命令、删文件。用 C 的 `system` 而不是 `popen`：`popen` 在 MSVC 里叫
// `_popen`、POSIX 里才叫 `popen`，而 `system` 两边同名，省掉一套条件编译。
//
// fopen / fclose / 判空复用 io_native.mbt 里已有的那三个，FILE* 的坑也写在那边。

///|
#borrow(buf, stream)
extern "C" fn fwrite_ffi(
  buf : Bytes,
  size : Int,
  n : Int,
  stream : FileHandle,
) -> Int = "fwrite"

///|
#borrow(path)
extern "C" fn remove_ffi(path : Bytes) -> Int = "remove"

///|
#borrow(cmd)
extern "C" fn system_ffi(cmd : Bytes) -> Int = "system"

///|
pub fn write_text_file(path : String, text : String) -> Unit raise IoError {
  let f = fopen_ffi(@utf8.encode(path), @utf8.encode("wb"))
  guard is_null_ffi(f) == 0 else { raise CannotWrite(path) }
  let buf = @utf8.encode(text)
  let n = fwrite_ffi(buf, 1, buf.length(), f)
  let _ = fclose_ffi(f)
  guard n == buf.length() else { raise CannotWrite(path) }
}

///|
/// 返回 shell 的退出码。命令串必须是常量，见 @diff.curl_command。
pub fn run_command(cmd : String) -> Int {
  system_ffi(@utf8.encode(cmd))
}

///|
/// 尽力而为地删掉临时文件：删不掉也不该盖掉真正的错误。
pub fn remove_file(path : String) -> Unit {
  let _ = remove_ffi(@utf8.encode(path))
}
