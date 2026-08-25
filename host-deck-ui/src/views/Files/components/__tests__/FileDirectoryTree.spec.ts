import { flushPromises, mount } from '@vue/test-utils'
import { defineComponent } from 'vue'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { filesApi, type FileItem } from '@/api/files'
import FileDirectoryTree from '../FileDirectoryTree.vue'
import { directoryTreeIconUrl } from '../fileIcons'

vi.mock('@/api/files', () => ({
  filesApi: {
    list: vi.fn(),
  },
}))

const directory = (filename: string): FileItem => ({
  filename,
  isDirectory: true,
  longname: filename,
  size: 0,
})

const file = (filename: string): FileItem => ({
  filename,
  isDirectory: false,
  longname: filename,
  size: 1,
})

const TreeStub = defineComponent({
  name: 'NTree',
  props: ['data', 'expandedKeys', 'selectedKeys', 'onLoad', 'renderPrefix'],
  emits: ['update:expandedKeys', 'update:selectedKeys'],
  template: '<div data-testid="tree" />',
})

function createWrapper(currentPath = '/') {
  return mount(FileDirectoryTree, {
    props: {
      connectionId: 'conn-1',
      currentPath,
    },
    global: {
      stubs: {
        NAlert: defineComponent({ template: '<div><slot /></div>' }),
        NScrollbar: defineComponent({ template: '<div><slot /></div>' }),
        NTree: TreeStub,
      },
    },
  })
}

function getTree(wrapper: ReturnType<typeof createWrapper>) {
  return wrapper.findComponent(TreeStub)
}

describe('FileDirectoryTree', () => {
  beforeEach(() => {
    vi.mocked(filesApi.list).mockReset()
  })

  it('loads one directory level by default and filters out files', async () => {
    vi.mocked(filesApi.list).mockResolvedValue([
      directory('var'),
      file('README'),
      directory('home'),
    ])

    const wrapper = createWrapper()
    await flushPromises()

    expect(filesApi.list).toHaveBeenCalledTimes(1)
    expect(filesApi.list).toHaveBeenCalledWith('conn-1', '/')
    expect(getTree(wrapper).props('data')).toMatchObject([
      {
        key: '/',
        children: [{ key: '/home' }, { key: '/var' }],
      },
    ])
    expect(getTree(wrapper).props('renderPrefix')()).toMatchObject({
      type: 'img',
      props: {
        src: directoryTreeIconUrl,
        width: 16,
        height: 16,
      },
    })
  })

  it('loads child directories only when their node is expanded', async () => {
    vi.mocked(filesApi.list)
      .mockResolvedValueOnce([directory('var')])
      .mockResolvedValueOnce([directory('log'), file('hosts')])

    const wrapper = createWrapper()
    await flushPromises()
    const tree = getTree(wrapper)
    const varNode = tree.props('data')[0].children[0]

    await tree.props('onLoad')(varNode)
    await flushPromises()

    expect(filesApi.list).toHaveBeenNthCalledWith(2, 'conn-1', '/var')
    expect(varNode.children).toMatchObject([{ key: '/var/log' }])
  })

  it('loads the current directory children and expands its full path', async () => {
    vi.mocked(filesApi.list)
      .mockResolvedValueOnce([directory('var')])
      .mockResolvedValueOnce([directory('log')])
      .mockResolvedValueOnce([directory('nginx')])

    const wrapper = createWrapper('/var/log')
    await flushPromises()

    expect(filesApi.list).toHaveBeenNthCalledWith(1, 'conn-1', '/')
    expect(filesApi.list).toHaveBeenNthCalledWith(2, 'conn-1', '/var')
    expect(filesApi.list).toHaveBeenNthCalledWith(3, 'conn-1', '/var/log')
    expect(getTree(wrapper).props('expandedKeys')).toEqual(['/', '/var', '/var/log'])
    expect(getTree(wrapper).props('selectedKeys')).toEqual(['/var/log'])
    expect(getTree(wrapper).props('data')[0].children[0].children[0].children).toMatchObject([
      { key: '/var/log/nginx' },
    ])
  })

  it('emits an absolute path when a directory is selected', async () => {
    vi.mocked(filesApi.list).mockResolvedValue([directory('var')])
    const wrapper = createWrapper()
    await flushPromises()

    getTree(wrapper).vm.$emit('update:selectedKeys', ['/var'])

    expect(wrapper.emitted('navigate')).toEqual([['/var']])
  })
})
