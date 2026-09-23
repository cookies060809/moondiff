// 输入层：读 stdin 和读文件。
//
// 这里不依赖任何外部包。native 目标的运行时本来就把 sync_io.c 编进了可执行
// 文件（`moon build` 的输出里能看到它），里面就是官方 IO 包在用的那组
// `moonbit_*` 符号，直接 extern 过来即可。
//
// 两个和 C 打交道的坑：
// 1. FILE* 是裸指针，用 `FileHandle?` 接会被 MoonBit 的指针标签规则毁掉
//    （对齐过的指针看起来像立即数），所以判空必须走 moonbit_is_null。
// 2. 传给 C 写的缓冲区必须是这一轮新建、没有别处引用的 Bytes，
//    否则 C 写进去会改到别人看到的值。

///|
#external
type FileHandle

///|
#borrow(path, mode)
extern "C" fn fopen_ffi(path : Bytes, mode : Bytes) -> FileHandle = "moonbit_fopen_ffi"

///|
#borrow(ptr)
extern "C" fn is_null_ffi(ptr : FileHandle) -> Int = "moonbit_is_null"

///|
#borrow(buf, stream)
extern "C" fn fread_ffi(
  buf : Bytes,
  size : Int,
  n : Int,
  stream : FileHandle,
) -> Int = "moonbit_fread_ffi"

///|
#borrow(stream)
extern "C" fn fclose_ffi(stream : FileHandle) -> Int = "moonbit_fclose_ffi"

///|
/// POSIX read。Windows 的 CRT 也导出这个名字，管道和重定向都能走它。
#borrow(buf)
extern "C" fn read_ffi(fd : Int, buf : Bytes, count : Int) -> Int = "read"

///|
/// 用 libc 的 exit 结束进程。它会先把 stdio 缓冲区冲掉，
/// 所以 println 之后立刻退出不会丢输出。
extern "C" fn exit_ffi(code : Int) -> Unit = "exit"

///|
let chunk_size : Int = 4096

///|
/// 反复调 `read_chunk` 往缓冲区里写，直到返回 0 或负数。
/// 0 是正常结束，负数是读失败（read/fread 返回 -1），这时才 raise。
fn drain(what : String, read_chunk : (Bytes) -> Int) -> String raise IoError {
  let out : Array[Byte] = Array(capacity=chunk_size)
  let chunk = @utf8.encode("a").repeat(chunk_size)
  let mut n = read_chunk(chunk)
  while n > 0 {
    for i in 0..<n {
      out.push(chunk[i])
    }
    n = read_chunk(chunk)
  }
  guard n >= 0 else { raise CannotRead(what) }
  @utf8.decode_lossy(Bytes::from_array(out))
}

///|
pub fn read_stdin() -> String raise IoError {
  drain("-", fn(buf) { read_ffi(0, buf, chunk_size) })
}

///|
pub fn read_file(path : String) -> String raise IoError {
  let f = fopen_ffi(@utf8.encode(path), @utf8.encode("rb"))
  guard is_null_ffi(f) == 0 else { raise CannotRead(path) }
  let text = drain(path, fn(buf) { fread_ffi(buf, 1, chunk_size, f) })
  let _ = fclose_ffi(f)
  text
}

///|
pub fn exit_with(code : Int) -> Unit {
  exit_ffi(code)
}
