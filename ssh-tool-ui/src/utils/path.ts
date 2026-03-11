/**
 * Simple POSIX path utilities
 */

/**
 * Normalize a path, removing '..' and '.' segments
 */
export function normalize(path: string): string {
    const isAbsolute = path.startsWith('/')
    const segments = path.split('/').filter(p => p && p !== '.')
    const stack: string[] = []

    for (const segment of segments) {
        if (segment === '..') {
            if (stack.length && stack[stack.length - 1] !== '..') {
                stack.pop()
            } else if (!isAbsolute) {
                stack.push('..')
            }
        } else {
            stack.push(segment)
        }
    }

    const result = stack.join('/')

    if (isAbsolute) {
        return '/' + result
    }
    return result || '.'
}

/**
 * Join all arguments together and normalize the resulting path
 */
export function join(...paths: string[]): string {
    return normalize(paths.filter(p => p).join('/'))
}

/**
 * Resolve a sequence of paths or path segments into an absolute path.
 * The resulting path is normalized and trailing slashes are removed unless the path is resolved to the root directory.
 */
export function resolve(...paths: string[]): string {
    let resolvedPath = ''

    for (let i = paths.length - 1; i >= 0; i--) {
        const path = paths[i]
        if (path) {
            if (resolvedPath) {
                resolvedPath = `${path}/${resolvedPath}`
            } else {
                resolvedPath = path
            }

            if (path.startsWith('/')) {
                return normalize(resolvedPath)
            }
        }
    }

    // If we haven't found an absolute path, we assume the base is root '/'
    return normalize('/' + resolvedPath)
}

/**
 * Get the directory name of a path
 */
export function dirname(path: string): string {
    const result = normalize(path)
    if (result === '/') return '/'
    const lastSlashIndex = result.lastIndexOf('/')
    if (lastSlashIndex === -1) return '.'
    if (lastSlashIndex === 0) return '/'
    return result.slice(0, lastSlashIndex)
}

/**
 * Get the base name of a path
 */
export function basename(path: string): string {
    const result = normalize(path)
    if (result === '/') return ''
    const lastSlashIndex = result.lastIndexOf('/')
    return result.slice(lastSlashIndex + 1)
}
