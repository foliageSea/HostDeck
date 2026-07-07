import { cp, mkdir, readFile, rm } from 'node:fs/promises'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { spawn } from 'node:child_process'

const currentDir = dirname(fileURLToPath(import.meta.url))
const uiRoot = resolve(currentDir, '..')
const repoRoot = resolve(uiRoot, '..')
const distDir = resolve(uiRoot, 'dist')
const pubspecPath = resolve(repoRoot, 'pubspec.yaml')

function run(command, args, options = {}) {
  return new Promise((resolveRun, reject) => {
    const child = spawn(command, args, {
      stdio: 'inherit',
      shell: process.platform === 'win32',
      ...options,
    })

    child.on('error', reject)
    child.on('close', (code) => {
      if (code === 0) {
        resolveRun()
        return
      }

      reject(new Error(`Command failed with exit code ${code}: ${command} ${args.join(' ')}`))
    })
  })
}

async function resolveFlutterWebAssetDir() {
  const pubspec = await readFile(pubspecPath, 'utf8')
  const assetMatch = pubspec.match(/^\s*-\s+(assets\/web\/)\s*$/m)

  if (!assetMatch) {
    throw new Error(`No assets/web/ entry found in ${pubspecPath}`)
  }

  return resolve(repoRoot, assetMatch[1])
}

const targetDir = await resolveFlutterWebAssetDir()

console.log('Building frontend...')
await run('pnpm', ['build'], { cwd: uiRoot })

console.log(`Syncing ${distDir} to ${targetDir}...`)
await rm(targetDir, { recursive: true, force: true })
await mkdir(targetDir, { recursive: true })
await cp(distDir, targetDir, { recursive: true })

console.log(`Flutter web assets updated: ${targetDir}`)
