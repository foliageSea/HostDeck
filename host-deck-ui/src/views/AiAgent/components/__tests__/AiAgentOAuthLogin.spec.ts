import { flushPromises, mount } from '@vue/test-utils'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import AiAgentOAuthLogin from '../AiAgentOAuthLogin.vue'

const mocks = vi.hoisted(() => ({
  api: { oauthStatus: vi.fn(), oauthLogin: vi.fn(), oauthCancel: vi.fn(), oauthLogout: vi.fn() },
  store: { loadSettings: vi.fn(), settings: undefined as unknown },
  success: vi.fn(),
  error: vi.fn(),
  writeText: vi.fn(),
}))
vi.mock('@/api/ai-agent', () => ({ aiAgentApi: mocks.api }))
vi.mock('@/stores/ai-agent', () => ({ useAiAgentStore: () => mocks.store }))
vi.mock('@/lib/ui', () => ({
  getUiApi: () => ({ message: { error: mocks.error, success: mocks.success } }),
}))

function render() {
  return mount(AiAgentOAuthLogin, {
    props: { active: true },
    global: {
      stubs: {
        NButton: {
          props: ['loading', 'disabled', 'tag'],
          emits: ['click'],
          template:
            '<component :is="tag || \'button\'" :disabled="disabled || loading" @click="$emit(\'click\')"><slot /></component>',
        },
      },
    },
  })
}

describe('OpenAI device login', () => {
  beforeEach(() => {
    vi.resetAllMocks()
    vi.useFakeTimers()
    mocks.api.oauthStatus.mockResolvedValue({ status: 'idle', authenticated: false })
    Object.defineProperty(navigator, 'clipboard', {
      configurable: true,
      value: { writeText: mocks.writeText },
    })
    mocks.writeText.mockResolvedValue(undefined)
  })
  afterEach(() => { vi.useRealTimers() })

  it('displays device code and updates readiness after authorization', async () => {
    const wrapper = render()
    await flushPromises()
    mocks.api.oauthLogin.mockResolvedValue({ status: 'starting', authenticated: false, id: 'login-1' })
    mocks.api.oauthStatus.mockResolvedValue({ status: 'pending', authenticated: false, id: 'login-1',
      userCode: 'ABCD-1234', verificationUri: 'https://auth.openai.com/codex/device' })
    await wrapper.find('button').trigger('click')
    await flushPromises()
    expect(wrapper.find('code').text()).toBe('ABCD-1234')
    await wrapper.get('button[aria-label="复制设备码"]').trigger('click')
    await flushPromises()
    expect(mocks.writeText).toHaveBeenCalledWith('ABCD1234')
    expect(mocks.success).toHaveBeenCalledWith('设备码已复制。')
    const actions = wrapper.findAll('.agent-oauth-actions > *')
    expect(actions.map((action) => action.text())).toEqual(['打开 OpenAI 授权页面', '取消登录'])
    expect(actions[0]!.element.tagName).toBe('A')
    expect(actions[0]!.attributes('href')).toBe('https://auth.openai.com/codex/device')
    mocks.api.oauthStatus.mockResolvedValue({ status: 'success', authenticated: true, id: 'login-1' })
    await vi.advanceTimersByTimeAsync(2000)
    await flushPromises()
    expect(mocks.store.loadSettings).toHaveBeenCalledOnce()
    expect(wrapper.text()).toContain('已登录')
    expect(wrapper.find('code').exists()).toBe(false)
    const count = mocks.api.oauthStatus.mock.calls.length
    wrapper.unmount()
    await vi.advanceTimersByTimeAsync(4000)
    expect(mocks.api.oauthStatus).toHaveBeenCalledTimes(count)
  })

  it('cancels the displayed login and stops polling when hidden', async () => {
    mocks.api.oauthStatus.mockResolvedValue({ status: 'pending', authenticated: false, id: 'login-2',
      userCode: 'CODE', verificationUri: 'https://auth.openai.com/codex/device' })
    mocks.api.oauthCancel.mockResolvedValue({ status: 'cancelled', authenticated: false, id: 'login-2' })
    const wrapper = render()
    await flushPromises()
    await wrapper
      .findAll('button')
      .find((button) => button.text() === '取消登录')!
      .trigger('click')
    await flushPromises()
    expect(mocks.api.oauthCancel).toHaveBeenCalledWith('login-2')
    expect(wrapper.find('code').exists()).toBe(false)
    await wrapper.setProps({ active: false })
    const count = mocks.api.oauthStatus.mock.calls.length
    await vi.advanceTimersByTimeAsync(4000)
    expect(mocks.api.oauthStatus).toHaveBeenCalledTimes(count)
    wrapper.unmount()
  })

  it('logout updates the shared settings so chat requires authentication again', async () => {
    mocks.api.oauthStatus.mockResolvedValue({ status: 'idle', authenticated: true })
    const settings = { hasOAuth: false, hasCredentials: false, provider: 'openai-codex' }
    mocks.api.oauthLogout.mockResolvedValue(settings)
    const wrapper = render()
    await flushPromises()
    await wrapper.findAll('button').find((button) => button.text() === '退出登录')!.trigger('click')
    await flushPromises()
    expect(mocks.store.settings).toEqual(settings)
    expect(wrapper.text()).not.toContain('已登录')
    wrapper.unmount()
  })
})
