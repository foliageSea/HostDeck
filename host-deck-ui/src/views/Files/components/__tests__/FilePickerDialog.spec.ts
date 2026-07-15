import { flushPromises, mount } from '@vue/test-utils'
import { defineComponent } from 'vue'
import { describe, expect, it, vi, beforeEach } from 'vitest'
import { filesApi, type FileItem } from '@/api/files'
import FilePickerDialog from '../FilePickerDialog.vue'

vi.mock('@/api/files', () => ({
  filesApi: {
    list: vi.fn(),
    mkdir: vi.fn(),
  },
}))

const directoryItem: FileItem = {
  filename: 'logs',
  isDirectory: true,
  longname: 'logs',
  size: 0,
}

const fileItem: FileItem = {
  filename: 'app.log',
  isDirectory: false,
  longname: 'app.log',
  size: 128,
}

function createWrapper(props: Partial<InstanceType<typeof FilePickerDialog>['$props']> = {}) {
  return mount(FilePickerDialog, {
    props: {
      connectionId: 'conn-1',
      show: true,
      ...props,
    },
    global: {
      stubs: {
        FileBrowserContent: defineComponent({
          name: 'FileBrowserContent',
          props: ['files', 'loading', 'selectedNames'],
          emits: ['clickFile', 'contextBlank', 'contextFile', 'openFile', 'selectNames'],
          template: '<div data-testid="browser"><slot /></div>',
        }),
        NAlert: defineComponent({
          template: '<div><slot /></div>',
        }),
        NButton: defineComponent({
          props: ['disabled'],
          emits: ['click'],
          template:
            '<button :disabled="disabled" @click="$emit(\'click\', $event)"><slot name="icon" /><slot /></button>',
        }),
        NIcon: defineComponent({
          template: '<span><slot /></span>',
        }),
        NInput: defineComponent({
          props: ['value'],
          emits: ['update:value'],
          methods: {
            handleInput(event: Event) {
              this.$emit('update:value', (event.target as HTMLInputElement).value)
            },
          },
          template: '<input :value="value" @input="handleInput" />',
        }),
        NModal: defineComponent({
          props: ['show'],
          emits: ['update:show'],
          template: '<section v-if="show"><slot /></section>',
        }),
      },
    },
  })
}

function getBrowser(wrapper: ReturnType<typeof createWrapper>) {
  return wrapper.findComponent({ name: 'FileBrowserContent' })
}

function getConfirmButton(wrapper: ReturnType<typeof createWrapper>) {
  return wrapper.findAll('button').find((button) => button.text().includes('选择'))
}

function getButton(wrapper: ReturnType<typeof createWrapper>, text: string) {
  return wrapper.findAll('button').find((button) => button.text().includes(text))
}

describe('FilePickerDialog', () => {
  beforeEach(() => {
    vi.mocked(filesApi.list).mockReset()
    vi.mocked(filesApi.mkdir).mockReset()
  })

  it('loads files from the initial path when opened', async () => {
    vi.mocked(filesApi.list).mockResolvedValue([directoryItem, fileItem])

    createWrapper({ initialPath: '/var' })
    await flushPromises()

    expect(filesApi.list).toHaveBeenCalledWith('conn-1', '/var')
  })

  it('navigates into directories on open', async () => {
    vi.mocked(filesApi.list)
      .mockResolvedValueOnce([directoryItem])
      .mockResolvedValueOnce([fileItem])

    const wrapper = createWrapper({ initialPath: '/var' })
    await flushPromises()

    getBrowser(wrapper).vm.$emit('openFile', directoryItem)
    await flushPromises()

    expect(filesApi.list).toHaveBeenLastCalledWith('conn-1', '/var/logs')
  })

  it('confirms a selectable file in file mode', async () => {
    vi.mocked(filesApi.list).mockResolvedValue([directoryItem, fileItem])

    const wrapper = createWrapper({ initialPath: '/var' })
    await flushPromises()

    getBrowser(wrapper).vm.$emit('clickFile', fileItem, new MouseEvent('click'))
    await wrapper.vm.$nextTick()
    await getConfirmButton(wrapper)?.trigger('click')

    expect(wrapper.emitted('confirm')).toEqual([
      [
        {
          currentPath: '/var',
          selections: [
            {
              currentPath: '/var',
              item: fileItem,
              path: '/var/app.log',
            },
          ],
        },
      ],
    ])
  })

  it('confirms the current directory when directory mode has no selected item', async () => {
    vi.mocked(filesApi.list).mockResolvedValue([directoryItem, fileItem])

    const wrapper = createWrapper({ initialPath: '/var', mode: 'directory' })
    await flushPromises()

    await getConfirmButton(wrapper)?.trigger('click')

    expect(wrapper.emitted('confirm')).toEqual([
      [
        {
          currentPath: '/var',
          selections: [
            {
              currentPath: '/var',
              item: null,
              path: '/var',
            },
          ],
        },
      ],
    ])
  })

  it('returns multiple selectable paths when multiple is enabled', async () => {
    const configFile: FileItem = {
      filename: 'config.json',
      isDirectory: false,
      longname: 'config.json',
      size: 64,
    }
    vi.mocked(filesApi.list).mockResolvedValue([directoryItem, fileItem, configFile])

    const wrapper = createWrapper({ initialPath: '/etc', multiple: true })
    await flushPromises()

    getBrowser(wrapper).vm.$emit('selectNames', ['app.log', 'config.json'])
    await wrapper.vm.$nextTick()
    await getConfirmButton(wrapper)?.trigger('click')

    expect(wrapper.emitted('confirm')).toEqual([
      [
        {
          currentPath: '/etc',
          selections: [
            {
              currentPath: '/etc',
              item: fileItem,
              path: '/etc/app.log',
            },
            {
              currentPath: '/etc',
              item: configFile,
              path: '/etc/config.json',
            },
          ],
        },
      ],
    ])
  })

  it('creates a directory, refreshes the list, and selects it', async () => {
    const newDirectory: FileItem = {
      filename: 'new-stack',
      isDirectory: true,
      longname: 'new-stack',
      size: 0,
    }
    vi.mocked(filesApi.list)
      .mockResolvedValueOnce([directoryItem])
      .mockResolvedValueOnce([directoryItem, newDirectory])
    vi.mocked(filesApi.mkdir).mockResolvedValue(undefined)

    const wrapper = createWrapper({ initialPath: '/opt', mode: 'directory' })
    await flushPromises()

    await getButton(wrapper, '新建目录')?.trigger('click')
    await wrapper.findAll('input')[2].setValue('new-stack')
    await getButton(wrapper, '创建')?.trigger('click')
    await flushPromises()
    await wrapper.vm.$nextTick()

    expect(filesApi.mkdir).toHaveBeenCalledWith('conn-1', '/opt/new-stack')
    expect(filesApi.list).toHaveBeenLastCalledWith('conn-1', '/opt')

    await getConfirmButton(wrapper)?.trigger('click')

    expect(wrapper.emitted('confirm')).toEqual([
      [
        {
          currentPath: '/opt',
          selections: [
            {
              currentPath: '/opt',
              item: newDirectory,
              path: '/opt/new-stack',
            },
          ],
        },
      ],
    ])
  })
})
