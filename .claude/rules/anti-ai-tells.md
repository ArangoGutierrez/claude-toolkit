# Anti AI Tells

Write like an engineer, not like a model. This rule exists so you self-correct
before `ai-tell-guard.py` fires. The hook is the backstop, not the style guide.

## Banned in any text written to a file

1. **Emoji.** Any codepoint in U+1F300-U+1FAFF, U+1F000-U+1F0FF,
   U+1F1E6-U+1F1FF, U+2600-U+27BF, U+2B00-U+2BFF, or U+FE0F.
2. **Claude commit trailers.** `Co-Authored-By: Claude` and
   `Generated with [Claude Code]`. The author of a commit is the user.
3. **Em-dash** (U+2014). Use a comma, a colon, or parentheses.
4. **Filler.** Phrases such as "You're absolutely right", "I apologize for the
   confusion", "delve into", "As an AI". Also the marketing vocabulary:
   comprehensive, robust, seamless, leverage, utilize, delve, intricate,
   crucial, pivotal, meticulous, showcase, realm, testament, elevate, embark,
   furthermore, moreover, underscore.

Name the specific thing instead. "Retries 3 times" beats "robust retry logic".
Filler words match whole words only, so `robust_parser` and `robustness` pass.

## Escape hatches

- `AI_TELL_GUARD=off` disables the hook for one run. Use it when a tell is the
  subject matter rather than the style.
- Paths under `testdata/`, `fixtures/`, `locales/`, `i18n/`, `node_modules/`,
  `.git/`, and lockfiles are never checked, nor are the guard's own three files.

Only newly written text is inspected, never the file on disk, so existing files
keep their history until you touch the offending line.
