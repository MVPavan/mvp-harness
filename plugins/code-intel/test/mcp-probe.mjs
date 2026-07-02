#!/usr/bin/env node
// Minimal stdio MCP client: initialize -> notifications/initialized -> tools/list.
// Prints `TOOLS=<n>` to stdout and exits 0 if the server lists >=1 tool.
// Zero dependencies. Used by the plugin test suite to prove an MCP server starts
// and exposes tools, WITHOUT needing Claude Code or any API key.
//
// Usage: node mcp-probe.mjs [--timeout SECS] -- <server-cmd> [args...]
import { spawn } from "node:child_process";

const argv = process.argv.slice(2);
let timeoutS = 60;
let i = 0;
for (; i < argv.length; i++) {
  if (argv[i] === "--timeout") timeoutS = parseInt(argv[++i], 10) || 60;
  else if (argv[i] === "--") { i++; break; }
  else break;
}
const cmd = argv[i];
const args = argv.slice(i + 1);
if (!cmd) { console.error("usage: mcp-probe.mjs [--timeout S] -- <cmd> [args...]"); process.exit(2); }

const child = spawn(cmd, args, { stdio: ["pipe", "pipe", "pipe"] });
let buf = "";
let done = false;
const timer = setTimeout(() => fail("timeout waiting for tools/list"), timeoutS * 1000);

const send = (obj) => { try { child.stdin.write(JSON.stringify(obj) + "\n"); } catch {} };
function fail(msg) {
  if (done) return; done = true; clearTimeout(timer);
  console.error("probe: " + msg);
  try { child.kill("SIGKILL"); } catch {}
  process.exit(1);
}
function succeed(n) {
  if (done) return; done = true; clearTimeout(timer);
  console.log("TOOLS=" + n);
  try { child.kill("SIGKILL"); } catch {}
  process.exit(n >= 1 ? 0 : 1);
}

child.on("error", (e) => fail("spawn error: " + e.message));
child.on("exit", (code) => { if (!done) fail("server exited early (code " + code + ")"); });
child.stderr.on("data", () => {}); // server logs go to stderr; ignore

child.stdout.on("data", (d) => {
  buf += d.toString();
  let nl;
  while ((nl = buf.indexOf("\n")) >= 0) {
    const line = buf.slice(0, nl).trim();
    buf = buf.slice(nl + 1);
    if (!line) continue;
    let msg;
    try { msg = JSON.parse(line); } catch { continue; } // ignore non-JSON log lines
    if (msg.id === 1 && msg.result) {
      send({ jsonrpc: "2.0", method: "notifications/initialized" });
      send({ jsonrpc: "2.0", id: 2, method: "tools/list", params: {} });
    } else if (msg.id === 2) {
      if (msg.result && Array.isArray(msg.result.tools)) succeed(msg.result.tools.length);
      else fail("tools/list error: " + JSON.stringify(msg.error || msg));
    }
  }
});

send({
  jsonrpc: "2.0", id: 1, method: "initialize",
  params: {
    protocolVersion: "2025-06-18",
    capabilities: {},
    clientInfo: { name: "code-intel-test-probe", version: "0.1.0" },
  },
});
