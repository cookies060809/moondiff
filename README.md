# moondiff

把 `git diff` 吐出来的 unified diff 文本解析成结构化数据，再渲染成人能看的改动摘要。

MoonBit 写的，解析层是纯函数，不碰文件也不碰网络；命令行那一层读 stdin 和文件时用的是 native 运行时自带的 C 符号，所以整个项目零第三方依赖。

## 构建

需要 MoonBit 工具链（`moon`）。装好后：

```bash
moon build cmd/main          # 产物在 _build/native/debug/build/cmd/main/main.exe
moon test                    # 39 个测试
```

也可以直接跑：`moon run cmd/main -- --stat`。

当作库引入：`moon add cookies060809/moondiff`。

## 命令行

不传文件名时从标准输入读，`-` 也表示标准输入，给多个文件会把内容按顺序拼起来。

```bash
git diff HEAD~1 HEAD | moondiff
moondiff --detail commit.diff
moondiff --check pr.diff
```

| 选项 | 作用 |
| --- | --- |
| 默认 / `--stat` | 每个文件一行变更量，末尾给总计，形式同 `git diff --stat` |
| `--detail` / `-d` | 逐文件打印状态、hunk 头和每一行的 +/- |
| `--check` | 不输出内容，只用退出码告诉你这份 diff 干不干净 |
| `-h` / `-V` | 帮助、版本 |

退出码：`0` 成功，`1` 是 `--check` 下发现了改动，`2` 是用法错误、读不到输入或 diff 解析失败。

## 例子

下面是一份真实的 `git diff` 输出（一个文件有改动、一个二进制新文件、一个改名），过 `moondiff` 的结果：

```
$ moondiff --stat sample.diff
       src/a.txt |    3 ++-
    src/logo.png |    0
 src/renamed.txt |    0
3 files changed, 2 insertion(+), 1 deletion(-)

$ moondiff -d sample.diff
modified  src/a.txt
@@ -1,3 +1,4 @@
 alpha
-beta
+BETA
 gamma
+delta
new file  src/logo.png
  (binary)
renamed  src/renamed.txt
```

## 库

`moon.pkg` 里给包起个别名，调用时走 `@别名.`（当前 MoonBit 版本没有 `包名::名字` 这种写法）：

```moonbit
// import { "cookies060809/moondiff" @moondiff, }

let d = @moondiff.parse_diff(text)   // 失败 raise DiffError::BadDiff(行号, 说明)
d.format_stat()                      // 上面那份摘要
d.format_detail()                    // 上面那份逐行输出
d.file_count()
d.hunk_count()
d.added_count()
d.removed_count()
d.touched_paths()                     // 这次动过的文件
```

数据结构是 `Diff` → `FileDiff` → `Hunk` → `Line`，`Line` 带 `old_line` / `new_line` 两个行号，所以拿到意见之后能准确回指到文件的某一行。

解析器按 `@@` 头声明的行数驱动，而不是逐行看前缀。这一点很重要：diff 里删掉一行 `-- foo` 会渲染成 `--- foo`，长得和文件头一模一样。

覆盖到的格式细节包括 GNU 的"计数省略当作 1"、计数为 0 的纯增/纯删、`\ No newline at end of file` 归属改动前还是改动后、`/dev/null`、`new file mode` / `rename from` / `old mode` / `Binary files ... differ`、带空格路径的引号、`---` 行尾的时间戳、CRLF。

## 还没做的

- `--json` 输出还没做，接机器消费时需要。
- 调模型做自动评审的那一层没开始。
- 只解析，不应用 diff，也不生成 diff（生成请用 `moonbitlang/core` 自带的 `diff` 模块，它只能生成不能解析，这两件事不冲突）。

## 许可

Apache-2.0，见 `LICENSE`。
