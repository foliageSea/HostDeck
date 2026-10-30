const { createHash } = require('node:crypto')
const fs = require('node:fs/promises')
const path = require('node:path')

function setAppBuildUuid(binary, appId, electronVersion) {
  if (binary.length < 32 || binary.readUInt32LE(0) !== 0xfeedfacf) {
    throw new Error('Expected a thin 64-bit Mach-O executable')
  }
  const commandCount = binary.readUInt32LE(16)
  const commandEnd = 32 + binary.readUInt32LE(20)
  if (commandEnd > binary.length) throw new Error('Truncated Mach-O load commands')

  let offset = 32
  let uuidOffset = null
  for (let index = 0; index < commandCount; index += 1) {
    if (offset + 8 > commandEnd) throw new Error('Truncated Mach-O load command')
    const command = binary.readUInt32LE(offset)
    const size = binary.readUInt32LE(offset + 4)
    if (size < 8 || offset + size > commandEnd) {
      throw new Error('Invalid Mach-O load command size')
    }
    if (command === 0x1b) {
      if (size !== 24 || uuidOffset !== null) throw new Error('Invalid Mach-O LC_UUID')
      uuidOffset = offset + 8
    }
    offset += size
  }
  if (offset !== commandEnd || uuidOffset === null) {
    throw new Error('Missing LC_UUID or invalid Mach-O load commands')
  }

  // Scope Electron's shared build UUID to this app before code signing (Apple TN3178).
  const uuid = createHash('sha256')
    .update(
      JSON.stringify([appId, electronVersion, binary.readUInt32LE(4), binary.readUInt32LE(8)]),
    )
    .digest()
    .subarray(0, 16)
  uuid[6] = (uuid[6] & 0x0f) | 0x80
  uuid[8] = (uuid[8] & 0x3f) | 0x80
  uuid.copy(binary, uuidOffset)
  return uuid.toString('hex')
}

async function afterPack({ appOutDir, electronPlatformName, packager }) {
  if (electronPlatformName !== 'darwin') return
  const { macBundleIdentifier: appId, productFilename } = packager.appInfo
  const electronVersion = packager.config.electronVersion
  if (!appId || !electronVersion)
    throw new Error('Missing app ID or Electron version for build UUID')
  const executable = path.join(
    appOutDir,
    `${productFilename}.app`,
    'Contents',
    'MacOS',
    productFilename,
  )
  const binary = await fs.readFile(executable)
  const uuid = setAppBuildUuid(binary, appId, electronVersion)
  await fs.writeFile(executable, binary)
  console.log(`Set macOS main executable build UUID for ${appId}: ${uuid}`)
}

module.exports = afterPack
module.exports.setAppBuildUuid = setAppBuildUuid
