"use strict";

/*
 * boop-runtime.js
 *
 * A faithful Node.js reimplementation of the parts of Boop's macOS runtime that
 * are relevant to authoring and validating Boop scripts:
 *
 *   - Script metadata parsing (the `/** { ... } **\/` header),
 *     mirroring ScriptManager.loadScript in
 *     Boop/Boop/System/ScriptManager.swift.
 *   - The `ScriptExecution` object passed to `main(state)`, mirroring
 *     Boop/Boop/System/Models/ScriptExecution.swift.
 *   - The custom `require()` module system (including `@boop/*` built-in
 *     modules resolved from Boop/Boop/scripts/lib), mirroring
 *     Boop/Boop/System/Models/Script+Require.swift.
 *   - Per-script isolation using Node's `vm` module, mirroring the one
 *     JSContext-per-script model in Boop/Boop/System/Models/Script.swift.
 *
 * The real app runs scripts under JavaScriptCore, which is a *subset* of what
 * Node exposes. Any script that works under Boop will work here; the reverse is
 * not guaranteed, so avoid relying on Node-only globals when authoring scripts.
 */

const fs = require("fs");
const path = require("path");
const vm = require("vm");

// Repo root is two levels up from `.cursor/tools`.
const REPO_ROOT = path.resolve(__dirname, "..", "..");
const BUILTIN_SCRIPTS_DIR = path.join(REPO_ROOT, "Boop", "Boop", "scripts");
const BUILTIN_LIB_DIR = path.join(BUILTIN_SCRIPTS_DIR, "lib");

const BOOP_PREFIX = "@boop/";
const MODULE_EXT = ".js";

/**
 * Extract and parse the metadata JSON contained between the first `/**` and the
 * first `**\/` markers, exactly like ScriptManager.loadScript does.
 */
function parseMetadata(source) {
  const open = source.indexOf("/**");
  const close = source.indexOf("**/");
  if (open === -1 || close === -1 || close < open) {
    throw new Error("Missing Boop metadata comment (/** ... **/)");
  }
  const meta = source.slice(open + 3, close);
  return JSON.parse(meta);
}

/**
 * Emulates ScriptExecution.swift. Properties are plain fields here (rather than
 * native getters/setters) but the observable behavior of `text`, `fullText`,
 * `selection`, `isSelection`, `insert`, `postInfo`, and `postError` matches.
 */
class ScriptExecution {
  constructor({ selection = null, fullText = "", insertIndex = null } = {}) {
    this.isSelection = selection != null;
    this.selection = selection;
    this.fullText = fullText;
    this.insertIndex = insertIndex;
    this.insertOffset = 0;
    this.messages = []; // collected postInfo/postError calls
  }

  get text() {
    return this.isSelection ? this.selection : this.fullText;
  }

  set text(newValue) {
    if (this.isSelection) {
      this.selection = newValue;
    } else {
      this.fullText = newValue;
    }
  }

  postError(error) {
    this.messages.push({ type: "error", message: String(error) });
  }

  postInfo(info) {
    this.messages.push({ type: "info", message: String(info) });
  }

  insert(newValue) {
    newValue = String(newValue);
    if (this.isSelection) {
      this.selection = newValue;
      return;
    }
    if (this.insertIndex == null || this.fullText == null) {
      this.fullText = newValue;
      return;
    }
    const point = this.insertIndex + this.insertOffset;
    this.fullText =
      this.fullText.slice(0, point) + newValue + this.fullText.slice(point);
    this.insertOffset += newValue.length;
  }
}

/**
 * Resolve a require() path to an absolute file path, mirroring Script+Require's
 * `url(for:)`. Built-in scripts can only import `@boop/*` modules.
 */
function resolveModulePath(requirePath, { isBuiltIn, userScriptDir }) {
  let p = requirePath;
  if (!p.endsWith(MODULE_EXT)) {
    p += MODULE_EXT;
  }

  if (p.startsWith(BOOP_PREFIX)) {
    const fileName = p.slice(BOOP_PREFIX.length);
    return path.join(BUILTIN_LIB_DIR, fileName);
  }

  if (isBuiltIn) {
    // Matches Swift: built-in scripts can't import custom stuff.
    return null;
  }

  if (!userScriptDir) return null;
  return path.join(userScriptDir, p);
}

/**
 * Build a `require` function bound to a given script, mirroring
 * Script+Require.setupRequire. Modules are evaluated in their own module scope
 * with a `module`/`exports` object, and `module.exports` is returned.
 */
function makeRequire(options) {
  const cache = new Map();

  function requireFn(requirePath) {
    const resolved = resolveModulePath(requirePath, options);
    if (!resolved || !fs.existsSync(resolved)) {
      // Boop returns `nil`/undefined for unresolved modules.
      return undefined;
    }

    if (cache.has(resolved)) {
      return cache.get(resolved);
    }

    const code = fs.readFileSync(resolved, "utf8");
    const module = { exports: {} };
    const wrapper = new vm.Script(
      "(function (exports, module, require) {\n" + code + "\n});",
      { filename: resolved }
    );
    const sandbox = makeSandbox(options);
    vm.createContext(sandbox);
    const fn = wrapper.runInContext(sandbox);
    fn.call(module.exports, module.exports, module, requireFn);

    cache.set(resolved, module.exports);
    return module.exports;
  }

  return requireFn;
}

/**
 * The set of globals available to scripts/modules. Kept intentionally lean to
 * resemble JavaScriptCore's headless environment (no window/process/etc.).
 */
function makeSandbox(options) {
  const sandbox = {
    console,
    ScriptExecution,
    require: makeRequire(options),
  };
  // Standard JS built-ins are provided by the vm context automatically.
  return sandbox;
}

/**
 * Loads a single Boop script into its own isolated context and returns a handle
 * exposing its metadata and a `run(execution)` function.
 */
function loadScript(scriptPath, { isBuiltIn = true, userScriptDir = null } = {}) {
  const source = fs.readFileSync(scriptPath, "utf8");
  const info = parseMetadata(source);

  const options = { isBuiltIn, userScriptDir };
  const sandbox = makeSandbox(options);
  const context = vm.createContext(sandbox);

  vm.runInContext(source, context, { filename: scriptPath });

  const mainFn = sandbox.main;
  if (typeof mainFn !== "function") {
    throw new Error("Script does not declare a top-level main() function");
  }

  return {
    path: scriptPath,
    name: info.name,
    info,
    run(execution) {
      mainFn(execution);
      return execution;
    },
  };
}

/**
 * Convenience: run a script against provided text/selection and return the
 * resulting text plus any messages.
 */
function runScript(scriptPath, { fullText = "", selection = null, insertIndex = null, isBuiltIn = true, userScriptDir = null } = {}) {
  const script = loadScript(scriptPath, { isBuiltIn, userScriptDir });
  const execution = new ScriptExecution({ fullText, selection, insertIndex });
  script.run(execution);
  return {
    name: script.name,
    info: script.info,
    text: execution.text,
    fullText: execution.fullText,
    selection: execution.selection,
    messages: execution.messages,
  };
}

/**
 * Resolve a built-in script by file name (with or without .js) or by its
 * declared metadata name.
 */
function resolveBuiltInScript(nameOrPath) {
  if (fs.existsSync(nameOrPath)) return nameOrPath;

  const direct = path.join(
    BUILTIN_SCRIPTS_DIR,
    nameOrPath.endsWith(".js") ? nameOrPath : nameOrPath + ".js"
  );
  if (fs.existsSync(direct)) return direct;

  // Fall back to matching the declared metadata "name".
  const files = listBuiltInScripts();
  for (const file of files) {
    try {
      const info = parseMetadata(fs.readFileSync(file, "utf8"));
      if (info.name && info.name.toLowerCase() === nameOrPath.toLowerCase()) {
        return file;
      }
    } catch (_) {
      /* ignore unparsable files during lookup */
    }
  }
  return null;
}

function listBuiltInScripts() {
  return fs
    .readdirSync(BUILTIN_SCRIPTS_DIR)
    .filter((f) => f.endsWith(".js"))
    .map((f) => path.join(BUILTIN_SCRIPTS_DIR, f));
}

module.exports = {
  REPO_ROOT,
  BUILTIN_SCRIPTS_DIR,
  BUILTIN_LIB_DIR,
  ScriptExecution,
  parseMetadata,
  loadScript,
  runScript,
  resolveBuiltInScript,
  listBuiltInScripts,
};
