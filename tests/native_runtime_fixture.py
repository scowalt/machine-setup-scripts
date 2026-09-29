"""Copy only trusted Node/npm runtime files into a disposable fixture prefix.

A directory symlink is NOT read-only isolation: mise repair could otherwise write
through it to the real installation. Never copy or execute installed agent tools.
"""
from pathlib import Path
import shutil


def copy_node_runtime(node, destination):
    node = Path(node).resolve(strict=True)
    destination = Path(destination)
    (destination / 'bin').mkdir(parents=True)
    shutil.copy2(node, destination / 'bin/node')
    npm = node.parent.parent / 'lib/node_modules/npm'
    if not npm.is_dir():
        raise RuntimeError('Native Node fixture requires an existing npm distribution')
    shutil.copytree(npm, destination / 'lib/node_modules/npm', symlinks=False)
    for name, entry in (('npm', 'npm-cli.js'), ('npx', 'npx-cli.js')):
        (destination / 'bin' / name).symlink_to('../lib/node_modules/npm/bin/' + entry)
    return destination / 'bin/node'
