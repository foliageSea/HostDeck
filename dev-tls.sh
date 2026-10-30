#!/usr/bin/env bash

set -euo pipefail

project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  printf 'Usage: ./dev-tls.sh [--check] [dev.sh options]\n\n'
  printf '读取当前自签名证书并启动 HTTPS 开发环境。\n'
  printf '  --check  仅检查证书并显示路径，不启动服务。\n\n'
  exec bash "$project_root/dev.sh" --help
fi

check_only=false
if [[ "${1:-}" == "--check" ]]; then
  check_only=true
  shift
fi

certificate_directory="$(node <<'NODE'
const fs = require('node:fs')
const os = require('node:os')
const path = require('node:path')
const { X509Certificate, createPrivateKey } = require('node:crypto')

try {
  const base = process.platform === 'darwin'
    ? path.join(os.homedir(), 'Library', 'Application Support')
    : process.env.XDG_DATA_HOME || path.join(os.homedir(), '.local', 'share')
  const current = path.join(base, 'host_deck')
  const dataDirectory = fs.existsSync(current) ? current : path.join(base, 'ssh_tool')
  const config = JSON.parse(fs.readFileSync(path.join(dataDirectory, 'tls.json'), 'utf8'))
  if (config.source !== 'selfSigned' || !/^[a-f0-9]{32}$/.test(config.revision || '')) {
    throw new Error('请先在“设置 → 安全 → TLS 访问”中生成并保存自签名证书。')
  }
  const directory = path.join(dataDirectory, 'tls', config.revision)
  const certificate = new X509Certificate(fs.readFileSync(path.join(directory, 'cert.pem')))
  const privateKey = createPrivateKey(fs.readFileSync(path.join(directory, 'key.pem')))
  if (!certificate.checkPrivateKey(privateKey)) throw new Error('证书与私钥不匹配。')
  if (Date.now() < Date.parse(certificate.validFrom) || Date.now() >= Date.parse(certificate.validTo)) {
    throw new Error('证书尚未生效或已过期，请重新生成证书。')
  }
  process.stdout.write(directory)
} catch (error) {
  console.error(`无法加载当前自签名证书：${error.message}`)
  process.exitCode = 1
}
NODE
)"

export HOSTDECK_DEV_TLS=true
export HOSTDECK_DEV_TLS_CERT="$certificate_directory/cert.pem"
export HOSTDECK_DEV_TLS_KEY="$certificate_directory/key.pem"
export HOSTDECK_TLS=true

printf '开发证书：%s\n' "$HOSTDECK_DEV_TLS_CERT"
printf '开发私钥：%s\n' "$HOSTDECK_DEV_TLS_KEY"

if [[ "$check_only" == true ]]; then
  printf '证书检查通过。\n'
  exit 0
fi

exec bash "$project_root/dev.sh" "$@"
