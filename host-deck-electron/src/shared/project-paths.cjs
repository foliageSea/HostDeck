const path = require('node:path')

const projectRoot = path.resolve(__dirname, '..', '..')
const repoRoot = path.resolve(projectRoot, '..')
const frontendRoot = path.join(repoRoot, 'host-deck-ui')
const frontendViteConfigPath = path.join(frontendRoot, 'vite.config.ts')
const rendererDistRoot = path.join(projectRoot, 'dist')
const rendererHtmlRoot = path.join(rendererDistRoot, 'src', 'renderer')
const shellViteConfigPath = path.join(projectRoot, 'vite.config.mjs')

module.exports = {
  frontendRoot,
  frontendViteConfigPath,
  projectRoot,
  rendererDistRoot,
  rendererHtmlRoot,
  repoRoot,
  shellViteConfigPath,
}
