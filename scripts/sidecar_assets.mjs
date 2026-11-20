#!/usr/bin/env node
import { spawnSync } from 'node:child_process'
import { createHash } from 'node:crypto'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const protocol = 1
const dartVersion = '3.11.0'
const packageDir = fileURLToPath(new URL('../host-deck-sidecar/', import.meta.url))
const architectures = {
  amd64: { node: 'x64', dart: 'x64', elf: 62, loader: '/lib64/ld-linux-x86-64.so.2' },
  arm64: { node: 'arm64', dart: 'arm64', elf: 183, loader: '/lib/ld-linux-aarch64.so.1' },
}
const arches = Object.keys(architectures)
const manifestFile = 'manifest.json'
const artifactName = (arch) => 'hostdeck-file-sidecar-linux-' + arch

function check(condition, message) {
  if (!condition) throw new Error(message)
}

function checkVersion(version) {
  check(typeof version === 'string' && /^[0-9A-Za-z][0-9A-Za-z.+_-]*$/.test(version),
    'Expected a nonempty SideCar version containing only letters, digits, ., +, _ or -')
}

function readFile(file) {
  check(fs.lstatSync(file).isFile(), 'Expected a regular file: ' + file)
  return fs.readFileSync(file)
}

function objectWithKeys(value, keys) {
  return value !== null && typeof value === 'object' && !Array.isArray(value) &&
    Object.keys(value).length === keys.length && keys.every((key) => Object.hasOwn(value, key))
}

function inspectArtifact(dir, arch) {
  const file = artifactName(arch)
  const bytes = readFile(path.join(dir, file))
  const { elf, loader } = architectures[arch]
  check(bytes.length >= 64 && bytes.subarray(0, 7).equals(Buffer.from([0x7f, 0x45, 0x4c, 0x46, 2, 1, 1])) &&
    [2, 3].includes(bytes.readUInt16LE(16)) && bytes.readUInt16LE(18) === elf,
    file + ' is not a Linux ELF64 executable for ' + arch)

  // Check PT_INTERP as well as e_machine: musl or other Linux loaders aren't supported here.
  const headerOffset = Number(bytes.readBigUInt64LE(32))
  const entrySize = bytes.readUInt16LE(54)
  const entryCount = bytes.readUInt16LE(56)
  check(headerOffset >= 64 && entrySize === 56 && headerOffset + entryCount * entrySize <= bytes.length,
    file + ' has an invalid ELF program header table')
  let hasGlibcLoader = false
  for (let i = 0; i < entryCount; i++) {
    const header = headerOffset + i * entrySize
    if (bytes.readUInt32LE(header) !== 3) continue // PT_INTERP
    const offset = Number(bytes.readBigUInt64LE(header + 8))
    const size = Number(bytes.readBigUInt64LE(header + 32))
    hasGlibcLoader = size === loader.length + 1 && offset + size <= bytes.length &&
      bytes.subarray(offset, offset + size).equals(Buffer.from(loader + '\0'))
    break
  }
  check(hasGlibcLoader, file + ' does not use the expected glibc loader: ' + loader)
  return { file, size: bytes.length, sha256: createHash('sha256').update(bytes).digest('hex') }
}

function smokeTest(dir, arch, version) {
  const file = path.join(dir, artifactName(arch))
  const run = (args) => {
    const result = spawnSync(file, args, { encoding: 'utf8', timeout: 10_000 })
    if (result.error) throw result.error
    check(result.status === 0, file + ' failed its ' + args[0] + ' smoke test: ' + result.stderr)
    return result.stdout
  }
  const output = run(['--version', '--json'])
  const info = JSON.parse(output)
  check(objectWithKeys(info, ['version', 'protocol']) && info.version === version && info.protocol === protocol,
    file + ' returned an unexpected SideCar version/protocol: ' + output)

  // Exercise the Linux filesystem ABI as well as the executable and protocol header.
  const smokeDir = fs.mkdtempSync(path.join(fs.realpathSync(os.tmpdir()), 'hostdeck-sidecar-smoke-'))
  try {
    const source = path.join(smokeDir, 'source')
    const target = path.join(smokeDir, 'target')
    const payload = Buffer.from('HostDeck SideCar smoke test')
    fs.writeFileSync(source, payload)
    run(['copy', source, target])
    check(readFile(target).equals(payload), file + ' copied unexpected content')
    const moved = path.join(smokeDir, 'moved')
    run(['move', target, moved])
    check(!fs.existsSync(target) && readFile(moved).equals(payload), file + ' moved unexpected content')
    const tree = path.join(smokeDir, 'tree')
    const nested = path.join(tree, 'nested')
    fs.mkdirSync(nested, { recursive: true })
    fs.renameSync(moved, path.join(tree, 'payload'))
    fs.symlinkSync('../payload', path.join(nested, 'link'))
    for (const suffix of ['zip', 'tar.gz']) {
      const archive = path.join(smokeDir, 'archive.' + suffix)
      const extracted = path.join(smokeDir, 'output-' + suffix)
      run(['compress', tree, archive])
      run(['extract', archive, extracted])
      check(readFile(path.join(extracted, 'tree', 'payload')).equals(payload), file + ' extracted unexpected content')
      const link = path.join(extracted, 'tree', 'nested', 'link')
      check(fs.readlinkSync(link) === '../payload' && fs.readFileSync(link).equals(payload), file + ' did not preserve the internal link')
    }
  } finally {
    fs.rmSync(smokeDir, { recursive: true, force: true })
  }
}

function dart(args, capture = false) {
  const result = spawnSync('dart', args, { cwd: packageDir, encoding: 'utf8', stdio: capture ? 'pipe' : 'inherit' })
  if (result.error) throw result.error
  check(result.status === 0, 'dart ' + args.join(' ') + ' failed: ' + (result.status ?? result.signal))
  return capture ? result.stdout + result.stderr : ''
}

function build(dir, version, targets) {
  checkVersion(version)
  check(process.platform === 'linux', 'SideCar AOT builds require a Linux Dart SDK')
  check(targets.length > 0 && new Set(targets).size === targets.length && targets.every((arch) => arches.includes(arch)),
    'Specify amd64 and/or arm64 as distinct target architectures')
  const sdkInfo = dart(['--version'], true).trim()
  check(sdkInfo.match(/^Dart SDK version: ([^ ]+)/)?.[1] === dartVersion,
    'SideCar builds require Dart ' + dartVersion + '; found: ' + sdkInfo)
  fs.mkdirSync(dir, { recursive: true })
  dart(['pub', 'get', '--enforce-lockfile'])
  for (const arch of targets) {
    const target = architectures[arch]
    const args = ['compile', 'exe']
    const native = target.node === process.arch
    if (!native) args.push('--target-os=linux', '--target-arch=' + target.dart)
    const output = path.join(dir, artifactName(arch))
    dart([...args, '-DHOSTDECK_SIDECAR_VERSION=' + version, '-o', output, 'bin/hostdeck_file_sidecar.dart'])
    inspectArtifact(dir, arch)
    if (native) smokeTest(dir, arch, version)
  }
}

function makeManifest(dir, version) {
  checkVersion(version)
  const artifacts = Object.fromEntries(arches.map((arch) => [arch, inspectArtifact(dir, arch)]))
  fs.writeFileSync(path.join(dir, manifestFile), JSON.stringify({ protocol, version, artifacts }, null, 2) + '\n')
}

function verifyManifest(dir, version) {
  const file = path.join(dir, manifestFile)
  const manifest = JSON.parse(readFile(file).toString('utf8'))
  check(objectWithKeys(manifest, ['protocol', 'version', 'artifacts']) && manifest.protocol === protocol &&
    objectWithKeys(manifest.artifacts, arches), 'Invalid SideCar manifest: ' + file)
  checkVersion(manifest.version)
  check(version === undefined || manifest.version === version,
    'SideCar manifest version mismatch: expected ' + version + ', found ' + manifest.version)
  for (const arch of arches) {
    const expected = inspectArtifact(dir, arch)
    const actual = manifest.artifacts[arch]
    const keys = Object.keys(expected)
    check(objectWithKeys(actual, keys) && keys.every((key) => actual[key] === expected[key]),
      'SideCar manifest metadata mismatch for ' + arch + ': ' + file)
  }
}

function stageBundle(bundle) {
  const configuredDir = process.env.HOSTDECK_SIDECAR_ASSETS_DIR
  if (!configuredDir) {
    check(process.env.HOSTDECK_REQUIRE_SIDECARS !== '1', 'Set HOSTDECK_SIDECAR_ASSETS_DIR to a prepared SideCar asset directory')
    console.log('Skipping SideCar assets (HOSTDECK_SIDECAR_ASSETS_DIR not set).')
    return
  }
  const source = path.resolve(configuredDir)
  verifyManifest(source)
  const destination = path.join(bundle, 'sidecars')
  fs.mkdirSync(destination, { recursive: true })
  for (const file of [manifestFile, ...arches.map(artifactName)]) {
    const target = path.join(destination, file)
    fs.copyFileSync(path.join(source, file), target)
    if (process.platform !== 'win32') fs.chmodSync(target, file === manifestFile ? 0o644 : 0o755)
  }
  verifyManifest(destination)
  console.log('Staged SideCar assets in ' + destination)
}

try {
  const [command, directory, version, ...rest] = process.argv.slice(2)
  check(directory, 'Usage: sidecar_assets.mjs build|manifest|verify <asset-dir> [version] [amd64|arm64 ...], or stage <bundle-root>')
  const dir = path.resolve(directory)
  switch (command) {
    case 'build': build(dir, version, rest); break
    case 'manifest': makeManifest(dir, version); break
    case 'verify': verifyManifest(dir, version); break
    case 'stage': stageBundle(dir); break
    default: throw new Error('Unknown SideCar assets command: ' + command)
  }
} catch (error) {
  console.error('SideCar assets: ' + error.message)
  process.exitCode = 1
}
