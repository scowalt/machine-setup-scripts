// Explicitly invoked by the registry fixture, never against a live profile.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import net from 'node:net';
import tls from 'node:tls';
import http from 'node:http';
import https from 'node:https';
import { syncBuiltinESMExports } from 'node:module';
import { pathToFileURL } from 'node:url';

const [sdk, agentDir, cwd] = process.argv.slice(2);
assert.equal(process.env.PI_OFFLINE, '1');
assert.equal(path.resolve(agentDir), path.join(os.homedir(), '.pi/agent'));
assert.equal(path.resolve(cwd), path.dirname(os.homedir()));
assert.ok(path.basename(cwd).startsWith('pi-maintenance-'));
assert.deepEqual(fs.readdirSync(os.homedir()), ['.pi']);
const packageDir = path.join(agentDir, 'npm/node_modules/pi-mcp-adapter');
assert.equal(JSON.parse(fs.readFileSync(path.join(packageDir, 'package.json'))).version, '2.32.1');
// Empty, test-owned HOME and cwd contain no MCP config. Also fail if anything
// tries to contact an MCP server, model provider, telemetry or update endpoint.
const blocked = () => { throw new Error('Network is forbidden in the adapter load fixture'); };
globalThis.fetch = blocked;
net.Socket.prototype.connect = blocked;
tls.connect = blocked;
http.request = http.get = https.request = https.get = blocked;
syncBuiltinESMExports();
const { DefaultResourceLoader, SettingsManager } = await import(pathToFileURL(sdk).href);
const pin = 'npm:pi-mcp-adapter@2.32.1';
for (const [entry, expected] of [
  [pin, true],
  [{ source: pin, skills: [] }, true],
  [{ source: pin, extensions: ['index.ts'] }, true],
  [{ source: pin, extensions: ['+./index.ts'] }, true],
  [{ source: pin, extensions: ['*.ts', '+index.ts'] }, true],
  [{ source: pin, extensions: ['!*', '+./index.ts'] }, true],
  [{ source: pin, autoload: false, extensions: ['!index.ts', '+index.ts'] }, true],
  [{ source: pin, extensions: ['+index.ts', '-index.ts'] }, false],
  [{ source: pin, autoload: false, extensions: ['+index.ts'] }, true],
  [{ source: pin, extensions: [] }, false],
  [{ source: pin, extensions: ['./index.ts'] }, false],
  [{ source: pin, extensions: ['-index.ts'] }, false],
  [{ source: pin, autoload: false }, false],
]) {
  const loader = new DefaultResourceLoader({
    cwd, agentDir,
    settingsManager: SettingsManager.inMemory({ packages: [entry] }),
    noSkills: true, noThemes: true, noPromptTemplates: true,
    agentsFilesOverride: () => ({ agentsFiles: [] }),
  });
  await loader.reload();
  const { extensions, errors } = loader.getExtensions();
  assert.deepEqual(errors, []);
  assert.equal(extensions.length, expected ? 1 : 0, JSON.stringify(entry));
  if (expected) {
    assert.equal(extensions[0].resolvedPath, path.join(packageDir, 'index.ts'));
    assert.ok(extensions[0].tools.has('mcp'), 'MCP gateway must register');
    assert.ok(extensions[0].tools.has('mcpScript'), 'MCP scripting must register');
    assert.ok(extensions[0].commands.has('mcp'), '/mcp command must register');
  }
}
console.log('PASS: pinned adapter loads MCP tools and /mcp; disabled filters stay inactive (no network or model calls).');
