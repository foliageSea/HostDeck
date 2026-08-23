import { mount } from '@vue/test-utils'
import { defineComponent } from 'vue'
import { describe, expect, it, vi } from 'vitest'
import FileFavoriteSidebar from '../FileFavoriteSidebar.vue'

vi.mock('@/stores/settings', () => ({
  useSettingsStore: () => ({ isDark: false }),
}))

const DirectoryTreeStub = defineComponent({
  name: 'FileDirectoryTree',
  emits: ['navigate'],
  template: '<div data-testid="directory-tree" />',
})

function createWrapper() {
  return mount(FileFavoriteSidebar, {
    props: {
      connectionId: 'conn-1',
      currentPath: '/var',
      favoritePaths: ['/var/log'],
      visible: true,
    },
    global: {
      stubs: {
        FileDirectoryTree: DirectoryTreeStub,
        NButton: defineComponent({
          emits: ['click'],
          template: '<button @click="$emit(\'click\', $event)"><slot /></button>',
        }),
        NEmpty: defineComponent({ template: '<div />' }),
        NIcon: defineComponent({ template: '<span><slot /></span>' }),
        NScrollbar: defineComponent({ template: '<div><slot /></div>' }),
        NTooltip: defineComponent({ template: '<div><slot name="trigger" /><slot /></div>' }),
      },
    },
  })
}

describe('FileFavoriteSidebar', () => {
  it('shows the directory tree by default and can switch to favorites', async () => {
    const wrapper = createWrapper()

    expect(wrapper.find('[data-testid="directory-tree"]').exists()).toBe(true)

    await wrapper
      .findAll('button')
      .find((button) => button.text().includes('收藏'))
      ?.trigger('click')

    expect(wrapper.find('[data-testid="directory-tree"]').exists()).toBe(false)
    expect(wrapper.text()).toContain('log')
  })

  it('forwards directory tree navigation', async () => {
    const wrapper = createWrapper()

    wrapper.findComponent(DirectoryTreeStub).vm.$emit('navigate', '/home')

    expect(wrapper.emitted('navigate')).toEqual([['/home']])
  })
})
