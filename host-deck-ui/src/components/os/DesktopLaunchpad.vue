<script setup lang="ts">
import { computed, nextTick, ref, watch } from 'vue'
import { Pin, PinOff, Search, X } from '@lucide/vue'
import AppIcon from '@/components/common/AppIcon.vue'
import { useDesktopStore } from '@/stores/desktop'
import { useSettingsStore } from '@/stores/settings'
import type { DesktopAppId } from '@/types/desktop'

const props = defineProps<{
  show: boolean
}>()

const emit = defineEmits<{
  close: []
}>()

const desktopStore = useDesktopStore()
const settingsStore = useSettingsStore()
const query = ref('')
const searchInput = ref<HTMLInputElement | null>(null)

const iconColors: Partial<Record<DesktopAppId, string>> = {
  dashboard: '#0ea5e9',
  docker: '#0284c7',
  'cron-tasks': '#d97706',
  files: '#f59e0b',
  opencode: '#a855f7',
  'operation-logs': '#64748b',
  'realtime-logs': '#0891b2',
  'port-forward': '#0891b2',
  processes: '#16a34a',
  'runtime-sessions': '#0d9488',
  settings: '#64748b',
  terminal: '#059669',
}

const apps = computed(() => {
  const normalizedQuery = query.value.trim().toLocaleLowerCase()
  return Object.values(desktopStore.apps).filter(
    (app) =>
      app.showInLaunchpad &&
      (!normalizedQuery || app.title.toLocaleLowerCase().includes(normalizedQuery)),
  )
})

watch(
  () => props.show,
  async (show) => {
    if (!show) {
      query.value = ''
      return
    }

    await nextTick()
    searchInput.value?.focus()
  },
)

function openApp(appId: DesktopAppId) {
  const existingWindow = desktopStore.windows.find(
    (window) => window.appId === appId && !window.isClosing,
  )
  if (existingWindow) {
    desktopStore.restoreWindow(existingWindow.id)
  } else {
    desktopStore.openWindow(appId)
  }
  emit('close')
}

function toggleDockPin(appId: DesktopAppId) {
  if (desktopStore.isAppPinnedToDock(appId)) {
    desktopStore.unpinAppFromDock(appId)
  } else {
    desktopStore.pinAppToDock(appId)
  }
}
</script>

<template>
  <Teleport to="body">
    <Transition name="launchpad">
      <section
        v-if="show"
        class="launchpad fixed inset-0 z-[9000] overflow-y-auto px-[24px] pb-[72px] pt-[68px] backdrop-blur-[32px]"
        :class="
          settingsStore.isDark
            ? 'bg-[rgba(2,6,23,0.68)] text-[#f8fafc]'
            : 'bg-[rgba(241,245,249,0.72)] text-[#0f172a]'
        "
        aria-label="应用启动台"
        role="dialog"
        aria-modal="true"
        @click.self="emit('close')"
      >
        <button
          type="button"
          class="fixed right-[22px] top-[18px] flex h-[38px] w-[38px] items-center justify-center rounded-full border-0 bg-[rgba(15,23,42,0.14)] text-current cursor-pointer hover:bg-[rgba(15,23,42,0.24)]"
          aria-label="关闭启动台"
          title="关闭"
          @click="emit('close')"
        >
          <X :size="20" />
        </button>

        <div class="launchpad-content mx-auto w-full max-w-[1040px]">
          <div
            class="mx-auto flex max-w-[360px] items-center gap-[9px] rounded-[10px] bg-[rgba(255,255,255,0.2)] px-[12px] ring-1 ring-[rgba(148,163,184,0.32)] focus-within:ring-[var(--app-primary-color)]"
          >
            <Search :size="17" class="shrink-0 opacity-60" aria-hidden="true" />
            <input
              ref="searchInput"
              v-model="query"
              type="search"
              class="h-[40px] min-w-0 flex-1 border-0 bg-transparent text-[0.9rem] text-current outline-none placeholder:text-current placeholder:opacity-50"
              placeholder="搜索应用"
              aria-label="搜索应用"
            />
          </div>

          <TransitionGroup
            v-if="apps.length"
            name="launchpad-app"
            tag="div"
            class="mt-[54px] grid grid-cols-[repeat(auto-fill,minmax(116px,1fr))] gap-x-[28px] gap-y-[38px]"
          >
            <div v-for="app in apps" :key="app.id" class="group relative min-w-0 text-center">
              <button
                type="button"
                class="mx-auto flex w-full flex-col items-center border-0 bg-transparent p-0 text-current cursor-pointer"
                @click="openApp(app.id)"
              >
                <span
                  class="app-radius-card flex h-[76px] w-[76px] items-center justify-center rounded-[18px] border border-[rgba(255,255,255,0.3)] transition-transform duration-150 group-hover:scale-[1.06] group-active:scale-[0.96]"
                  :class="settingsStore.isDark ? 'bg-[#000]' : 'bg-[#fff]'"
                >
                  <AppIcon :color="iconColors[app.id]" :name="app.icon" :size="38" />
                </span>
                <span
                  class="mt-[10px] max-w-full break-words text-[0.86rem] font-500 leading-[1.3]"
                >
                  {{ app.title }}
                </span>
              </button>

              <button
                type="button"
                class="absolute top-[-8px] flex h-[28px] w-[28px] items-center justify-center rounded-full border border-[rgba(255,255,255,0.42)] bg-[rgba(15,23,42,0.72)] text-white opacity-0 shadow-md transition-opacity cursor-pointer group-hover:opacity-100 focus:opacity-100"
                style="right: calc(50% - 48px)"
                :aria-label="
                  desktopStore.isAppPinnedToDock(app.id)
                    ? `从 Dock 移除${app.title}`
                    : `将${app.title}固定到 Dock`
                "
                :title="desktopStore.isAppPinnedToDock(app.id) ? '从 Dock 移除' : '固定到 Dock'"
                @click.stop="toggleDockPin(app.id)"
              >
                <PinOff v-if="desktopStore.isAppPinnedToDock(app.id)" :size="14" />
                <Pin v-else :size="14" />
              </button>
            </div>
          </TransitionGroup>

          <div v-else class="mt-[96px] text-center text-[0.92rem] opacity-60">未找到应用</div>
        </div>
      </section>
    </Transition>
  </Teleport>
</template>

<style scoped>
.launchpad-enter-active,
.launchpad-leave-active {
  transition:
    opacity 220ms ease,
    backdrop-filter 220ms ease;
}

.launchpad-enter-from,
.launchpad-leave-to {
  opacity: 0;
  backdrop-filter: blur(0);
}

.launchpad-content {
  transform-origin: center 42%;
  transition:
    opacity 220ms ease,
    transform 260ms cubic-bezier(0.16, 1, 0.3, 1);
}

.launchpad-app-enter-active,
.launchpad-app-leave-active,
.launchpad-app-move {
  transition:
    opacity 220ms ease,
    transform 260ms cubic-bezier(0.16, 1, 0.3, 1);
}

.launchpad-app-enter-from,
.launchpad-app-leave-to {
  opacity: 0;
  transform: translateY(16px) scale(0.88);
}

.launchpad-app-leave-active {
  position: absolute;
}

.launchpad-enter-from .launchpad-content {
  opacity: 0;
  transform: translateY(18px) scale(0.96);
}

.launchpad-leave-to .launchpad-content {
  opacity: 0;
  transform: translateY(10px) scale(0.97);
}

@media (max-width: 640px) {
  .launchpad {
    padding-inline: 14px;
    padding-top: 62px;
  }
}

@media (hover: none) {
  .group > button:last-child {
    opacity: 1;
  }
}

@media (prefers-reduced-motion: reduce) {
  .launchpad-enter-active,
  .launchpad-leave-active,
  .launchpad-content {
    transition-duration: 1ms;
  }

  .launchpad-app-enter-active,
  .launchpad-app-leave-active,
  .launchpad-app-move {
    transition-duration: 1ms;
  }
}
</style>
