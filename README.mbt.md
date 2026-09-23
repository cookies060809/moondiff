# cookies060809/moondiff

unified diff 文本解析器。`parse_diff` 把 `git diff` 的输出读成 `Diff` / `FileDiff` /
`Hunk` / `Line`，每一行都带改动前和改动后的行号；`format_stat` 和 `format_detail`
把它渲染成人能看的摘要和逐行视图。

解析按 `@@` 头声明的行数驱动，不靠逐行看前缀，所以 diff 里被删掉的 `-- foo`
不会被误认成文件头。纯函数，零依赖。

命令行用法和完整说明见仓库：<https://github.com/cookies060809/moondiff>。
