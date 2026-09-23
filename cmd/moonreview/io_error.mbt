///|
/// 输入层的错误。BadLine 用来把解析器报的行号错误归到同一个类型里，
/// 这样 main 只需要 catch 一次。
suberror IoError {
  CannotRead(String)
  CannotWrite(String)
  BadLine(Int, String)
}

///|
pub fn IoError::message(self : IoError) -> String {
  match self {
    CannotRead(path) => "cannot read \{path}"
    CannotWrite(path) => "cannot write \{path}"
    BadLine(no, msg) => "line \{no}: \{msg}"
  }
}
