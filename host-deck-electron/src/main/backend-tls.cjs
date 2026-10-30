const { X509Certificate } = require('node:crypto')

function certificateMatches(pem, fingerprint) {
  if (!pem || !fingerprint) return false
  const certificate = new X509Certificate(pem)
  const now = Date.now()
  return (
    now >= Date.parse(certificate.validFrom) &&
    now < Date.parse(certificate.validTo) &&
    certificate.fingerprint256.toLowerCase() === fingerprint.toLowerCase()
  )
}

function configureBackendTrust(session, baseUrl, certificatePem) {
  const url = new URL(baseUrl)
  session.setCertificateVerifyProc((request, callback) => {
    try {
      if (
        url.protocol === 'https:' &&
        request.hostname === url.hostname &&
        certificateMatches(
          certificatePem,
          new X509Certificate(request.certificate.data).fingerprint256,
        )
      ) {
        callback(0)
        return
      }
    } catch {
      // Invalid certificate data keeps Chromium's normal verification result.
    }
    callback(-3)
  })
}

function probeOptions(certificatePem) {
  if (!certificatePem) return {}
  return {
    ca: certificatePem,
    allowPartialTrustChain: true,
    checkServerIdentity: (_host, certificate) => {
      if (!certificateMatches(certificatePem, certificate.fingerprint256)) {
        return new Error('HostDeck backend certificate does not match')
      }
    },
  }
}

module.exports = { certificateMatches, configureBackendTrust, probeOptions }
