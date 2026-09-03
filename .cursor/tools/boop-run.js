#!/usr/bin/env node
"use strict";

/*
 * boop-run.js — run a single Boop script against some input text.
 *
 * Usage:
 *   node .cursor/tools/boop-run.js <script> [--input "text"] [--selection "sel"]
 *   echo "text" | node .cursor/tools/boop-run.js <script>
 *
 * <script> is a built-in script name (e.g. "Base64Encode", "Camel Case") or a
 * path to a .js script file.
 *
 * Examples:
 *   node .cursor/tools/boop-run.js Base64Encode --input "Hello, Boop!"
 *   echo "hello world" | node .cursor/tools/boop-run.js "Camel Case"
 */

const fs = require("fs");
const { runScript, resolveBuiltInScript } = require("./boop-runtime");

function parseArgs(argv) {
  const args = { _: [] };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--input" || a === "-i") {
      args.input = argv[++i];
    } else if (a === "--selection" || a === "-s") {
      args.selection = argv[++i];
    } else if (a === "--user") {
      args.user = true;
    } else if (a === "--user-dir") {
      args.userDir = argv[++i];
    } else {
      args._.push(a);
    }
  }
  return args;
}

function readStdin() {
  try {
    return fs.readFileSync(0, "utf8");
  } catch (_) {
    return "";
  }
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const target = args._[0];

  if (!target) {
    console.error("Usage: boop-run.js <script> [--input TEXT] [--selection SEL]");
    process.exit(2);
  }

  const scriptPath = resolveBuiltInScript(target);
  if (!scriptPath) {
    console.error(`Could not find script: ${target}`);
    process.exit(1);
  }

  let input = args.input;
  if (input == null) {
    input = readStdin();
  }

  const result = runScript(scriptPath, {
    fullText: input,
    selection: args.selection != null ? args.selection : null,
    insertIndex: 0,
    isBuiltIn: !args.user,
    userScriptDir: args.userDir || null,
  });

  for (const m of result.messages) {
    console.error(`[${m.type}] ${m.message}`);
  }

  process.stdout.write(result.text != null ? result.text : "");
  if (process.stdout.isTTY) process.stdout.write("\n");
}

main();
