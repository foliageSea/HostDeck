const path = require('node:path')

const { normalizeUrl } = require('../shared/dev-server.cjs')

function createShellPageLoader({ rendererHtmlRoot, shellDevServerUrl, useShellDevServer }) {
  const normalizedShellUrl = normalizeUrl(shellDevServerUrl)
  const rendererHtmlBasePath = 'src/renderer'

  return function loadShellPage(window, pageName) {
    if (useShellDevServer) {
      return window.loadURL(`${normalizedShellUrl}/${rendererHtmlBasePath}/${pageName}.html`)
    }

    return window.loadFile(path.join(rendererHtmlRoot, `${pageName}.html`))
  }
}

module.exports = {
  createShellPageLoader,
}
