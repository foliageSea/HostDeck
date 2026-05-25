import { readFile, writeFile } from 'node:fs/promises'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const currentDir = dirname(fileURLToPath(import.meta.url))
const uiRoot = resolve(currentDir, '..')
const repoRoot = resolve(uiRoot, '..')
const packageJsonPath = resolve(uiRoot, 'package.json')
const pubspecPath = resolve(repoRoot, 'pubspec.yaml')

const pubspec = await readFile(pubspecPath, 'utf8')
const versionMatch = pubspec.match(/^version:\s*([^\s#]+)\s*(?:#.*)?$/m)

if (!versionMatch) {
  throw new Error(`No version field found in ${pubspecPath}`)
}

const version = versionMatch[1]
const packageJson = JSON.parse(await readFile(packageJsonPath, 'utf8'))

if (packageJson.version === version) {
  console.log(`package.json version already matches pubspec.yaml: ${version}`)
  process.exit(0)
}

packageJson.version = version
await writeFile(packageJsonPath, `${JSON.stringify(packageJson, null, 2)}\n`)
console.log(`Synced package.json version to ${version}`)
