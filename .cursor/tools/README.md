# Boop script development tools (Cloud Agent environment)

Boop is a **macOS** app built with Xcode (AppKit + JavaScriptCore). It cannot be
compiled or run on a Linux Cloud Agent VM. However, the most common way to
contribute to Boop — writing and improving the JavaScript transformation
scripts in [`Boop/Boop/scripts`](../../Boop/Boop/scripts) — does not require
building the app (see the project README).

These tools provide a faithful Node.js reimplementation of the parts of Boop's
runtime that matter for script authoring, so scripts can be run and validated on
any platform:

- `boop-runtime.js` — metadata parsing, the `ScriptExecution` object, and the
  custom `@boop/*` `require()` system, mirroring the Swift sources in
  `Boop/Boop/System`. Each script runs in its own `vm` context, matching Boop's
  one-`JSContext`-per-script model.
- `boop-run.js` — run a single script against input text.
- `boop-validate.js` — validate every built-in script (metadata + load + `main`).

> The app runs scripts under JavaScriptCore, which is a *subset* of Node. Scripts
> that work in Boop will work here; avoid relying on Node-only globals such as
> `process` or `require('fs')` when authoring scripts, since they don't exist in
> Boop.

## Usage

Run a built-in script by name or file, using text from `--input` or stdin:

```bash
node .cursor/tools/boop-run.js Base64Encode --input "Hello, Boop!"
echo "hello world" | node .cursor/tools/boop-run.js "Camel Case"
```

Transformed text is written to stdout; `postInfo`/`postError` messages go to
stderr.

Validate all built-in scripts (useful as a CI-style check; exits non-zero on any
failure):

```bash
node .cursor/tools/boop-validate.js
```
