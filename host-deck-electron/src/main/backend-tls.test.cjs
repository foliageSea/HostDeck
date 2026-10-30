const assert = require('node:assert/strict')
const { test } = require('node:test')
const { X509Certificate } = require('node:crypto')
const { rootCertificates } = require('node:tls')
const { certificateMatches, configureBackendTrust, probeOptions } = require('./backend-tls.cjs')

const pem = rootCertificates.find((value) => {
  const cert = new X509Certificate(value)
  return Date.parse(cert.validFrom) < Date.now() && Date.parse(cert.validTo) > Date.now()
})
const certificate = new X509Certificate(pem)

test('backend trust requires both the configured hostname and certificate', () => {
  let verify
  configureBackendTrust(
    {
      setCertificateVerifyProc: (handler) => {
        verify = handler
      },
    },
    'https://127.0.0.1:18080',
    pem,
  )
  let result
  verify({ hostname: '127.0.0.1', certificate: { data: pem } }, (value) => {
    result = value
  })
  assert.equal(result, 0)
  verify({ hostname: 'example.com', certificate: { data: pem } }, (value) => {
    result = value
  })
  assert.equal(result, -3)
  verify({ hostname: '127.0.0.1', certificate: { data: 'invalid' } }, (value) => {
    result = value
  })
  assert.equal(result, -3)
  assert.equal(certificateMatches(pem, 'wrong fingerprint'), false)
})

test('HTTPS readiness probe pins the supplied certificate', () => {
  const options = probeOptions(pem)
  assert.equal(options.ca, pem)
  assert.equal(options.checkServerIdentity('127.0.0.1', certificate), undefined)
  assert.ok(options.checkServerIdentity('127.0.0.1', { fingerprint256: 'wrong' }) instanceof Error)
  assert.deepEqual(probeOptions(null), {})
})

test('HTTP startup restores Chromium certificate verification', () => {
  let verify
  configureBackendTrust(
    {
      setCertificateVerifyProc: (handler) => {
        verify = handler
      },
    },
    'http://127.0.0.1:18080',
    null,
  )
  verify({ hostname: '127.0.0.1', certificate: { data: pem } }, (result) =>
    assert.equal(result, -3),
  )
})
