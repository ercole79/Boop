#!/usr/bin/env node
"use strict";

/*
 * boop-validate.js — validate every built-in Boop script.
 *
 * For each script in Boop/Boop/scripts it checks that:
 *   1. the metadata header parses as JSON and has the expected fields,
 *   2. the script loads in an isolated context (mirroring one JSContext per
 *      script, including resolving any @boop/* module imports),
 *   3. a top-level main() function is declared.
 *
 * Exits non-zero if any script fails, so it can be used as a CI-style check.
 *
 * Usage: node .cursor/tools/boop-validate.js
 */

const fs = require("fs");
const path = require("path");
const { listBuiltInScripts, loadScript, parseMetadata } = require("./boop-runtime");

const REQUIRED_META_FIELDS = ["name", "description"];

function validateOne(scriptPath) {
  const rel = path.basename(scriptPath);
  const source = fs.readFileSync(scriptPath, "utf8");

  const info = parseMetadata(source); // throws on bad metadata
  for (const field of REQUIRED_META_FIELDS) {
    if (!(field in info)) {
      throw new Error(`metadata missing required field "${field}"`);
    }
  }

  const script = loadScript(scriptPath, { isBuiltIn: true });
  if (typeof script.run !== "function") {
    throw new Error("no runnable main()");
  }
  return info;
}

function main() {
  const scripts = listBuiltInScripts();
  let passed = 0;
  const failures = [];

  for (const scriptPath of scripts) {
    const rel = path.basename(scriptPath);
    try {
      const info = validateOne(scriptPath);
      passed++;
      console.log(`  ok   ${rel}  (${info.name})`);
    } catch (err) {
      failures.push({ rel, message: err.message });
      console.log(`  FAIL ${rel}  — ${err.message}`);
    }
  }

  console.log("");
  console.log(
    `Validated ${scripts.length} built-in scripts: ${passed} passed, ${failures.length} failed.`
  );

  if (failures.length > 0) {
    process.exit(1);
  }
}

main();
