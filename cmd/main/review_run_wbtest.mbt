// `--review` 里不联网的那半：环境变量和读响应的容错。
// 真的发请求要靠 curl，那部分放在 shell 脚本里跑，不在单测里碰网络。

///|
fn unset_key_vars() -> Unit {
  for n in key_vars {
    @env.unset_env_var(n)
  }
}

///|
test "an empty variable counts as missing" {
  @env.set_env_var("MOONDIFF_BASE_URL", "")
  assert_eq(nonempty_env("MOONDIFF_BASE_URL"), None)
  @env.set_env_var("MOONDIFF_BASE_URL", "https://api.example/v1")
  assert_eq(nonempty_env("MOONDIFF_BASE_URL"), Some("https://api.example/v1"))
  unset_key_vars()
}

///|
test "the project-specific key wins over the generic one" {
  unset_key_vars()
  @env.set_env_var("MOONDIFF_API_KEY", "")
  @env.set_env_var("OPENAI_API_KEY", "sk-generic")
  assert_eq(first_env(key_vars), Some("sk-generic"))
  @env.set_env_var("MOONDIFF_API_KEY", "sk-own")
  assert_eq(first_env(key_vars), Some("sk-own"))
  unset_key_vars()
}

///|
test "review without a key explains what to set instead of calling curl" {
  unset_key_vars()
  let d = @diff.parse_diff(
    [
      "diff --git a/a.txt b/a.txt", "--- a/a.txt", "+++ b/a.txt", "@@ -1,1 +1,1 @@",
      "-a", "+b",
    ].join("\n"),
  )
  let (ok, text) = ask_for_review(d)
  assert_eq(ok, false)
  assert_true(text.contains("MOONDIFF_API_KEY"))
}

///|
test "a missing response file reads as nothing rather than crashing" {
  assert_eq(try_read(".moondiff-review-does-not-exist"), None)
}
