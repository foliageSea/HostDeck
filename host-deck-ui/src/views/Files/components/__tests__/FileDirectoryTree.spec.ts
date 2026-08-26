import { flushPromises, mount } from '@vue/test-utils'
import { defineComponent, type PropType } from 'vue'
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

const scrollTo = vi.fn()
const scrollContainerTo = vi.fn()
interface TestTreeNode {
  children: TestTreeNode[]
}

const TreeStub = defineComponent({
  name: 'NTree',
  props: {
    data: { type: Array as PropType<TestTreeNode[]>, required: true },
    expandedKeys: Array,
    selectedKeys: Array,
    onLoad: {
      type: Function as PropType<(node: TestTreeNode) => Promise<boolean>>,
      required: true,
    },
    renderPrefix: { type: Function as PropType<() => unknown>, required: true },
    virtualScroll: Boolean,
  },
  emits: ['update:expandedKeys', 'update:selectedKeys'],
  setup(_, { expose }) {
    expose({ scrollTo })
  },
  template:
    '<div data-testid="tree" class="n-scrollbar-container"><div class="n-tree-node--selected" /></div>',
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
        NButton: defineComponent({
          props: ['disabled'],
          emits: ['click'],
          template:
            '<button :disabled="disabled" @click="$emit(\'click\')"><slot name="icon" /><slot /></button>',
        }),
        NIcon: defineComponent({ template: '<span><slot /></span>' }),
        NTooltip: defineComponent({ template: '<div><slot name="trigger" /><slot /></div>' }),
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
    scrollTo.mockReset()
    scrollContainerTo.mockReset()
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
    expect(getTree(wrapper).props('virtualScroll')).toBe(true)
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

  it('collapses directories below the first level with one click', async () => {
    vi.mocked(filesApi.list)
      .mockResolvedValueOnce([directory('var')])
      .mockResolvedValueOnce([directory('log')])
      .mockResolvedValueOnce([])

    const wrapper = createWrapper('/var/log')
    await flushPromises()

    expect(getTree(wrapper).props('expandedKeys')).toEqual(['/', '/var', '/var/log'])

    await wrapper.get('[aria-label="收起一级目录以下的目录"]').trigger('click')

    expect(getTree(wrapper).props('expandedKeys')).toEqual(['/'])
  })

  it('expands and scrolls back to the current directory with one click', async () => {
    vi.mocked(filesApi.list)
      .mockResolvedValueOnce([directory('var')])
      .mockResolvedValueOnce([directory('log')])
      .mockResolvedValueOnce([])

    const wrapper = createWrapper('/var/log')
    await flushPromises()

    const scrollContainer = wrapper.get('.n-scrollbar-container').element as HTMLElement
    const target = wrapper.get('.n-tree-node--selected').element as HTMLElement
    scrollContainer.scrollTo = scrollContainerTo
    Object.defineProperties(scrollContainer, {
      clientHeight: { configurable: true, value: 200 },
      scrollTop: { configurable: true, value: 40 },
    })
    vi.spyOn(scrollContainer, 'getBoundingClientRect').mockReturnValue(
      new DOMRect(0, 100, 200, 200),
    )
    vi.spyOn(target, 'getBoundingClientRect').mockReturnValue(new DOMRect(0, 220, 100, 32))

    await wrapper.get('[aria-label="收起一级目录以下的目录"]').trigger('click')
    expect(getTree(wrapper).props('expandedKeys')).toEqual(['/'])

    await wrapper.get('[aria-label="定位到当前目录"]').trigger('click')
    await flushPromises()

    expect(getTree(wrapper).props('expandedKeys')).toEqual(['/', '/var', '/var/log'])
    expect(scrollTo).toHaveBeenCalledWith({ key: '/var/log', debounce: false })
    expect(scrollContainerTo).toHaveBeenCalledWith({ top: 76, behavior: 'smooth' })
    expect(filesApi.list).toHaveBeenCalledTimes(3)
  })

  it('emits an absolute path when a directory is selected', async () => {
    vi.mocked(filesApi.list).mockResolvedValue([directory('var')])
    const wrapper = createWrapper()
    await flushPromises()

    getTree(wrapper).vm.$emit('update:selectedKeys', ['/var'])

    expect(wrapper.emitted('navigate')).toEqual([['/var']])
  })
})
