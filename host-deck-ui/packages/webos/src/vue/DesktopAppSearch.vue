<script setup lang="ts">
import { computed, nextTick, ref, shallowRef, watch } from 'vue'
import { Search, X } from '@lucide/vue'
import {
  ComboboxContent,
  ComboboxInput,
  ComboboxItem,
  ComboboxRoot,
  DialogContent,
  DialogPortal,
  DialogRoot,
  DialogTitle,
} from 'reka-ui'
import AppIcon from './AppIcon.vue'
import { useDesktopContext } from './context'

const props = defineProps<{ show: boolean }>()
const emit = defineEmits<{ close: [] }>()
const context = useDesktopContext()
const desktop = context.desktop
const query = ref('')
const combobox = ref<{ highlightFirstItem: () => void }>()
const input = ref<InstanceType<typeof ComboboxInput>>()
const composing = ref(false)
const interactedOutside = ref(false)
const pinyinSearch = shallowRef<typeof import('../core/app-search')>()
let pinyinLoading: Promise<void> | undefined
let previousFocus: HTMLElement | null = null
let launchedWindowId: string | undefined

const searchableApps = computed(() =>
  props.show
    ? Object.values(desktop.apps)
        .filter((app) => app.showInLaunchpad && !app.hide)
        .map((app) => ({ app, index: pinyinSearch.value?.createPinyinSearchIndex(app.title) }))
    : [],
)

const apps = computed(() => {
  const normalized = query.value.normalize('NFKC').toLocaleLowerCase().replace(/\s+/gu, '')
  return searchableApps.value
    .filter(
      ({ app, index }) =>
        [app.title, app.id].some((value) =>
          value.normalize('NFKC').toLocaleLowerCase().replace(/\s+/gu, '').includes(normalized),
        ) ||
        (index && pinyinSearch.value?.matchesPinyinSearch(index, normalized)),
    )
    .map(({ app }) => {
      const existing = desktop.windows
        .filter((window) => window.appId === app.id && !window.isClosing)
        .sort((left, right) => right.zIndex - left.zIndex)[0]
      return { app, existing, disabled: !existing && !desktop.canOpenWindow(app.id) }
    })
})

function loadPinyinSearch() {
  if (pinyinSearch.value || pinyinLoading) return
  pinyinLoading = import('../core/app-search')
    .then((module) => {
      pinyinSearch.value = module
    })
    .catch((error: unknown) => {
      console.warn(
        'WebOS could not load pinyin search; name and ID search are still available.',
        error,
      )
      pinyinLoading = undefined
    })
}

watch(
  () => props.show,
  (show) => {
    if (!show) return
    previousFocus = document.activeElement instanceof HTMLElement ? document.activeElement : null
    launchedWindowId = undefined
    interactedOutside.value = false
    composing.value = false
    query.value = ''
    loadPinyinSearch()
  },
  { immediate: true },
)

watch(
  apps,
  async () => {
    await nextTick()
    if (props.show && apps.value.length > 0) combobox.value?.highlightFirstItem()
  },
  { flush: 'post' },
)

async function focusInput(event: Event) {
  event.preventDefault()
  await nextTick()
  if (!props.show) return
  input.value?.$el.focus({ preventScroll: true })
  combobox.value?.highlightFirstItem()
}

function restoreFocus(event: Event) {
  event.preventDefault()
  if (launchedWindowId) {
    const target = Array.from(
      context.overlayTarget?.value?.querySelectorAll<HTMLElement>('[data-desktop-window-id]') ?? [],
    ).find((element) => element.dataset.desktopWindowId === launchedWindowId)
    target?.focus({ preventScroll: true })
  } else if (!interactedOutside.value && previousFocus?.isConnected) {
    previousFocus.focus({ preventScroll: true })
  }
}

function launch(appId: string) {
  if (composing.value) return
  const result = apps.value.find(({ app }) => app.id === appId)
  if (!result || result.disabled) return
  if (result.existing) {
    desktop.restoreWindow(result.existing.id)
    launchedWindowId = result.existing.id
  } else {
    launchedWindowId = desktop.openWindow(appId)
  }
  if (launchedWindowId) emit('close')
}

function closeOnEscape(event: KeyboardEvent) {
  event.preventDefault()
  if (!composing.value && !event.isComposing && event.keyCode !== 229) emit('close')
}

function guardComposition(event: KeyboardEvent) {
  if (composing.value || event.isComposing || event.keyCode === 229) event.stopPropagation()
}
</script>

<template>
  <DialogRoot :open="show" :modal="false" @update:open="!$event && emit('close')">
    <DialogPortal
      :to="context.overlayTarget?.value ?? undefined"
      :disabled="!context.overlayTarget?.value"
    >
      <div
        v-if="show"
        class="webos-app-search-layer absolute inset-0 z-[100003] flex items-start justify-center bg-[rgba(0,0,0,0.18)] p-[16px] pt-[min(12vh,80px)] backdrop-blur-[6px]"
        @pointerdown.self.prevent="emit('close')"
      >
        <DialogContent
          class="webos-app-search app-radius-card flex max-h-full w-full max-w-[560px] flex-col overflow-hidden outline-none"
          :aria-describedby="undefined"
          @open-auto-focus="focusInput"
          @close-auto-focus="restoreFocus"
          @interact-outside="interactedOutside = true"
          @escape-key-down="closeOnEscape"
          @keydown.capture="guardComposition"
          @compositionstart="composing = true"
          @compositionend="composing = false"
        >
          <DialogTitle class="sr-only">搜索应用</DialogTitle>
          <ComboboxRoot
            ref="combobox"
            class="flex min-h-0 flex-col"
            :open="true"
            model-value=""
            ignore-filter
            loop
            :reset-search-term-on-blur="false"
            :reset-search-term-on-select="false"
          >
            <div
              class="flex shrink-0 items-center gap-[12px] border-b border-[var(--webos-overlay-border)] px-[16px]"
            >
              <Search :size="20" class="shrink-0 opacity-60" aria-hidden="true" />
              <ComboboxInput
                ref="input"
                v-model="query"
                class="h-[60px] min-w-0 flex-1 border-0 bg-transparent text-[16px] text-inherit outline-none"
                placeholder="搜索应用"
                aria-label="搜索应用"
              />
              <button
                type="button"
                class="webos-icon-button inline-flex h-[28px] w-[28px] shrink-0 items-center justify-center rounded-full border-0 bg-transparent p-0 text-inherit cursor-pointer"
                aria-label="关闭快捷搜索"
                @click="emit('close')"
              >
                <X :size="16" aria-hidden="true" />
              </button>
            </div>
            <ComboboxContent
              class="min-h-0 overflow-y-auto p-[6px]"
              :style="{ maxHeight: '360px' }"
              @escape-key-down="closeOnEscape"
              @focus-outside.prevent
              @interact-outside.prevent
              @pointer-down-outside.prevent
            >
              <ComboboxItem
                v-for="{ app, existing, disabled } in apps"
                :key="app.id"
                :value="app.id"
                :text-value="app.title"
                :disabled="disabled"
                class="webos-app-search-item app-radius-item flex items-center gap-[12px] px-[12px] py-[10px] outline-none"
                @select.prevent="launch(app.id)"
              >
                <AppIcon :name="app.icon" :size="36" themed />
                <span class="min-w-0 flex-1 truncate text-[14px]">{{ app.title }}</span>
                <span v-if="existing || disabled" class="shrink-0 text-[12px] opacity-50">
                  {{ existing ? '已打开' : '不可用' }}
                </span>
              </ComboboxItem>
              <div
                v-if="!apps.length"
                role="status"
                class="px-[12px] py-[28px] text-center text-[14px] opacity-60"
              >
                未找到应用
              </div>
            </ComboboxContent>
          </ComboboxRoot>
        </DialogContent>
      </div>
    </DialogPortal>
  </DialogRoot>
</template>
