#!/usr/bin/env node
// Contract version 2: real source/config managers, fake execution, and isolated Git environment.
// Requires an explicitly supplied installed plugins/index.js module. Never starts a daemon.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {spawnSync} from 'node:child_process';

const self = fileURLToPath(import.meta.url);
const modulePath = process.env.PASEO_TEST_PLUGIN_SERVICE_MODULE;
assert.ok(modulePath && path.isAbsolute(modulePath), 'Set PASEO_TEST_PLUGIN_SERVICE_MODULE to the installed Paseo 0.8 plugins/index.js.');

async function cli() {
  const home = process.env.PASEO_HOME;
  const fixture = process.env.PASEO_PLAIN_TEST_ROOT;
  assert.ok(fixture && path.isAbsolute(fixture) && home.startsWith(fixture + path.sep));
  assert.equal(process.env.GIT_ALLOW_PROTOCOL, 'file');
  const args = process.argv.slice(2);
  fs.appendFileSync(path.join(home, 'calls.jsonl'), JSON.stringify(args) + '\n');
  const at = args.findIndex(arg => ['daemon', 'plugin'].includes(arg));
  assert.ok(at === 0 || (at === 2 && args[0] === '--host'));
  const command = args.slice(at);
  if (command[0] === 'daemon') {
    assert.deepEqual(command, ['daemon', 'status', '--json']);
    console.log(JSON.stringify({home, listen:'127.0.0.1:19991', localDaemon:'running', connectedDaemon:'reachable',
      cliVersion:'0.8.0-beta.1', daemonVersion:'0.8.0-beta.1'}));
    return;
  }
  assert.equal(args[1], '127.0.0.1:19991');
  const serviceUrl = pathToFileURL(modulePath);
  const {PluginService} = await import(serviceUrl);
  const {ManagedPluginSources} = await import(new URL('./managed-source.js', serviceUrl));
  const {DaemonConfigStore} = await import(new URL('../daemon-config-store.js', serviceUrl));
  const config = JSON.parse(fs.readFileSync(path.join(home, 'config.json')));
  const logger = {child:() => logger, info() {}, warn() {}, error() {}, debug() {}};
  const store = new DaemonConfigStore(home, {
    mcp:{injectIntoAgents:true}, browserTools:{enabled:false}, providers:{}, metadataGeneration:{providers:[]},
    autoArchiveAfterMerge:false, enableTerminalAgentHooks:false, appendSystemPrompt:'',
    pluginsEnabled:config.pluginsEnabled, plugins:config.plugins || {},
  }, logger);
  const active = new Set();
  const runtime = {
    catalog:() => [...active].map(id => ({id, clientBundle:'fixture'})),
    invoke:async () => { throw new Error('RPC/model calls forbidden'); },
    connectProvider:async () => { throw new Error('provider calls forbidden'); },
    getLogs:() => [], clearLogs() {}, subscribe:() => () => {}, bindPaseoSessionHost() {},
    validatePlugin:async directory => assert.ok(fs.existsSync(path.join(directory, 'index.server.ts'))),
    startPlugin:async (id, directory, canPublish) => {
      assert.ok(canPublish());
      assert.ok(fs.existsSync(path.join(directory, 'index.server.ts')));
      active.add(id);
    },
    stopPluginById:async id => active.delete(id), stopAll:async () => active.clear(),
  };
  const service = new PluginService(logger, store, '0.8.0-beta.1', {
    managedSources:new ManagedPluginSources(home), settingsDirectory:path.join(home, 'plugin-settings'), runtime,
  });
  await service.start();
  try {
    let result;
    if (command[1] === 'ls') {
      assert.deepEqual(command, ['plugin', 'ls', '--json']);
      result = service.listPlugins();
    } else if (command[1] === 'add') {
      assert.deepEqual(command.slice(3), ['--ref', command[4], '--id', 'paseo-plain', '--json']);
      result = await service.installSource({source:command[2], ref:command[4], id:'paseo-plain'});
    } else if (command[1] === 'remove') {
      assert.deepEqual(command, ['plugin', 'remove', 'paseo-plain', '--json']);
      await service.removePlugin('paseo-plain');
      result = {id:'paseo-plain', enabled:false, status:'disabled'};
    } else if (command[1] === 'update') {
      assert.deepEqual(command, ['plugin', 'update', 'paseo-plain', '--json']);
      result = await service.updateSources('paseo-plain');
    } else throw new Error('forbidden fixture CLI operation');
    console.log(JSON.stringify(result));
  } finally { await service.stopAllPlugins(); }
}

async function smoke() {
  assert.notEqual(process.platform, 'win32', 'The CLI fixture uses POSIX executables; this is not a native Windows test.');
  const git = spawnSync('which', ['git'], {encoding:'utf8'}).stdout.trim();
  assert.ok(path.isAbsolute(git));
  const source = fs.readFileSync(new URL('../ubuntu.sh', import.meta.url), 'utf8');
  const installer = source.split('// BEGIN PASEO PLAIN INSTALLER\n')[1].split('// END PASEO PLAIN INSTALLER')[0];
  for (const broken of [false, true]) {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'paseo-native-migration-'));
    try {
      const user = path.join(root, 'user');
      const home = path.join(user, '.paseo');
      const bin = path.join(root, 'bin');
      const repository = path.join(root, 'repository');
      for (const directory of [home, bin, repository]) fs.mkdirSync(directory, {recursive:true, mode:0o700});
      // Hooks export GIT_DIR/INDEX_FILE and friends. Never let a fixture target its caller's repository.
      const clean = Object.fromEntries(Object.entries(process.env).filter(([key]) => !key.toUpperCase().startsWith('GIT_')));
      const hooks = path.join(root, 'empty-hooks');
      fs.mkdirSync(hooks);
      const env = {...clean, HOME:user, PASEO_HOME:home, PATH:`${bin}${path.delimiter}${process.env.PATH}`,
        PASEO_PLAIN_TEST_ROOT:root, PASEO_PLAIN_TEST_CLI:'1',
        GIT_CONFIG_NOSYSTEM:'1', GIT_CONFIG_GLOBAL:path.join(root, 'gitconfig'), GIT_ALLOW_PROTOCOL:'file',
        GIT_CONFIG_COUNT:'2', GIT_CONFIG_KEY_0:`url.${pathToFileURL(repository).href}.insteadOf`,
        GIT_CONFIG_VALUE_0:'https://github.com/scowalt/paseo-plain.git',
        GIT_CONFIG_KEY_1:'core.hooksPath', GIT_CONFIG_VALUE_1:hooks};
      fs.writeFileSync(env.GIT_CONFIG_GLOBAL, '');
      fs.symlinkSync(git, path.join(bin, 'git'));
      fs.writeFileSync(path.join(bin, 'pi'), '#!/bin/sh\nexit 99\n', {mode:0o700});
      fs.writeFileSync(path.join(bin, 'paseo'), `#!/usr/bin/env node\nimport(${JSON.stringify(pathToFileURL(self).href)});\n`, {mode:0o700});
      fs.writeFileSync(path.join(home, 'config.json'), JSON.stringify({version:1, pluginsEnabled:true,
        daemon:{listen:'127.0.0.1:19991'}, plugins:{unrelated:{source:'directory', path:'/fixture/other', enabled:false}}}));
      const run = (command, args, options = {}) => {
        const result = spawnSync(command, args, {env, cwd:repository, encoding:'utf8', timeout:30000, ...options});
        assert.equal(result.status, 0, `${path.basename(command)} failed: ${result.stderr}`);
        return result.stdout;
      };
      const gitRun = args => {
        if (args[0] !== 'init') assert.equal(run(git, ['rev-parse', '--absolute-git-dir']).trim(), path.join(repository, '.git'));
        return run(git, ['-c', 'user.name=Paseo Fixture', '-c', 'user.email=fixture@example.test', '-c', 'commit.gpgsign=false', ...args]);
      };
      gitRun(['init', '-b', 'release']);
      assert.ok(fs.statSync(path.join(repository, '.git')).isDirectory());
      const manifest = {id:'paseo-plain', requirements:{paseo:'>=0.8.0-beta.1 <0.9.0'}};
      fs.writeFileSync(path.join(repository, 'paseo-plugin.json'), JSON.stringify(manifest));
      fs.writeFileSync(path.join(repository, 'index.server.ts'), 'export default function() {}\n');
      gitRun(['add', '.']); gitRun(['commit', '-m', 'old release']);
      const paseo = args => JSON.parse(run(path.join(bin, 'paseo'), ['--host', '127.0.0.1:19991', 'plugin', ...args, '--json']));
      const old = paseo(['add', 'https://github.com/scowalt/paseo-plain.git', '--ref', 'release', '--id', 'paseo-plain']);
      assert.equal(old.status, 'running');
      gitRun(['checkout', '-b', 'main']);
      fs.writeFileSync(path.join(repository, 'index.server.ts'), 'export default function main() {}\n');
      if (broken) fs.writeFileSync(path.join(repository, 'paseo-plugin.json'), JSON.stringify({...manifest, build:[[process.execPath, '-e', 'process.exit(23)']]}));
      gitRun(['add', '.']); gitRun(['commit', '-m', 'main fixture']);
      let mainCommit = gitRun(['rev-parse', 'HEAD']).trim();
      const data = path.join(home, 'plugin-data/paseo-plain');
      const native = path.join(home, 'plugin-settings/paseo-plain');
      fs.mkdirSync(data, {recursive:true}); fs.mkdirSync(native, {recursive:true});
      const preferences = '{"values":{"enabled":false,"style":"unchanged"},"revision":8}';
      fs.writeFileSync(path.join(data, 'configuration.json'), preferences);
      fs.writeFileSync(path.join(data, 'cache.json'), '["cached fixture"]');
      fs.writeFileSync(path.join(native, 'voice.json'), '{"version":1,"values":{"keep":true}}\n');
      const result = spawnSync(process.execPath, ['-'], {input:installer, env, encoding:'utf8', timeout:30000});
      assert.equal(result.status, broken ? 1 : 0, result.stdout + result.stderr);
      assert.equal(fs.readFileSync(path.join(data, 'configuration.json'), 'utf8'), preferences);
      assert.equal(fs.readFileSync(path.join(data, 'cache.json'), 'utf8'), '["cached fixture"]');
      assert.equal(fs.readFileSync(path.join(native, 'voice.json'), 'utf8'), '{"version":1,"values":{"keep":true}}\n');
      assert.equal(fs.existsSync(old.path), false, 'Native removal really deletes the previous managed checkout.');
      const recovery = path.join(home, 'setup-recovery/paseo-plain-release-to-main');
      assert.equal(fs.readFileSync(path.join(recovery, 'checkout/index.server.ts'), 'utf8'), 'export default function() {}\n');
      const state = JSON.parse(fs.readFileSync(path.join(recovery, 'state.json')));
      assert.equal(state.phase, broken ? 'adding' : 'complete');
      if (!broken) {
        fs.writeFileSync(path.join(repository, 'index.server.ts'), 'export default function newerMain() {}\n');
        gitRun(['add', '.']); gitRun(['commit', '-m', 'next main commit']);
        mainCommit = gitRun(['rev-parse', 'HEAD']).trim();
      }
      const beforeCalls = fs.readFileSync(path.join(home, 'calls.jsonl'), 'utf8').trim().split('\n').length;
      const again = spawnSync(process.execPath, ['-'], {input:installer, env, encoding:'utf8', timeout:30000});
      assert.equal(again.status, broken ? 1 : 0, again.stdout + again.stderr);
      if (broken) {
        const calls = fs.readFileSync(path.join(home, 'calls.jsonl'), 'utf8').trim().split('\n').slice(beforeCalls).map(JSON.parse);
        assert.ok(calls.every(args => !args.some(arg => ['remove', 'add', 'update'].includes(arg))));
        assert.equal(paseo(['ls']).some(item => item.id === 'paseo-plain'), false);
      } else {
        assert.match(again.stdout, /checked for updates/);
        const installed = paseo(['ls']).find(item => item.id === 'paseo-plain');
        assert.equal(installed.ref, 'main'); assert.equal(installed.commit, mainCommit); assert.equal(installed.status, 'running');
      }
      assert.equal(JSON.parse(fs.readFileSync(path.join(home, 'config.json'))).plugins.unrelated.enabled, false);
      console.log(`PASS: real Paseo source/config managers, ${broken ? 'failed main build and blocked retry' : 'release-to-main migration and subsequent main commit update'}.`);
    } finally { fs.rmSync(root, {recursive:true, force:true}); }
  }
  console.log('No daemon listener, real plugin execution, provider, authentication, or model was used. Git transport was file-only.');
}

try {
  if (process.env.PASEO_PLAIN_TEST_CLI === '1') await cli();
  else await smoke();
} catch (error) {
  // Only synthetic fixture data reaches this script. Never run it against a real home.
  console.error(error);
  process.exitCode = 1;
}
