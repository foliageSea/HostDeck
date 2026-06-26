<script setup>
import { computed, nextTick, onBeforeUnmount, onMounted, ref } from 'vue'
import {
  ChevronDown,
  ChevronUp,
  CodeXml,
  Ellipsis,
  ExternalLink,
  Minus,
  Monitor,
  PanelLeft,
  Plus,
  RefreshCw,
  Square,
  X,
} from 'lucide-vue-next'

const api = window.hostDeckTabs

const currentState = ref({
  activeTabId: null,
  tabBarPosition: 'top',
  tabs: [],
})
const dragState = ref(null)
const editingTabId = ref(null)
const editingTitle = ref('')
const toolbarExpanded = ref(false)
const sidebarWidth = ref(220)
const minSidebarWidth = 160
const maxSidebarWidth = 220
const isResizingSidebar = ref(false)

const isMac = api?.platform === 'darwin'
const isVertical = computed(() => currentState.value.tabBarPosition === 'left')
const tabs = computed(() => currentState.value.tabs)
const nextTabBarPosition = computed(() => (isVertical.value ? 'top' : 'left'))
const sidebarStyle = computed(() => ({ '--sidebar-width': `${sidebarWidth.value}px` }))
const nextTabBarLabel = computed(() =>
  nextTabBarPosition.value === 'left' ? '切换垂直标签栏' : '切换顶部标签栏'
)
const toolbarMenuLabel = computed(() => {
  if (!isVertical.value) return '更多操作'
  return toolbarExpanded.value ? '收起菜单' : '展开菜单'
})
const toolbarMenuIcon = computed(() => {
  if (!isVertical.value) return Ellipsis
  return toolbarExpanded.value ? ChevronDown : ChevronUp
})

let unsubscribe = null

function render(state) {
  currentState.value = state
  sidebarWidth.value = clampSidebarWidth(state?.sidebarWidth)
}

function clampSidebarWidth(width) {
  const nextWidth = Number(width)
  if (!Number.isFinite(nextWidth)) return maxSidebarWidth
  return Math.min(maxSidebarWidth, Math.max(minSidebarWidth, Math.round(nextWidth)))
}

function clearDropIndicators() {
  document.querySelectorAll('.drop-before, .drop-after').forEach((element) => {
    element.classList.remove('drop-before', 'drop-after')
  })
}

function endDrag() {
  const draggedElement = dragState.value?.element
  if (draggedElement) draggedElement.classList.remove('dragging')
  clearDropIndicators()
  dragState.value = null
}

function getDropPlacement(event, element) {
  const rect = element.getBoundingClientRect()
  const ratio = isVertical.value
    ? (event.clientY - rect.top) / Math.max(rect.height, 1)
    : (event.clientX - rect.left) / Math.max(rect.width, 1)
  return ratio < 0.5 ? 'before' : 'after'
}

function startEditing(tab) {
  editingTabId.value = tab.id
  editingTitle.value = tab.title || 'HostDeck'
  nextTick(() => {
    const input = document.querySelector(`[data-edit-tab-id="${tab.id}"]`)
    input?.focus()
    input?.select()
  })
}

function stopEditing() {
  editingTabId.value = null
}

async function saveEditing(tabId) {
  if (editingTabId.value !== tabId) return
  stopEditing()
  await api.rename(tabId, editingTitle.value)
}

function handleAuxClick(event, tabId) {
  if (event.button !== 1) return
  event.preventDefault()
  event.stopPropagation()
  api.close(tabId)
}

function handleDragStart(event, tabId) {
  if (editingTabId.value === tabId) {
    event.preventDefault()
    return
  }

  dragState.value = {
    element: event.currentTarget,
    id: tabId,
    placement: null,
    targetId: null,
  }
  event.currentTarget.classList.add('dragging')
  event.dataTransfer.effectAllowed = 'move'
  event.dataTransfer.setData('text/plain', tabId)
}

function handleDragOver(event, tabId) {
  if (!dragState.value || dragState.value.id === tabId) return

  event.preventDefault()
  const placement = getDropPlacement(event, event.currentTarget)
  dragState.value.targetId = tabId
  dragState.value.placement = placement
  clearDropIndicators()
  event.currentTarget.classList.add(placement === 'before' ? 'drop-before' : 'drop-after')
  event.dataTransfer.dropEffect = 'move'
}

async function handleDrop(event, tabId) {
  if (!dragState.value || dragState.value.id === tabId || !dragState.value.placement) return

  event.preventDefault()
  const { id, placement } = dragState.value
  endDrag()
  await api.reorder(id, tabId, placement)
}

function setToolbarActionsVisible(visible) {
  toolbarExpanded.value = visible
}

async function toggleTabBarPosition() {
  await api.setBarPosition(nextTabBarPosition.value)
  setToolbarActionsVisible(false)
}

function handleDocumentClick(event) {
  const toolbar = document.querySelector('.toolbar')
  if (!toolbar?.contains(event.target instanceof Node ? event.target : null)) {
    setToolbarActionsVisible(false)
  }
}

function handleDocumentKeydown(event) {
  if (event.key === 'Escape') {
    setToolbarActionsVisible(false)
    if (editingTabId.value) stopEditing()
  }
}

function handleListDragLeave(event) {
  if (
    !(event.currentTarget instanceof Element) ||
    !(event.relatedTarget instanceof Node) ||
    !event.currentTarget.contains(event.relatedTarget)
  ) {
    clearDropIndicators()
  }
}

function handleSidebarResizePointerDown(event) {
  if (!isVertical.value) return

  event.preventDefault()
  isResizingSidebar.value = true
  document.body.style.cursor = 'col-resize'
  document.body.style.userSelect = 'none'

  const handlePointerMove = (moveEvent) => {
    sidebarWidth.value = clampSidebarWidth(moveEvent.clientX)
  }

  const handlePointerUp = async () => {
    window.removeEventListener('pointermove', handlePointerMove)
    window.removeEventListener('pointerup', handlePointerUp)
    window.removeEventListener('pointercancel', handlePointerUp)
    document.body.style.cursor = ''
    document.body.style.userSelect = ''
    isResizingSidebar.value = false
    await api.setSidebarWidth(sidebarWidth.value)
  }

  window.addEventListener('pointermove', handlePointerMove)
  window.addEventListener('pointerup', handlePointerUp)
  window.addEventListener('pointercancel', handlePointerUp)
}

onMounted(async () => {
  if (!api) return
  unsubscribe = api.onChanged(render)
  render(await api.list())
  document.addEventListener('click', handleDocumentClick)
  document.addEventListener('keydown', handleDocumentKeydown)
})

onBeforeUnmount(() => {
  unsubscribe?.()
  document.removeEventListener('click', handleDocumentClick)
  document.removeEventListener('keydown', handleDocumentKeydown)
})
</script>

<template>
  <div :class="['shell', isMac ? 'is-mac' : '', isVertical ? 'left' : 'top']">
    <header class="tab-shell">
      <template v-if="!isVertical">
        <div class="tabs">
          <div class="tab-list" @dragleave="handleListDragLeave">
            <button
              v-for="tab in tabs"
              :key="tab.id"
              :class="['tab', { active: tab.isActive, loading: tab.isLoading }]"
              :data-tab-id="tab.id"
              :draggable="editingTabId !== tab.id"
              :title="tab.title || 'HostDeck'"
              type="button"
              @click="api.activate(tab.id)"
              @auxclick="handleAuxClick($event, tab.id)"
              @dblclick.prevent.stop="startEditing(tab)"
              @dragstart="handleDragStart($event, tab.id)"
              @dragover="handleDragOver($event, tab.id)"
              @drop="handleDrop($event, tab.id)"
              @dragend="endDrag"
            >
              <span class="tab-app-icon" aria-hidden="true">
                <Monitor class="icon" />
              </span>

              <input
                v-if="editingTabId === tab.id"
                :data-edit-tab-id="tab.id"
                :value="editingTitle"
                class="tab-title-input"
                aria-label="Tab 标题"
                @blur="saveEditing(tab.id)"
                @click.stop
                @dblclick.stop
                @input="editingTitle = $event.target instanceof HTMLInputElement ? $event.target.value : editingTitle"
                @keydown.enter.prevent="saveEditing(tab.id)"
                @keydown.esc.prevent="stopEditing()"
              />
              <span v-else class="tab-title">{{ tab.title || 'HostDeck' }}</span>

              <span class="tab-status"></span>
              <span class="tab-close" role="button" :aria-label="'关闭 ' + (tab.title || 'HostDeck')" @click.stop="api.close(tab.id)">
                <X class="icon close-icon" />
              </span>
            </button>
          </div>

          <button class="new-tab" type="button" title="新建 Tab" aria-label="新建 Tab" @click="api.create()">
            <Plus class="icon button-icon" />
            <span class="toolbar-label">新建 Tab</span>
          </button>
        </div>

        <div class="toolbar">
          <div class="toolbar-actions" :hidden="!toolbarExpanded">
            <button class="toolbar-button" type="button" title="刷新当前 Tab" aria-label="刷新当前 Tab" @click="api.reloadActive(); setToolbarActionsVisible(false)">
              <RefreshCw class="icon button-icon" />
              <span class="toolbar-label">刷新当前 Tab</span>
            </button>
            <button class="toolbar-button" type="button" title="在外部浏览器打开" aria-label="在外部浏览器打开" @click="api.openActiveInBrowser(); setToolbarActionsVisible(false)">
              <ExternalLink class="icon button-icon" />
              <span class="toolbar-label">外部浏览器打开</span>
            </button>
            <button class="toolbar-button" type="button" title="打开当前 Tab 开发者工具" aria-label="打开当前 Tab 开发者工具" @click="api.openActiveDevTools(); setToolbarActionsVisible(false)">
              <CodeXml class="icon button-icon devtools-icon" />
              <span class="toolbar-label">开发者工具</span>
            </button>
            <button class="toolbar-button" type="button" :title="nextTabBarLabel" :aria-label="nextTabBarLabel" @click="toggleTabBarPosition">
              <PanelLeft class="icon button-icon" />
              <span class="toolbar-label">{{ nextTabBarLabel }}</span>
            </button>
          </div>

          <button
            class="toolbar-button"
            :aria-expanded="String(toolbarExpanded)"
            :aria-label="toolbarMenuLabel"
            :title="toolbarMenuLabel"
            type="button"
            @click="setToolbarActionsVisible(!toolbarExpanded)"
          >
            <component :is="toolbarMenuIcon" class="icon button-icon" />
            <span class="toolbar-label">{{ toolbarMenuLabel }}</span>
          </button>
        </div>
      </template>

      <div v-if="isVertical" class="titlebar-app-name" aria-label="应用名称">HostDeck</div>

      <div v-if="!isMac" class="window-controls" aria-label="窗口操作">
        <button class="window-control minimize" type="button" aria-label="最小化窗口" @click="api.window.minimize()">
          <Minus class="window-control-icon" />
        </button>
        <button class="window-control maximize" type="button" aria-label="最大化窗口" @click="api.window.toggleMaximize()">
          <Square class="window-control-icon" />
        </button>
        <button class="window-control close" type="button" aria-label="关闭窗口" @click="api.window.close()">
          <X class="window-control-icon" />
        </button>
      </div>
    </header>

    <aside v-if="isVertical" class="sidebar" :style="sidebarStyle">
      <div class="tabs">
        <div class="tab-list" @dragleave="handleListDragLeave">
          <button
            v-for="tab in tabs"
            :key="tab.id"
            :class="['tab', { active: tab.isActive, loading: tab.isLoading }]"
            :data-tab-id="tab.id"
            :draggable="editingTabId !== tab.id"
            :title="tab.title || 'HostDeck'"
            type="button"
            @click="api.activate(tab.id)"
            @auxclick="handleAuxClick($event, tab.id)"
            @dblclick.prevent.stop="startEditing(tab)"
            @dragstart="handleDragStart($event, tab.id)"
            @dragover="handleDragOver($event, tab.id)"
            @drop="handleDrop($event, tab.id)"
            @dragend="endDrag"
          >
            <span class="tab-app-icon" aria-hidden="true">
              <Monitor class="icon" />
            </span>

            <input
              v-if="editingTabId === tab.id"
              :data-edit-tab-id="tab.id"
              :value="editingTitle"
              class="tab-title-input"
              aria-label="Tab 标题"
              @blur="saveEditing(tab.id)"
              @click.stop
              @dblclick.stop
              @input="editingTitle = $event.target instanceof HTMLInputElement ? $event.target.value : editingTitle"
              @keydown.enter.prevent="saveEditing(tab.id)"
              @keydown.esc.prevent="stopEditing()"
            />
            <span v-else class="tab-title">{{ tab.title || 'HostDeck' }}</span>

            <span class="tab-status"></span>
            <span class="tab-close" role="button" :aria-label="'关闭 ' + (tab.title || 'HostDeck')" @click.stop="api.close(tab.id)">
              <X class="icon close-icon" />
            </span>
          </button>
        </div>

        <button class="new-tab" type="button" title="新建 Tab" aria-label="新建 Tab" @click="api.create()">
          <Plus class="icon button-icon" />
          <span class="toolbar-label">新建 Tab</span>
        </button>
      </div>

      <div class="toolbar">
        <div class="toolbar-actions" :hidden="!toolbarExpanded">
          <button class="toolbar-button" type="button" title="刷新当前 Tab" aria-label="刷新当前 Tab" @click="api.reloadActive(); setToolbarActionsVisible(false)">
            <RefreshCw class="icon button-icon" />
            <span class="toolbar-label">刷新当前 Tab</span>
          </button>
          <button class="toolbar-button" type="button" title="在外部浏览器打开" aria-label="在外部浏览器打开" @click="api.openActiveInBrowser(); setToolbarActionsVisible(false)">
            <ExternalLink class="icon button-icon" />
            <span class="toolbar-label">外部浏览器打开</span>
          </button>
          <button class="toolbar-button" type="button" title="打开当前 Tab 开发者工具" aria-label="打开当前 Tab 开发者工具" @click="api.openActiveDevTools(); setToolbarActionsVisible(false)">
            <CodeXml class="icon button-icon devtools-icon" />
            <span class="toolbar-label">开发者工具</span>
          </button>
          <button class="toolbar-button" type="button" :title="nextTabBarLabel" :aria-label="nextTabBarLabel" @click="toggleTabBarPosition">
            <PanelLeft class="icon button-icon" />
            <span class="toolbar-label">{{ nextTabBarLabel }}</span>
          </button>
        </div>

        <button
          class="toolbar-button"
          :aria-expanded="String(toolbarExpanded)"
          :aria-label="toolbarMenuLabel"
          :title="toolbarMenuLabel"
          type="button"
          @click="setToolbarActionsVisible(!toolbarExpanded)"
        >
          <component :is="toolbarMenuIcon" class="icon button-icon" />
          <span class="toolbar-label">{{ toolbarMenuLabel }}</span>
        </button>
      </div>

      <div
        class="sidebar-resize-handle"
        :class="{ active: isResizingSidebar }"
        role="separator"
        aria-label="调整标签栏宽度"
        aria-orientation="vertical"
        :aria-valuemin="String(minSidebarWidth)"
        :aria-valuemax="String(maxSidebarWidth)"
        :aria-valuenow="String(sidebarWidth)"
        @pointerdown="handleSidebarResizePointerDown"
      ></div>
    </aside>

    <main :class="['empty-state', { visible: tabs.length === 0 }]" :style="isVertical ? sidebarStyle : undefined">
      <button class="empty-action" type="button" @click="api.create()">
        <Plus class="icon button-icon" />
        <span>新建 Tab</span>
      </button>
    </main>
  </div>
</template>

<style scoped>
:global(:root) {
  color-scheme: dark;
  font-family: Inter, 'Segoe UI', system-ui, -apple-system, BlinkMacSystemFont, sans-serif;
  --titlebar-height: 42px;
  --sidebar-width: 220px;
  --mac-traffic-light-space: 88px;
  --window-controls-width: 138px;
}

:global(*) {
  box-sizing: border-box;
}

:global(body) {
  margin: 0;
  overflow: hidden;
  background: #0f172a;
  color: #e2e8f0;
  user-select: none;
}

.shell {
  min-height: 100vh;
}

.sidebar {
  display: none;
}

.tab-shell {
  position: fixed;
  inset: 0 0 auto;
  z-index: 1000;
  display: flex;
  height: var(--titlebar-height);
  align-items: stretch;
  border-bottom: 1px solid rgba(148, 163, 184, 0.18);
  background: #000;
  -webkit-app-region: drag;
}

.shell.left .tab-shell {
  inset: 0 0 auto;
  width: 100%;
  height: var(--titlebar-height);
  flex-direction: row;
  align-items: stretch;
  border-right: 0;
  border-bottom: 1px solid rgba(148, 163, 184, 0.18);
}

.titlebar-app-name {
  position: absolute;
  inset: 0 var(--window-controls-width) 0 0;
  display: flex;
  align-items: center;
  justify-content: flex-start;
  min-width: 0;
  padding: 0 20px 0 16px;
  overflow: hidden;
  color: rgba(226, 232, 240, 0.92);
  font-size: 13px;
  font-weight: 700;
  letter-spacing: 0.04em;
  pointer-events: none;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.shell.is-mac .titlebar-app-name {
  inset: 0 var(--mac-traffic-light-space) 0 0;
}

.shell.left .sidebar {
  position: fixed;
  inset: var(--titlebar-height) auto 0 0;
  z-index: 999;
  width: var(--sidebar-width);
  display: flex;
  flex-direction: column;
  align-items: stretch;
  background: #000;
  border-right: 1px solid rgba(148, 163, 184, 0.18);
}

.sidebar-resize-handle {
  position: absolute;
  top: 0;
  right: -4px;
  bottom: 0;
  width: 8px;
  cursor: col-resize;
  -webkit-app-region: no-drag;
}

.sidebar-resize-handle::before {
  content: '';
  position: absolute;
  top: 0;
  right: 3px;
  bottom: 0;
  width: 2px;
  background: transparent;
  transition: background 160ms ease;
}

.sidebar-resize-handle:hover::before,
.sidebar-resize-handle.active::before {
  background: rgba(56, 189, 248, 0.72);
}

.window-controls {
  display: flex;
  height: var(--titlebar-height);
  flex: none;
  align-items: stretch;
  margin-left: auto;
  -webkit-app-region: no-drag;
}

.shell.left .window-controls {
  margin-left: auto;
}

.window-control {
  display: grid;
  width: 46px;
  height: 100%;
  place-items: center;
  padding: 0;
  border: 0;
  border-radius: 0;
  background: transparent;
  color: rgba(226, 232, 240, 0.72);
  cursor: default;
  transition: background 120ms ease, color 120ms ease;
}

.window-control:hover {
  background: rgba(148, 163, 184, 0.18);
  color: #f8fafc;
}

.window-control.close:hover {
  background: #c42b1c;
  color: #fff;
}

.window-control-icon {
  width: 13px;
  height: 13px;
  stroke-width: 1.8;
}

.tabs {
  display: flex;
  min-width: 0;
  flex: 1;
  align-items: center;
  gap: 4px;
  padding: 0 2px 0 0;
}

.shell.left .tabs {
  flex-direction: column;
  align-items: stretch;
  gap: 8px;
  padding: 0 10px 10px;
}

.shell.is-mac .tabs {
  padding-left: var(--mac-traffic-light-space);
}

.shell.is-mac.left .tabs {
  padding: 12px 10px 10px;
}

.tab-list {
  display: flex;
  align-self: center;
  min-width: 0;
  flex: 1;
  align-items: center;
  gap: 0;
  overflow: hidden;
}

.shell.left .tab-list {
  align-self: stretch;
  flex-direction: column;
  align-items: stretch;
  overflow-x: hidden;
  overflow-y: auto;
}

.tab {
  position: relative;
  display: flex;
  min-width: 84px;
  max-width: 180px;
  height: 32px;
  flex: 1 1 132px;
  align-items: center;
  gap: 6px;
  overflow: hidden;
  border: 1px solid rgba(148, 163, 184, 0.14);
  border-bottom-color: transparent;
  border-radius: 0;
  background: transparent;
  color: rgba(226, 232, 240, 0.6);
  padding: 0 10px;
  margin-right: -1px;
  text-align: left;
  cursor: default;
  transition: background 160ms ease, border-color 160ms ease, color 160ms ease, opacity 160ms ease;
  -webkit-app-region: no-drag;
}

.shell.left .tab {
  min-width: 0;
  max-width: none;
  width: 100%;
  height: 40px;
  flex: none;
  margin-right: 0;
  margin-bottom: -1px;
}

.tab.dragging {
  opacity: 0.48;
}

:global(.drop-before)::before,
:global(.drop-after)::after {
  content: '';
  position: absolute;
  top: 5px;
  bottom: 5px;
  width: 3px;
  border-radius: 999px;
  background: #38bdf8;
  pointer-events: none;
}

:global(.drop-before)::before {
  left: -2px;
}

:global(.drop-after)::after {
  right: -2px;
}

.shell.left :global(.drop-before)::before,
.shell.left :global(.drop-after)::after {
  left: 6px;
  right: 6px;
  width: auto;
  height: 3px;
}

.shell.left :global(.drop-before)::before {
  top: -2px;
  bottom: auto;
}

.shell.left :global(.drop-after)::after {
  top: auto;
  bottom: -2px;
}

.tab:hover {
  background: rgba(255, 255, 255, 0.03);
  color: #f8fafc;
  border-color: rgba(148, 163, 184, 0.22);
  border-bottom-color: transparent;
}

.shell.left .tab:hover {
  border-bottom-color: rgba(148, 163, 184, 0.22);
  border-right-color: transparent;
}

.tab.active {
  border-color: rgba(148, 163, 184, 0.22);
  border-bottom-color: #38bdf8;
  color: #f8fafc;
}

.shell.left .tab.active {
  border-bottom-color: rgba(148, 163, 184, 0.22);
  border-right-color: #38bdf8;
}

.tab-title {
  min-width: 0;
  flex: 1;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: 12px;
  font-weight: 600;
}

.tab-app-icon {
  display: inline-flex;
  width: 16px;
  height: 16px;
  flex: none;
  align-items: center;
  justify-content: center;
  color: #38bdf8;
}

.icon {
  width: 16px;
  height: 16px;
  stroke-width: 2;
}

.tab-title-input {
  min-width: 0;
  flex: 1;
  height: 24px;
  border: 1px solid rgba(56, 189, 248, 0.56);
  border-radius: 6px;
  outline: none;
  background: rgba(2, 6, 23, 0.72);
  color: #f8fafc;
  padding: 0 6px;
  font: inherit;
  font-size: 12px;
  font-weight: 600;
  -webkit-app-region: no-drag;
}

.tab-status {
  width: 8px;
  height: 8px;
  flex: none;
  border-radius: 999px;
  background: #38bdf8;
  opacity: 0;
}

.tab.loading .tab-status {
  opacity: 1;
  animation: pulse 0.9s ease-in-out infinite;
}

.tab-close,
.toolbar-button,
.new-tab {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  border: 0;
  color: currentColor;
  cursor: default;
  -webkit-app-region: no-drag;
}

.tab-close {
  width: 22px;
  height: 22px;
  flex: none;
  border-radius: 999px;
  background: transparent;
  opacity: 0.68;
}

.close-icon {
  width: 14px;
  height: 14px;
}

.tab-close:hover {
  background: rgba(148, 163, 184, 0.18);
  opacity: 1;
}

.new-tab,
.toolbar-button {
  width: 32px;
  height: 32px;
  padding: 0;
  border-radius: 10px;
  background: transparent;
  line-height: 0;
  opacity: 0.76;
}

.shell.left .new-tab,
.shell.left .toolbar-button {
  width: 100%;
  justify-content: flex-start;
  padding: 0 12px;
  border-radius: 12px;
}

.button-icon {
  flex: none;
}

.devtools-icon {
  width: 18px;
  height: 18px;
}

.new-tab:hover,
.toolbar-button:hover {
  background: rgba(148, 163, 184, 0.14);
  opacity: 1;
}

.toolbar {
  display: flex;
  flex: none;
  align-items: center;
  gap: 2px;
  padding: 3px 10px 3px 0;
  -webkit-app-region: no-drag;
}

.shell.left .toolbar {
  width: 100%;
  flex-direction: column;
  align-items: stretch;
  gap: 8px;
  padding: 0 10px 12px;
}

.toolbar-actions {
  display: flex;
  gap: 2px;
}

.shell.left .toolbar-actions {
  flex-direction: column;
  gap: 8px;
}

.toolbar-actions[hidden] {
  display: none;
}

.toolbar-label {
  display: none;
  margin-left: 10px;
  font-size: 12px;
  font-weight: 600;
  line-height: 1;
}

.shell.left .toolbar-label {
  display: inline;
}

.empty-state {
  position: fixed;
  inset: var(--titlebar-height) 0 0;
  display: none;
  place-items: center;
  background: #020617;
}

.shell.left .empty-state {
  inset: var(--titlebar-height) 0 0 var(--sidebar-width);
}

.empty-state.visible {
  display: grid;
}

.empty-action {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  height: 40px;
  padding: 0 16px;
  border: 1px solid rgba(148, 163, 184, 0.24);
  border-radius: 10px;
  background: rgba(15, 23, 42, 0.72);
  color: #e2e8f0;
  font-weight: 700;
  cursor: default;
  -webkit-app-region: no-drag;
}

.empty-action:hover {
  border-color: rgba(56, 189, 248, 0.48);
  background: rgba(30, 41, 59, 0.86);
  color: #f8fafc;
}

@media (max-width: 720px) {
  .shell.is-mac {
    --mac-traffic-light-space: 76px;
  }

  .tab {
    min-width: 76px;
  }
}

@keyframes pulse {
  0%,
  100% {
    transform: scale(0.8);
    opacity: 0.42;
  }

  50% {
    transform: scale(1);
    opacity: 1;
  }
}
</style>
