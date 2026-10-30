import { flushPromises, shallowMount, type VueWrapper } from '@vue/test-utils'
import { defineComponent, reactive } from 'vue'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { CodeServerSession, CodeServerTargetStatus } from '@/api/code-server'
import CodeServerView from '../index.vue'

const mocks = vi.hoisted(() => ({
  api: { status: vi.fn(), listPackages: vi.fn(), start: vi.fn(), stop: vi.fn() },
  message: { success: vi.fn(), error: vi.fn(), warning: vi.fn() },
  ssh: { connectionId: 'conn-1', isConnected: true, username: 'alice', host: 'host-1', port: 22 },
  updateWindowProps: vi.fn(),
}))

vi.mock('@/api/code-server', () => ({ codeServerApi: mocks.api, uploadPackage: vi.fn() }))
vi.mock('@/stores/ssh', () => ({ useSshStore: () => mocks.ssh }))
vi.mock('@/stores/settings', () => ({ useSettingsStore: () => ({ isDark: false }) }))
vi.mock('@/stores/desktop', () => ({
  useDesktopStore: () => ({ updateWindowProps: mocks.updateWindowProps }),
}))
vi.mock('@/lib/ui', () => ({
  getUiApi: () => ({ dialog: { warning: vi.fn() }, message: mocks.message }),
}))

const ButtonStub = defineComponent({
  props: ['disabled', 'loading'],
  emits: ['click'],
  template: '<button :disabled="disabled || loading" @click="$emit(\'click\', $event)"><slot /></button>',
})
const AlertStub = defineComponent({ template: '<div role="alert"><slot /></div>' })

function targetStatus(running = false): CodeServerTargetStatus {
  return {
    preflight: {
      arch: 'x86_64',
      libc: '2.35',
      diskFreeBytes: 1024 ** 3,
      installedVersion: '4.143.1',
      issues: [],
      supported: true,
    },
    session: running ? {
      id: 'ide-1',
      state: 'running',
      error: null,
      version: '4.143.1',
      progress: null,
      startedAt: null,
      url: '/ide/ide-1/',
    } : null,
  }
}

function deferred<T>() {
  let resolve!: (value: T) => void
  const promise = new Promise<T>((resolvePromise) => {
    resolve = resolvePromise
  })
  return { promise, resolve }
}

let wrapper: VueWrapper | undefined
let observer: MutationObserver | undefined

async function mountView() {
  wrapper = shallowMount(CodeServerView, {
    props: { windowId: 'code-window', toolbarCollapsed: false },
    global: {
      stubs: {
        NButton: ButtonStub,
        NAlert: AlertStub,
        NTag: true,
        NEmpty: true,
        NSpin: true,
        NSelect: true,
        NInput: true,
        NPopconfirm: true,
        NDrawerContent: true,
        NDrawer: true,
      },
    },
  })
  await flushPromises()
  return wrapper
}

function observeFrameInsertions(view: VueWrapper) {
  const insertions: HTMLIFrameElement[] = []
  observer = new MutationObserver((records) => {
    for (const record of records) {
      for (const node of record.addedNodes) {
        if (!(node instanceof Element)) continue
        if (node instanceof HTMLIFrameElement) insertions.push(node)
        insertions.push(...node.querySelectorAll('iframe'))
      }
    }
  })
  observer.observe(view.element, { childList: true, subtree: true })
  return insertions
}

function button(view: VueWrapper, text: string) {
  const match = view.findAll('button').find((item) => item.text() === text)
  if (!match) throw new Error('Expected button: ' + text)
  return match
}

beforeEach(() => {
  vi.resetAllMocks()
  window.localStorage.clear()
  mocks.ssh = reactive({
    connectionId: 'conn-1',
    isConnected: true,
    username: 'alice',
    host: 'host-1',
    port: 22,
  })
  mocks.api.status.mockResolvedValue(targetStatus())
  mocks.api.listPackages.mockResolvedValue([])
})

afterEach(() => {
  observer?.disconnect()
  observer = undefined
  wrapper?.unmount()
  wrapper = undefined
})

describe('CodeServer startup', () => {
  it('removes the iframe before requesting the IDE stop', async () => {
    mocks.api.status.mockResolvedValueOnce(targetStatus(true))
    const view = await mountView()
    const stop = deferred<CodeServerSession>()
    mocks.api.stop.mockImplementationOnce(() => {
      expect(view.find('iframe').exists()).toBe(false)
      return stop.promise
    })

    await button(view, '停止').trigger('click')
    await flushPromises()

    expect(mocks.api.stop).toHaveBeenCalledExactlyOnceWith('conn-1')
    expect(view.find('iframe').exists()).toBe(false)
    expect(view.get('[role="status"]').text()).toBe('正在停止 IDE…')
    expect(view.find('.cs-setup').exists()).toBe(false)

    stop.resolve({ ...targetStatus(true).session!, state: 'stopped', url: null })
    await flushPromises()
    expect(view.find('iframe').exists()).toBe(false)
    expect(view.find('[role="status"]').exists()).toBe(false)
    expect(view.find('.cs-setup').exists()).toBe(true)
  })

  it('removes the iframe after each stop without waiting for the status refresh', async () => {
    mocks.api.status.mockResolvedValue(targetStatus(true))
    const view = await mountView()

    for (let attempt = 0; attempt < 2; attempt += 1) {
      await view.get('iframe').trigger('load')
      const stoppedSession: CodeServerSession = {
        ...targetStatus(true).session!, state: 'stopped', url: null,
      }
      const refresh = deferred<CodeServerTargetStatus>()
      mocks.api.stop.mockResolvedValueOnce(stoppedSession)
      mocks.api.status.mockReturnValueOnce(refresh.promise)

      await button(view, '停止').trigger('click')
      await flushPromises()

      expect(view.find('iframe').exists()).toBe(false)
      expect(view.findAll('button').some((item) => item.text() === '停止')).toBe(false)

      refresh.resolve({ ...targetStatus(), session: stoppedSession })
      await flushPromises()

      if (attempt === 0) {
        mocks.api.start.mockResolvedValueOnce(targetStatus(true).session!)
        await button(view, '启动 IDE').trigger('click')
        await flushPromises()
        expect(view.get('iframe').classes()).not.toContain('cs-frame-ready')
      }
    }

    expect(mocks.api.stop).toHaveBeenCalledTimes(2)
  })

  it('keeps the iframe removed when the status refresh after stopping fails', async () => {
    mocks.api.status.mockResolvedValueOnce(targetStatus(true))
    const view = await mountView()
    mocks.api.stop.mockResolvedValueOnce({
      ...targetStatus(true).session!, state: 'stopped', url: null,
    })
    mocks.api.status.mockRejectedValueOnce(new Error('Status unavailable'))

    await button(view, '停止').trigger('click')
    await flushPromises()

    expect(view.find('iframe').exists()).toBe(false)
    expect(button(view, '启动 IDE').attributes('disabled')).toBeUndefined()
  })

  it('inserts the iframe only once when the status request after start returns running', async () => {
    const view = await mountView()
    const insertions = observeFrameInsertions(view)
    const start = deferred<CodeServerSession>()
    const runningStatus = deferred<CodeServerTargetStatus>()
    mocks.api.start.mockReturnValueOnce(start.promise)
    mocks.api.status.mockReturnValueOnce(runningStatus.promise)

    await button(view, '启动 IDE').trigger('click')
    expect(mocks.api.start).toHaveBeenCalledExactlyOnceWith('conn-1', undefined)
    expect(mocks.api.status).toHaveBeenCalledTimes(1)
    expect(insertions).toHaveLength(0)

    start.resolve(targetStatus(true).session!)
    await flushPromises()
    expect(mocks.api.status).toHaveBeenLastCalledWith('conn-1')
    expect(mocks.api.status).toHaveBeenCalledTimes(2)
    expect(insertions).toHaveLength(0)

    runningStatus.resolve(targetStatus(true))
    await flushPromises()

    // Count insertion history: the old post-fetch frameKey increment replaced
    // the first iframe immediately, leaving the same final DOM count of one.
    expect(insertions).toHaveLength(1)
    expect(view.get('iframe').element).toBe(insertions[0])
    expect(view.get('iframe').attributes('src')).toContain('/ide/ide-1/')
  })

  it('still replaces the iframe when the user clicks refresh', async () => {
    mocks.api.status.mockResolvedValue(targetStatus(true))
    const view = await mountView()
    const original = view.get('iframe').element
    const insertions = observeFrameInsertions(view)

    await button(view, '刷新').trigger('click')
    await flushPromises()

    expect(insertions).toHaveLength(1)
    expect(view.get('iframe').element).toBe(insertions[0])
    expect(view.get('iframe').element).not.toBe(original)
    expect(mocks.api.start).not.toHaveBeenCalled()
    expect(mocks.api.status).toHaveBeenCalledTimes(1)
  })
})
