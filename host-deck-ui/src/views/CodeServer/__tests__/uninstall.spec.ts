import { flushPromises, shallowMount, type VueWrapper } from '@vue/test-utils'
import { defineComponent, reactive } from 'vue'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { CodeServerTargetStatus } from '@/api/code-server'
import CodeServerView from '../index.vue'

interface Confirmation {
  title: string
  content: string
  positiveText: string
  negativeText: string
  onPositiveClick: () => Promise<void>
  onNegativeClick?: () => void
}

const mocks = vi.hoisted(() => ({
  api: {
    status: vi.fn(),
    listPackages: vi.fn(),
    uninstall: vi.fn(),
  },
  warningDialog: vi.fn<(options: Confirmation) => void>(),
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
  getUiApi: () => ({ dialog: { warning: mocks.warningDialog }, message: mocks.message }),
}))

const ButtonStub = defineComponent({
  props: ['disabled', 'loading'],
  emits: ['click'],
  template: `<button :disabled="disabled || loading" @click="$emit('click', $event)"><slot /></button>`,
})
const AlertStub = defineComponent({ template: '<div role="alert"><slot /></div>' })

function targetStatus(installedVersion: string | null = '4.143.1'): CodeServerTargetStatus {
  return {
    preflight: {
      arch: 'x86_64',
      libc: '2.35',
      diskFreeBytes: 1024 ** 3,
      installedVersion,
      issues: [],
      supported: true,
    },
    session: null,
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

function uninstallButton(view: VueWrapper) {
  const button = view.findAll('button').find((item) => item.text() === '卸载 IDE')
  if (!button) throw new Error('Expected an uninstall button')
  return button
}

async function requestUninstall(view: VueWrapper) {
  await uninstallButton(view).trigger('click')
  expect(mocks.warningDialog).toHaveBeenCalledTimes(1)
  return mocks.warningDialog.mock.calls[0]![0]
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
  mocks.api.uninstall.mockResolvedValue({ success: true })
})

afterEach(() => {
  wrapper?.unmount()
  wrapper = undefined
})

describe('CodeServer uninstall', () => {
  it('requires confirmation before sending an uninstall request', async () => {
    const view = await mountView()
    const confirmation = await requestUninstall(view)

    expect(confirmation.title).toContain('卸载')
    expect(confirmation.content).toContain('alice@host-1:22')
    expect(confirmation.content).toContain('项目文件、用户设置和扩展会保留')
    expect(confirmation.positiveText).toBe('卸载 IDE')
    expect(confirmation.negativeText).toBe('取消')
    expect(mocks.api.uninstall).not.toHaveBeenCalled()
    expect(mocks.message.success).not.toHaveBeenCalled()
  })

  it('does not uninstall when the confirmation is cancelled', async () => {
    const view = await mountView()
    const confirmation = await requestUninstall(view)

    // Naive UI closes the dialog on Cancel without invoking onPositiveClick.
    confirmation.onNegativeClick?.()
    await flushPromises()

    expect(mocks.api.uninstall).not.toHaveBeenCalled()
    expect(mocks.api.status).toHaveBeenCalledTimes(1)
    expect(mocks.message.success).not.toHaveBeenCalled()
    expect(uninstallButton(view).attributes('disabled')).toBeUndefined()
  })

  it('uninstalls only the confirmed connection, then refreshes the installed state', async () => {
    const view = await mountView()
    const confirmation = await requestUninstall(view)
    const uninstall = deferred<{ success: boolean }>()
    mocks.api.uninstall.mockReturnValueOnce(uninstall.promise)
    mocks.api.status.mockResolvedValueOnce(targetStatus(null))

    const completion = confirmation.onPositiveClick()
    await flushPromises()

    expect(mocks.api.uninstall).toHaveBeenCalledExactlyOnceWith('conn-1')
    expect(uninstallButton(view).attributes('disabled')).toBeDefined()
    expect(mocks.api.status).toHaveBeenCalledTimes(1)
    expect(mocks.message.success).not.toHaveBeenCalled()

    uninstall.resolve({ success: true })
    await completion
    await flushPromises()

    expect(mocks.api.status).toHaveBeenCalledTimes(2)
    expect(mocks.api.status).toHaveBeenLastCalledWith('conn-1')
    expect(mocks.message.success).toHaveBeenCalledTimes(1)
    expect(mocks.message.error).not.toHaveBeenCalled()
    expect(view.text()).toContain('未安装')
    expect(view.findAll('button').some((button) => button.text() === '卸载 IDE')).toBe(false)
  })

  it('reports a failed uninstall without claiming success and refreshes the actual state', async () => {
    const view = await mountView()
    const confirmation = await requestUninstall(view)
    mocks.api.uninstall.mockRejectedValueOnce(new Error('远端卸载失败：权限不足'))

    await confirmation.onPositiveClick()
    await flushPromises()

    expect(mocks.api.uninstall).toHaveBeenCalledExactlyOnceWith('conn-1')
    expect(mocks.message.success).not.toHaveBeenCalled()
    expect(mocks.message.error).toHaveBeenCalledWith('远端卸载失败：权限不足')
    expect(view.get('[role="alert"]').text()).toContain('远端卸载失败：权限不足')
    expect(mocks.api.status).toHaveBeenCalledTimes(2)
    expect(uninstallButton(view).attributes('disabled')).toBeUndefined()
    expect(view.text()).toContain('v4.143.1')
  })

  it('invalidates an old confirmation after switching connections', async () => {
    const view = await mountView()
    const confirmation = await requestUninstall(view)

    mocks.ssh.connectionId = 'conn-2'
    mocks.ssh.host = 'host-2'
    await flushPromises()
    await confirmation.onPositiveClick()

    expect(mocks.api.status).toHaveBeenLastCalledWith('conn-2')
    expect(mocks.api.uninstall).not.toHaveBeenCalled()
    expect(mocks.message.success).not.toHaveBeenCalled()
    expect(mocks.message.warning).toHaveBeenCalledWith('连接或 IDE 状态已变化，请重新确认卸载。')
  })

  it('invalidates an old confirmation after disconnecting', async () => {
    const view = await mountView()
    const confirmation = await requestUninstall(view)

    mocks.ssh.isConnected = false
    await confirmation.onPositiveClick()

    expect(mocks.api.uninstall).not.toHaveBeenCalled()
    expect(mocks.message.success).not.toHaveBeenCalled()
    expect(mocks.message.warning).toHaveBeenCalledTimes(1)
  })

  it('ignores a confirmation after the view is unmounted', async () => {
    const view = await mountView()
    const confirmation = await requestUninstall(view)
    view.unmount()
    wrapper = undefined

    await confirmation.onPositiveClick()

    expect(mocks.api.uninstall).not.toHaveBeenCalled()
    expect(mocks.message.success).not.toHaveBeenCalled()
  })

  it('does not submit twice while an uninstall is pending', async () => {
    const view = await mountView()
    const confirmation = await requestUninstall(view)
    const uninstall = deferred<{ success: boolean }>()
    mocks.api.uninstall.mockReturnValueOnce(uninstall.promise)

    const completion = confirmation.onPositiveClick()
    await confirmation.onPositiveClick()

    expect(mocks.api.uninstall).toHaveBeenCalledExactlyOnceWith('conn-1')
    expect(mocks.message.success).not.toHaveBeenCalled()

    uninstall.resolve({ success: true })
    await completion
  })
})
