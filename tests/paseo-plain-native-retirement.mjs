#!/usr/bin/env node
// Contract version 4: real native 0664 PID and source/config removal; no daemon or plugin execution.
// Requires an explicitly supplied Paseo 0.8 plugins/index.js. Never starts a daemon.
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
  if (args[0] === 'daemon') {
    assert.deepEqual(args, ['daemon', 'status', '--json']);
    console.log(JSON.stringify({home, listen:'127.0.0.1:19991', localDaemon:'running', connectedDaemon:'reachable',
      cliVersion:'0.8.0', daemonVersion:'0.8.0'}));
    return;
  }
  assert.deepEqual(args.slice(0, 3), ['--host', '127.0.0.1:19991', 'plugin']);
  const command = args.slice(3);
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
  const service = new PluginService(logger, store, '0.8.0', {
    managedSources:new ManagedPluginSources(home), settingsDirectory:path.join(home, 'plugin-settings'), runtime,
  });
  await service.start();
  try {
    let result;
    if (command[0] === 'ls') {
      assert.deepEqual(command, ['ls', '--json']);
      result = service.listPlugins();
    } else if (command[0] === 'add' && process.env.PASEO_PLAIN_FIXTURE_SEED === '1') {
      assert.deepEqual(command, ['add', '--json']);
      result = await service.installSource({source:'https://github.com/scowalt/paseo-plain.git', ref:'release', id:'paseo-plain'});
    } else if (command[0] === 'remove') {
      assert.deepEqual(command, ['remove', 'paseo-plain', '--json']);
      await service.removePlugin('paseo-plain');
      result = {id:'paseo-plain', enabled:false, status:'disabled'};
    } else throw new Error('forbidden fixture CLI operation');
    console.log(JSON.stringify(result));
  } finally { await service.stopAllPlugins(); }
}

async function smoke() {
  assert.notEqual(process.platform, 'win32', 'The CLI fixture uses POSIX executables; this is not a native Windows test.');
  const previousUmask = process.umask(0o077);
  const git = spawnSync('which', ['git'], {encoding:'utf8'}).stdout.trim();
  assert.ok(path.isAbsolute(git));
  const source = fs.readFileSync(new URL('../ubuntu.sh', import.meta.url), 'utf8');
  const helper = source.split('// BEGIN PASEO PLAIN RETIREMENT\n')[1].split('// END PASEO PLAIN RETIREMENT')[0];
  const {acquirePidLock} = await import(new URL('../pid-lock.js', pathToFileURL(modulePath)));
  try {
    for (const variant of ['git', 'disabled-git', 'directory']) {
      const root = fs.mkdtempSync(path.join(os.tmpdir(), 'paseo-native-retirement-'));
      try {
        const user = path.join(root, 'user');
        const home = path.join(user, '.paseo');
        const bin = path.join(root, 'bin');
        const repository = path.join(root, 'repository');
        for (const directory of [home, bin, repository]) fs.mkdirSync(directory, {recursive:true, mode:0o700});
        const clean = Object.fromEntries(Object.entries(process.env).filter(([key]) => !key.toUpperCase().startsWith('GIT_')));
        const hooks = path.join(root, 'empty-hooks');
        fs.mkdirSync(hooks);
        const env = {...clean, HOME:user, PASEO_HOME:home, PATH:`${bin}${path.delimiter}${process.env.PATH}`,
          PASEO_PLAIN_TEST_ROOT:root, PASEO_PLAIN_TEST_CLI:'1', PASEO_PLAIN_FIXTURE_SEED:'0',
          GIT_CONFIG_NOSYSTEM:'1', GIT_CONFIG_GLOBAL:path.join(root, 'gitconfig'), GIT_ALLOW_PROTOCOL:'file',
          GIT_CONFIG_COUNT:'2', GIT_CONFIG_KEY_0:`url.${pathToFileURL(repository).href}.insteadOf`,
          GIT_CONFIG_VALUE_0:'https://github.com/scowalt/paseo-plain.git',
          GIT_CONFIG_KEY_1:'core.hooksPath', GIT_CONFIG_VALUE_1:hooks};
        fs.writeFileSync(env.GIT_CONFIG_GLOBAL, '');
        fs.symlinkSync(git, path.join(bin, 'git'));
        const cli = path.join(bin, 'node_modules/@getpaseo/cli');
        fs.mkdirSync(path.join(cli, 'bin'), {recursive:true});
        fs.writeFileSync(path.join(cli, 'package.json'), JSON.stringify({name:'@getpaseo/cli', version:'0.8.0', bin:{paseo:'bin/paseo'}}));
        fs.writeFileSync(path.join(cli, 'bin/paseo'), `#!/usr/bin/env node\nimport(${JSON.stringify(pathToFileURL(self).href)});\n`, {mode:0o700});
        fs.symlinkSync(path.join(cli, 'bin/paseo'), path.join(bin, 'paseo'));
        const configFile = path.join(home, 'config.json');
        fs.writeFileSync(configFile, JSON.stringify({version:1, pluginsEnabled:true,
          daemon:{listen:'127.0.0.1:19991'}, plugins:{unrelated:{source:'directory', path:'/fixture/other', enabled:false}}}));
        const run = (command, args, options = {}) => {
          const result = spawnSync(command, args, {env, cwd:repository, encoding:'utf8', timeout:30000, ...options});
          assert.equal(result.status, 0, `${path.basename(command)} failed: ${result.stdout} ${result.stderr}`);
          return result.stdout;
        };
        const gitRun = args => {
          if (args[0] !== 'init') assert.equal(run(git, ['rev-parse', '--absolute-git-dir']).trim(), path.join(repository, '.git'));
          return run(git, ['-c', 'user.name=Paseo Fixture', '-c', 'user.email=fixture@example.test', '-c', 'commit.gpgsign=false', ...args]);
        };
        gitRun(['init', '-b', 'release']);
        fs.writeFileSync(path.join(repository, 'paseo-plugin.json'), JSON.stringify({id:'paseo-plain', requirements:{paseo:'^0.8.0'}}));
        fs.writeFileSync(path.join(repository, 'index.server.ts'), 'throw new Error("fixture code must never execute");\n');
        gitRun(['add', '.']); gitRun(['commit', '-m', 'inert release']);
        let checkout = repository;
        if (variant !== 'directory') {
          const installed = JSON.parse(run(path.join(bin, 'paseo'), ['--host', '127.0.0.1:19991', 'plugin', 'add', '--json'], {
            env:{...env, PASEO_PLAIN_FIXTURE_SEED:'1'},
          }));
          checkout = installed.path;
        }
        const config = JSON.parse(fs.readFileSync(configFile));
        config.pluginsEnabled = variant !== 'disabled-git';
        config.plugins['paseo-plain'] = {source:'directory', path:checkout, enabled:variant !== 'disabled-git'};
        fs.writeFileSync(configFile, JSON.stringify(config));
        // Native lock creation only, owned by this fixture process; no daemon is started.
        const mask = process.umask(0o002);
        try { await acquirePidLock(home, '127.0.0.1:19991'); } finally { process.umask(mask); }
        const pidFile = path.join(home, 'paseo.pid');
        const pidBefore = fs.readFileSync(pidFile, 'utf8');
        const pidStat = fs.statSync(pidFile);
        assert.equal(pidStat.mode & 0o777, 0o664, 'Exercise the real legacy native PID mode.');
        const data = path.join(home, 'plugin-data/paseo-plain');
        const native = path.join(home, 'plugin-settings/paseo-plain');
        fs.mkdirSync(data, {recursive:true});
        fs.writeFileSync(path.join(data, 'configuration.json'), 'preferences');
        fs.writeFileSync(path.join(data, 'cache.json'), 'cached text');
        if (variant !== 'directory') {
          fs.mkdirSync(native, {recursive:true});
          fs.writeFileSync(path.join(native, 'voice.json'), 'native settings');
        } else {
          assert.equal(fs.existsSync(path.join(home, 'plugins')), false);
          assert.equal(fs.existsSync(native), false);
        }
        assert.match(run(process.execPath, ['-'], {input:helper}), /Paseo Plain removed;/);
        assert.equal(fs.readFileSync(path.join(data, 'configuration.json'), 'utf8'), 'preferences');
        assert.equal(fs.readFileSync(path.join(data, 'cache.json'), 'utf8'), 'cached text');
        assert.equal(fs.existsSync(native), false, 'Native removal really deletes plugin-settings.');
        assert.equal(fs.existsSync(checkout), variant === 'directory', 'External sources survive; managed checkout is deleted.');
        if (variant !== 'directory') {
          assert.equal(fs.readFileSync(path.join(home, 'setup-recovery/paseo-plain-retirement/plugin-settings/voice.json'), 'utf8'), 'native settings');
        }
        assert.equal(fs.readFileSync(pidFile, 'utf8'), pidBefore);
        assert.equal(fs.statSync(pidFile).ino, pidStat.ino);
        assert.equal(fs.statSync(pidFile).mode, pidStat.mode, 'Retirement must not chmod the native PID.');
        assert.match(run(process.execPath, ['-'], {input:helper}), /already absent/);
        const after = JSON.parse(fs.readFileSync(configFile));
        assert.equal(after.pluginsEnabled, config.pluginsEnabled);
        assert.deepEqual(after.plugins, {unrelated:config.plugins.unrelated});
        const calls = fs.readFileSync(path.join(home, 'calls.jsonl'), 'utf8').trim().split('\n').map(JSON.parse);
        assert.equal(calls.filter(args => args.includes('remove')).length, 1);
        assert.equal(calls.filter(args => args.includes('add')).length, variant === 'directory' ? 0 : 1);
        console.log(`PASS: real Paseo removal, ${variant}, unchanged native 0664 PID, saved data/settings, idempotent rerun.`);
      } finally { fs.rmSync(root, {recursive:true, force:true}); }
    }
  } finally { process.umask(previousUmask); }
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
