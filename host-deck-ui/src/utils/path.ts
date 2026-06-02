export function normalize(path: string): string {
  const isAbsolute = path.startsWith('/')
  const segments = path.split('/').filter((segment) => segment && segment !== '.')
  const stack: string[] = []

  for (const segment of segments) {
    if (segment === '..') {
      if (stack.length > 0) {
        stack.pop()
      }
      continue
    }

    stack.push(segment)
  }

  if (isAbsolute) {
    return `/${stack.join('/')}` || '/'
  }

  return stack.join('/') || '.'
}

export function resolve(...paths: string[]): string {
  let resolvedPath = ''

  for (let index = paths.length - 1; index >= 0; index -= 1) {
    const current = paths[index]
    if (!current) {
      continue
    }

    resolvedPath = resolvedPath ? `${current}/${resolvedPath}` : current
    if (current.startsWith('/')) {
      return normalize(resolvedPath)
    }
  }

  return normalize(`/${resolvedPath}`)
}

export function dirname(path: string): string {
  const normalizedPath = normalize(path)
  if (normalizedPath === '/') {
    return '/'
  }

  const lastSlashIndex = normalizedPath.lastIndexOf('/')
  if (lastSlashIndex <= 0) {
    return '/'
  }

  return normalizedPath.slice(0, lastSlashIndex)
}

export function basename(path: string): string {
  const normalizedPath = normalize(path)
  if (normalizedPath === '/') {
    return ''
  }

  return normalizedPath.slice(normalizedPath.lastIndexOf('/') + 1)
}
