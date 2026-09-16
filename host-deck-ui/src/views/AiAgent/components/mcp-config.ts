export interface ParsedMcpConfig {
  headers?: Record<string, string>
  name?: string
  url?: string
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}

function stringHeaders(value: unknown) {
  if (!isRecord(value) || Object.values(value).some((item) => typeof item !== 'string')) {
    throw new Error('请求头必须是字符串键值组成的 JSON 对象。')
  }
  return value as Record<string, string>
}

function nameFromUrl(value: string) {
  try {
    const labels = new URL(value).hostname.split('.').filter((label) => label && label !== 'mcp')
    return labels[0]
  } catch {
    return undefined
  }
}

export function parseMcpConfig(source: string): ParsedMcpConfig {
  const parsed: unknown = JSON.parse(source)
  if (!isRecord(parsed)) throw new Error('MCP 配置必须是 JSON 对象。')

  if ('url' in parsed || 'headers' in parsed || 'type' in parsed) {
    if (typeof parsed.url !== 'string' || !parsed.url.trim()) {
      throw new Error('完整 MCP 配置必须包含 URL。')
    }
    if (parsed.type !== undefined && typeof parsed.type !== 'string') {
      throw new Error('MCP 配置的 type 必须是字符串。')
    }
    return {
      headers: parsed.headers === undefined ? undefined : stringHeaders(parsed.headers),
      name:
        typeof parsed.name === 'string' && parsed.name.trim()
          ? parsed.name.trim()
          : nameFromUrl(parsed.url),
      url: parsed.url.trim(),
    }
  }

  return { headers: stringHeaders(parsed) }
}
