export type PermissionSubject = 'owner' | 'group' | 'others'
export type PermissionAction = 'read' | 'write' | 'execute'
export type PermissionMatrix = Record<PermissionSubject, Record<PermissionAction, boolean>>

const permissionSubjects: PermissionSubject[] = ['owner', 'group', 'others']
const permissionPattern = /^[dlpscb-][rwxStTs-]{9}$/

export function createPermissionMatrix(): PermissionMatrix {
  return {
    owner: { read: false, write: false, execute: false },
    group: { read: false, write: false, execute: false },
    others: { read: false, write: false, execute: false },
  }
}

export function getPermissionFromLongname(longname?: string): string {
  const permission = longname?.trim().split(/\s+/)[0]
  return permission && permissionPattern.test(permission) ? permission : '-'
}

export function permissionToMode(permission: string): string | null {
  if (!permissionPattern.test(permission)) {
    return null
  }

  const value = permission.slice(1)
  return [0, 3, 6]
    .map((start) => {
      const read = value[start] === 'r' ? 4 : 0
      const write = value[start + 1] === 'w' ? 2 : 0
      const execute = /[xst]/.test(value[start + 2] ?? '') ? 1 : 0
      return (read + write + execute).toString()
    })
    .join('')
}

export function permissionModeToMatrix(mode: string): PermissionMatrix {
  const normalizedMode = mode.length === 4 ? mode.slice(1) : mode
  const matrix = createPermissionMatrix()

  permissionSubjects.forEach((subject, index) => {
    const digit = Number(normalizedMode[index] ?? '0')
    matrix[subject] = {
      read: (digit & 4) !== 0,
      write: (digit & 2) !== 0,
      execute: (digit & 1) !== 0,
    }
  })

  return matrix
}

export function permissionMatrixToMode(matrix: PermissionMatrix): string {
  return permissionSubjects
    .map((subject) => {
      const value = matrix[subject]
      return ((value.read ? 4 : 0) + (value.write ? 2 : 0) + (value.execute ? 1 : 0)).toString()
    })
    .join('')
}
