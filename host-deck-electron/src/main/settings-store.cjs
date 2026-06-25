const fs = require('node:fs')
const path = require('node:path')

function createSettingsStore(app) {
  function settingsPath() {
    return path.join(app.getPath('userData'), 'electron-settings.json')
  }

  function read() {
    try {
      const rawValue = fs.readFileSync(settingsPath(), 'utf8')
      const value = JSON.parse(rawValue)
      return value && typeof value === 'object' ? value : {}
    } catch {
      return {}
    }
  }

  function write(settings) {
    const targetPath = settingsPath()
    fs.mkdirSync(path.dirname(targetPath), { recursive: true })
    fs.writeFileSync(targetPath, JSON.stringify(settings, null, 2))
  }

  return {
    read,
    write,
  }
}

module.exports = {
  createSettingsStore,
}
