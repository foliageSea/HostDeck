import { beforeEach, describe, expect, it, vi } from 'vitest'
import type { PortForwardRule } from '@/api/port-forward'

const { list, create, start } = vi.hoisted(() => ({
  list: vi.fn(),
  create: vi.fn(),
  start: vi.fn(),
}))
vi.mock('@/api/port-forward', () => ({ portForwardApi: { list, create, start } }))
import { createDockerHttpForward, parseDockerHttpPort } from '../dockerPortForward'

describe('Docker HTTP forwards', () => {
  beforeEach(() => vi.resetAllMocks())

  it.each([
    ['0.0.0.0:8080->80/tcp', '127.0.0.1', 8080],
    ['127.0.0.1:8081->80/tcp', '127.0.0.1', 8081],
    ['192.168.1.2:9000->80/tcp', '192.168.1.2', 9000],
    [':::8080->80/tcp', '::1', 8080],
    ['[::1]:8080->80/tcp', '::1', 8080],
    ['8080->80/tcp', '127.0.0.1', 8080],
  ])('parses %s', (text, remoteHost, remotePort) => {
    expect(parseDockerHttpPort(text)).toEqual({ remoteHost, remotePort })
  })

  it.each(['80/tcp', '0.0.0.0:53->53/udp', '0.0.0.0:65536->80/tcp', 'invalid'])('rejects %s', (text) => {
    expect(parseDockerHttpPort(text)).toBeNull()
  })

  const target = { remoteHost: '127.0.0.1', remotePort: 8080 }
  const rule = {
    id: 12, protocol: 'http', connectionId: 'conn-2', status: 'running', ...target,
    accessPath: '/port-forward/12/',
  } as PortForwardRule

  it('reuses an existing saved HTTP forward and never creates a duplicate', async () => {
    const running = { ...rule, connectionId: 'conn-1' }
    list.mockResolvedValue([running, { ...rule, protocol: 'tcp' }, rule])
    expect(await createDockerHttpForward('conn-2', 'web', target)).toBe(running)
    expect(create).not.toHaveBeenCalled()
    expect(start).not.toHaveBeenCalled()
  })

  it('starts a saved stopped HTTP forward instead of creating another rule', async () => {
    const stopped = { ...rule, status: 'stopped' as const, connectionId: null }
    const started = { ...stopped, status: 'running' as const, connectionId: 'conn-2' }
    list.mockResolvedValue([stopped])
    start.mockResolvedValue(started)
    expect(await createDockerHttpForward('conn-2', 'web', target)).toBe(started)
    expect(start).toHaveBeenCalledWith(12, 'conn-2')
    expect(create).not.toHaveBeenCalled()
  })

  it('deduplicates concurrent clicks and creates without a local port', async () => {
    list.mockResolvedValue([])
    create.mockResolvedValue(rule)
    const first = createDockerHttpForward('conn-2', 'web', target)
    const second = createDockerHttpForward('conn-2', 'web', target)
    expect(first).toBe(second)
    await expect(first).resolves.toBe(rule)
    expect(create).toHaveBeenCalledOnce()
    expect(create).toHaveBeenCalledWith({
      protocol: 'http', name: 'web:8080', enabled: true, connectionId: 'conn-2', ...target,
    })
  })

  it('allows retry after a creation failure', async () => {
    list.mockResolvedValue([])
    create.mockRejectedValueOnce(new Error('SSH disconnected')).mockResolvedValue(rule)
    await expect(createDockerHttpForward('conn-2', 'web', target)).rejects.toThrow('SSH disconnected')
    await expect(createDockerHttpForward('conn-2', 'web', target)).resolves.toBe(rule)
  })
})
