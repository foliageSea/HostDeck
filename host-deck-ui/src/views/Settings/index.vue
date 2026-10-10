<script setup lang="ts">
import { Renew } from '@vicons/carbon'
import { AppWindow, Image as ImageIcon, Keyboard, Network, Palette, ShieldCheck } from '@lucide/vue'
import { isAxiosError } from 'axios'
import { computed, nextTick, onMounted, ref } from 'vue'
import { settingsApi } from '@/api/settings'
import { downloadBlob } from '@/lib/download'
import { createKeyboardShortcut, formatKeyboardShortcut } from '@/lib/keyboard-shortcut'
import { getUiApi } from '@/lib/ui'
import BackendPortsSection from './components/BackendPortsSection.vue'
import TotpSecuritySection from './components/TotpSecuritySection.vue'
import WallpaperSection from './components/WallpaperSection.vue'
import { useWallpaperSettings } from './hooks/useWallpaperSettings'

const uiVersion = __APP_VERSION__

const controller = useWallpaperSettings()
const { settingsStore } = controller
const serviceVersion = ref<string>()
const serviceVersionLoading = ref(true)
const clearingBrowserCache = ref(false)
const externalAccess = ref(false)
const externalAccessLoading = ref(false)
const exportingLogs = ref(false)
const recordingWindowSwitchShortcut = ref(false)
const recordingWindowSwitcherToggleShortcut = ref(false)
const backendPortsSection = ref<InstanceType<typeof BackendPortsSection>>()
const canClearBrowserCache = computed(() => Boolean(window.hostDeck?.app?.clearBrowserCache))
const canManageExternalAccess = computed(() =>
  Boolean(window.hostDeck?.app?.getExternalAccess && window.hostDeck?.app?.setExternalAccess),
)

async function handleTabChange(tab: string | number) {
  if (tab !== 'ports') {
    return
  }

  await nextTick()
  await backendPortsSection.value?.refresh()
}

onMounted(async () => {
  try {
    serviceVersion.value = (await settingsApi.getServiceVersion()).version
  } catch {
    serviceVersion.value = undefined
  } finally {
    serviceVersionLoading.value = false
  }

  if (canManageExternalAccess.value) {
    externalAccess.value = (await window.hostDeck?.app?.getExternalAccess()) ?? false
  }
})

const primaryColorPresets = ['#2563eb', '#0891b2', '#059669', '#7c3aed', '#db2777', '#ea580c']
const windowSwitchShortcutLabel = computed(() =>
  formatKeyboardShortcut(settingsStore.windowSwitchShortcut),
)
const windowSwitcherToggleShortcutLabel = computed(() =>
  formatKeyboardShortcut(settingsStore.windowSwitcherToggleShortcut),
)
const windowSwitchShortcutKeys = computed(() =>
  getShortcutDisplayKeys(windowSwitchShortcutLabel.value),
)
const windowSwitcherToggleShortcutKeys = computed(() =>
  getShortcutDisplayKeys(windowSwitcherToggleShortcutLabel.value),
)

function getShortcutDisplayKeys(label: string) {
  return label.split(' + ').map((key) => (key === 'Command / Control' ? 'Cmd / Ctrl' : key))
}

function recordWindowSwitchShortcut(event: KeyboardEvent) {
  if (!recordingWindowSwitchShortcut.value) {
    return
  }

  event.preventDefault()
  event.stopPropagation()
  if (event.key === 'Escape') {
    recordingWindowSwitchShortcut.value = false
    return
  }

  const shortcut = createKeyboardShortcut(event)
  if (!shortcut) {
    return
  }

  settingsStore.setWindowSwitchShortcut(shortcut)
  recordingWindowSwitchShortcut.value = false
}

function recordWindowSwitcherToggleShortcut(event: KeyboardEvent) {
  if (!recordingWindowSwitcherToggleShortcut.value) {
    return
  }

  event.preventDefault()
  event.stopPropagation()
  if (event.key === 'Escape') {
    recordingWindowSwitcherToggleShortcut.value = false
    return
  }

  const shortcut = createKeyboardShortcut(event)
  if (!shortcut) {
    return
  }

  settingsStore.setWindowSwitcherToggleShortcut(shortcut)
  recordingWindowSwitcherToggleShortcut.value = false
}

function confirmClearBrowserCache() {
  const dialog = getUiApi().dialog.warning({
    title: '清理浏览器缓存',
    content:
      '将清理 Electron 内置浏览器缓存，不会删除登录信息、应用设置、壁纸或本地数据。是否继续？',
    positiveText: '清理缓存',
    negativeText: '取消',
    onPositiveClick: async () => {
      dialog.loading = true
      clearingBrowserCache.value = true
      try {
        await window.hostDeck?.app?.clearBrowserCache()
        getUiApi().message.success('浏览器缓存已清理。')
      } catch (error) {
        getUiApi().message.error(error instanceof Error ? error.message : '清理浏览器缓存失败。')
      } finally {
        dialog.loading = false
        clearingBrowserCache.value = false
      }
    },
  })
}

async function updateExternalAccess(value: boolean) {
  externalAccessLoading.value = true
  try {
    externalAccess.value = (await window.hostDeck?.app?.setExternalAccess(value)) ?? false
    getUiApi().message.success(externalAccess.value ? '已允许局域网访问。' : '已恢复仅本机访问。')
  } catch (error) {
    externalAccess.value = !value
    getUiApi().message.error(error instanceof Error ? error.message : '更新外部访问设置失败。')
  } finally {
    externalAccessLoading.value = false
  }
}

async function getExportErrorMessage(error: unknown) {
  if (isAxiosError(error) && error.response?.data instanceof Blob) {
    try {
      const payload = JSON.parse(await error.response.data.text()) as { message?: unknown }
      if (typeof payload.message === 'string' && payload.message.trim()) {
        return payload.message
      }
    } catch {
      // Fall back to the Axios error message.
    }
  }
  return error instanceof Error ? error.message : '导出日志失败。'
}

function buildLogArchiveName() {
  const now = new Date()
  const pad = (value: number) => String(value).padStart(2, '0')
  const timestamp = `${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}T${pad(now.getHours())}${pad(now.getMinutes())}${pad(now.getSeconds())}`
  return `hostdeck-logs-${timestamp}.zip`
}

async function exportLogs() {
  exportingLogs.value = true
  try {
    const archive = await settingsApi.exportLogs()
    downloadBlob(archive, buildLogArchiveName())
    getUiApi().message.success('日志已导出。')
  } catch (error) {
    getUiApi().message.error(await getExportErrorMessage(error))
  } finally {
    exportingLogs.value = false
  }
}
</script>

<template>
  <div
    class="settings-view scrollbar-none h-full overflow-hidden px-[20px] pt-[16px] pb-[20px] lt-md:px-[16px] lt-md:pb-[16px]"
  >
    <NTabs
      type="line"
      placement="left"
      class="settings-tabs h-full"
      @update:value="handleTabChange"
    >
      <NTabPane name="appearance">
        <template #tab>
          <span class="flex items-center gap-[8px]">
            <Palette :size="16" class="shrink-0" aria-hidden="true" />
            <span>外观</span>
          </span>
        </template>
        <section>
          <h2 class="m-0 mb-[20px] text-[16px] font-600">基础设置</h2>
          <NForm label-placement="top">
            <NFormItem label="主题模式">
              <NRadioGroup :value="settingsStore.themeMode" @update:value="settingsStore.setTheme">
                <NSpace>
                  <NRadio value="system">跟随系统</NRadio>
                  <NRadio value="dark">深色</NRadio>
                  <NRadio value="light">浅色</NRadio>
                </NSpace>
              </NRadioGroup>
            </NFormItem>
            <NFormItem label="主题色">
              <div class="flex flex-wrap items-center gap-[12px]">
                <NColorPicker
                  :value="settingsStore.primaryColor"
                  :show-alpha="false"
                  :modes="['hex']"
                  @update:value="settingsStore.setPrimaryColor"
                >
                  <template #trigger="{ value, onClick, ref: triggerRef }">
                    <button
                      :ref="triggerRef"
                      type="button"
                      class="h-[32px] w-[32px] shrink-0 cursor-pointer rounded-full border-2 border-solid border-white p-0 shadow-[0_2px_8px_rgba(0,0,0,0.15)] transition-[transform,box-shadow] duration-[160ms] ease-in-out hover:scale-[1.08]"
                      :style="{ backgroundColor: value || settingsStore.primaryColor }"
                      :aria-label="`选择主题色，当前 ${value || settingsStore.primaryColor}`"
                      @click="onClick"
                    />
                  </template>
                </NColorPicker>
                <div class="flex items-center gap-[8px]">
                  <button
                    v-for="color in primaryColorPresets"
                    :key="color"
                    type="button"
                    class="h-[28px] w-[28px] cursor-pointer rounded-full border border-[rgba(148,163,184,0.28)] p-0 transition-[transform,box-shadow] duration-[160ms] ease-in-out hover:scale-[1.08]"
                    :class="
                      settingsStore.primaryColor === color
                        ? 'shadow-[0_0_0_3px_var(--app-primary-soft)]'
                        : ''
                    "
                    :style="{ backgroundColor: color }"
                    :aria-label="`设置主题色 ${color}`"
                    @click="settingsStore.setPrimaryColor(color)"
                  />
                </div>
                <NTooltip>
                  <template #trigger>
                    <NButton
                      circle
                      secondary
                      aria-label="恢复默认主题色"
                      @click="settingsStore.resetPrimaryColor"
                    >
                      <template #icon>
                        <NIcon>
                          <Renew />
                        </NIcon>
                      </template>
                    </NButton>
                  </template>
                  恢复默认
                </NTooltip>
              </div>
            </NFormItem>
            <NFormItem label="窗口按钮风格">
              <NRadioGroup
                :value="settingsStore.windowControlsStyle"
                @update:value="settingsStore.setWindowControlsStyle"
              >
                <NSpace>
                  <NRadio value="mac">Mac</NRadio>
                  <NRadio value="win">Windows</NRadio>
                </NSpace>
              </NRadioGroup>
            </NFormItem>
            <NFormItem label="窗口高斯模糊">
              <div class="flex w-full items-center justify-between gap-[16px]">
                <span class="text-[12px] text-[rgba(148,163,184,0.96)]">
                  关闭后标题栏和窗体将使用纯色背景。
                </span>
                <NSwitch
                  :value="settingsStore.windowBlur"
                  @update:value="settingsStore.setWindowBlur"
                />
              </div>
            </NFormItem>
            <NFormItem label="暗色窗口边框">
              <div class="flex w-full items-center justify-between gap-[16px]">
                <span class="text-[12px] text-[rgba(148,163,184,0.96)]">
                  使用主题色边框区分暗色模式下的窗口层次。
                </span>
                <NSwitch
                  :value="settingsStore.darkWindowBorder"
                  @update:value="settingsStore.setDarkWindowBorder"
                />
              </div>
            </NFormItem>
            <NFormItem label="圆角风格">
              <NRadioGroup
                :value="settingsStore.cornerStyle"
                @update:value="settingsStore.setCornerStyle"
              >
                <NSpace>
                  <NRadio value="square">直角</NRadio>
                  <NRadio value="soft">小圆角</NRadio>
                  <NRadio value="rounded">圆角</NRadio>
                </NSpace>
              </NRadioGroup>
            </NFormItem>
            <NFormItem label="Dock 栏">
              <div class="flex w-full items-center justify-between gap-[16px]">
                <div class="text-[12px] text-[rgba(148,163,184,0.96)]">
                  开启后 Dock 栏会在鼠标移入屏幕底部时显示。
                </div>
                <NSwitch
                  :value="settingsStore.dockAutoHide"
                  @update:value="settingsStore.setDockAutoHide"
                />
              </div>
            </NFormItem>
          </NForm>
        </section>
      </NTabPane>

      <NTabPane name="shortcuts">
        <template #tab>
          <span class="flex items-center gap-[8px]">
            <Keyboard :size="16" class="shrink-0" aria-hidden="true" />
            <span>快捷键</span>
          </span>
        </template>
        <section>
          <h2 class="m-0 mb-[20px] text-[16px] font-600">快捷键设置</h2>
          <NForm label-placement="top">
            <NFormItem label="直接切换窗口快捷键">
              <div class="flex w-full flex-nowrap items-center gap-[10px]">
                <button
                  data-shortcut-recorder
                  type="button"
                  class="shortcut-recorder"
                  :class="{ 'shortcut-recorder--recording': recordingWindowSwitchShortcut }"
                  :aria-label="
                    recordingWindowSwitchShortcut
                      ? '正在录入直接切换窗口快捷键，请按下组合键'
                      : `直接切换窗口快捷键：${windowSwitchShortcutLabel}`
                  "
                  @blur="recordingWindowSwitchShortcut = false"
                  @focus="recordingWindowSwitchShortcut = true"
                  @keydown="recordWindowSwitchShortcut"
                >
                  <span v-if="recordingWindowSwitchShortcut" class="shortcut-recorder__hint">
                    请按组合键
                  </span>
                  <template v-else>
                    <template v-for="(key, index) in windowSwitchShortcutKeys" :key="key">
                      <span v-if="index" class="shortcut-recorder__plus" aria-hidden="true">+</span>
                      <kbd class="shortcut-recorder__key">{{ key }}</kbd>
                    </template>
                  </template>
                </button>
                <NTooltip>
                  <template #trigger>
                    <NButton
                      class="shrink-0"
                      circle
                      secondary
                      aria-label="恢复默认直接切换窗口快捷键"
                      @click="settingsStore.resetWindowSwitchShortcut"
                    >
                      <template #icon>
                        <NIcon><Renew /></NIcon>
                      </template>
                    </NButton>
                  </template>
                  恢复默认
                </NTooltip>
              </div>
            </NFormItem>
            <NFormItem label="打开/关闭窗口选择器快捷键">
              <div class="flex w-full flex-nowrap items-center gap-[10px]">
                <button
                  data-shortcut-recorder
                  type="button"
                  class="shortcut-recorder"
                  :class="{
                    'shortcut-recorder--recording': recordingWindowSwitcherToggleShortcut,
                  }"
                  :aria-label="
                    recordingWindowSwitcherToggleShortcut
                      ? '正在录入窗口选择器快捷键，请按下组合键'
                      : `打开/关闭窗口选择器快捷键：${windowSwitcherToggleShortcutLabel}`
                  "
                  @blur="recordingWindowSwitcherToggleShortcut = false"
                  @focus="recordingWindowSwitcherToggleShortcut = true"
                  @keydown="recordWindowSwitcherToggleShortcut"
                >
                  <span
                    v-if="recordingWindowSwitcherToggleShortcut"
                    class="shortcut-recorder__hint"
                  >
                    请按组合键
                  </span>
                  <template v-else>
                    <template v-for="(key, index) in windowSwitcherToggleShortcutKeys" :key="key">
                      <span v-if="index" class="shortcut-recorder__plus" aria-hidden="true">+</span>
                      <kbd class="shortcut-recorder__key">{{ key }}</kbd>
                    </template>
                  </template>
                </button>
                <NTooltip>
                  <template #trigger>
                    <NButton
                      class="shrink-0"
                      circle
                      secondary
                      aria-label="恢复默认窗口选择器快捷键"
                      @click="settingsStore.resetWindowSwitcherToggleShortcut"
                    >
                      <template #icon>
                        <NIcon><Renew /></NIcon>
                      </template>
                    </NButton>
                  </template>
                  恢复默认
                </NTooltip>
              </div>
            </NFormItem>
          </NForm>
        </section>
      </NTabPane>

      <NTabPane name="wallpaper">
        <template #tab>
          <span class="flex items-center gap-[8px]">
            <ImageIcon :size="16" class="shrink-0" aria-hidden="true" />
            <span>壁纸</span>
          </span>
        </template>
        <section>
          <h2 class="m-0 mb-[20px] text-[16px] font-600">壁纸设置</h2>
          <NSpace vertical :size="24">
            <WallpaperSection target="desktop" title="桌面与登录页壁纸" :controller="controller" />
          </NSpace>
        </section>
      </NTabPane>

      <NTabPane name="ports">
        <template #tab>
          <span class="flex items-center gap-[8px]">
            <Network :size="16" class="shrink-0" aria-hidden="true" />
            <span>后端端口</span>
          </span>
        </template>
        <BackendPortsSection ref="backendPortsSection" />
      </NTabPane>

      <NTabPane name="security">
        <template #tab>
          <span class="flex items-center gap-[8px]">
            <ShieldCheck :size="16" class="shrink-0" aria-hidden="true" />
            <span>安全</span>
          </span>
        </template>
        <TotpSecuritySection />
      </NTabPane>

      <NTabPane name="app">
        <template #tab>
          <span class="flex items-center gap-[8px]">
            <AppWindow :size="16" class="shrink-0" aria-hidden="true" />
            <span>应用</span>
          </span>
        </template>
        <section>
          <h2 class="m-0 mb-[20px] text-[16px] font-600">应用维护</h2>
          <div class="flex flex-col gap-[12px]">
            <div
              class="app-radius-item flex flex-wrap items-center justify-between gap-[16px] rounded-[14px] border border-[rgba(148,163,184,0.16)] p-[14px]"
            >
              <div>
                <div class="text-[14px] font-600">前端版本</div>
                <div class="mt-[4px] text-[12px] text-[rgba(148,163,184,0.96)]">当前 UI 版本</div>
              </div>
              <NTag type="info" size="small" :bordered="false">v{{ uiVersion }}</NTag>
            </div>

            <div
              class="app-radius-item flex flex-wrap items-center justify-between gap-[16px] rounded-[14px] border border-[rgba(148,163,184,0.16)] p-[14px]"
            >
              <div>
                <div class="text-[14px] font-600">后端服务版本</div>
                <div class="mt-[4px] text-[12px] text-[rgba(148,163,184,0.96)]">
                  当前连接的 HostDeck 服务版本
                </div>
              </div>
              <NTag type="success" size="small" :bordered="false">
                {{
                  serviceVersionLoading
                    ? '获取中'
                    : serviceVersion
                      ? `v${serviceVersion}`
                      : '获取失败'
                }}
              </NTag>
            </div>

            <div
              class="app-radius-item flex flex-wrap items-center justify-between gap-[16px] rounded-[14px] border border-[rgba(148,163,184,0.16)] p-[14px]"
            >
              <div class="min-w-0 flex-1">
                <div class="text-[14px] font-600">运行日志</div>
                <div class="mt-[4px] text-[12px] text-[rgba(148,163,184,0.96)]">
                  导出运行日志，用于问题排查。
                </div>
              </div>
              <NButton type="primary" secondary :loading="exportingLogs" @click="exportLogs">
                导出日志
              </NButton>
            </div>
            <div
              v-if="canManageExternalAccess"
              class="app-radius-item flex flex-wrap items-center justify-between gap-[16px] rounded-[14px] border border-[rgba(148,163,184,0.16)] p-[14px]"
            >
              <div>
                <div class="text-[14px] font-600">允许外部访问</div>
                <div class="mt-[4px] text-[12px] text-[rgba(148,163,184,0.96)]">
                  开启后内置后端将绑定 0.0.0.0，可通过本机局域网 IP 访问当前服务。
                </div>
              </div>
              <NSwitch
                :value="externalAccess"
                :loading="externalAccessLoading"
                @update:value="updateExternalAccess"
              />
            </div>

            <div
              v-if="canClearBrowserCache"
              class="app-radius-item flex flex-wrap items-center justify-between gap-[16px] rounded-[14px] border border-[rgba(148,163,184,0.16)] p-[14px]"
            >
              <div>
                <div class="text-[14px] font-600">浏览器缓存</div>
                <div class="mt-[4px] text-[12px] text-[rgba(148,163,184,0.96)]">
                  清理内置浏览器缓存，不影响登录信息、应用设置、壁纸和本地数据。
                </div>
              </div>
              <NButton
                type="warning"
                secondary
                :loading="clearingBrowserCache"
                @click="confirmClearBrowserCache"
              >
                清理浏览器缓存
              </NButton>
            </div>
          </div>
        </section>
      </NTabPane>
    </NTabs>
  </div>
</template>

<style scoped>
.settings-view {
  box-sizing: border-box;
  container-type: inline-size;
}

.settings-view::-webkit-scrollbar {
  width: 0;
  height: 0;
  display: none;
}

.wallpaper-section + .wallpaper-section {
  padding-top: 4px;
}

.shortcut-recorder {
  display: flex;
  min-width: 0;
  max-width: 240px;
  min-height: 40px;
  flex: 1;
  align-items: center;
  gap: 7px;
  overflow-x: auto;
  border: 1px solid rgba(148, 163, 184, 0.2);
  border-radius: var(--app-radius-control);
  padding: 7px 12px;
  color: inherit;
  background: rgba(148, 163, 184, 0.1);
  font: inherit;
  text-align: left;
  cursor: pointer;
  scrollbar-width: none;
  transition:
    border-color 160ms ease,
    background-color 160ms ease,
    box-shadow 160ms ease;
}

.shortcut-recorder::-webkit-scrollbar {
  display: none;
}

.shortcut-recorder:hover {
  border-color: rgba(148, 163, 184, 0.42);
  background: rgba(148, 163, 184, 0.14);
}

.shortcut-recorder:focus-visible {
  outline: 0;
  border-color: var(--app-primary-color);
  box-shadow: 0 0 0 3px var(--app-primary-soft);
}

.shortcut-recorder--recording {
  border-color: var(--app-primary-color);
  background: var(--app-primary-soft);
}

.shortcut-recorder__key {
  display: inline-flex;
  min-height: 22px;
  align-items: center;
  justify-content: center;
  flex: 0 0 auto;
  border: 1px solid rgba(148, 163, 184, 0.28);
  border-bottom-color: rgba(148, 163, 184, 0.45);
  border-radius: 6px;
  padding: 1px 8px;
  color: inherit;
  background: rgba(15, 23, 42, 0.34);
  box-shadow: 0 2px 0 rgba(15, 23, 42, 0.24);
  font-family: inherit;
  font-size: 12px;
  font-weight: 500;
  line-height: 18px;
  white-space: nowrap;
}

.shortcut-recorder__plus {
  flex: 0 0 auto;
  color: rgba(148, 163, 184, 0.72);
  font-size: 12px;
  font-weight: 500;
}

.shortcut-recorder__hint {
  color: var(--app-primary-color);
  font-size: 12px;
  font-weight: 500;
  white-space: nowrap;
}

.settings-tabs {
  display: flex;
  min-width: 0;
  min-height: 0;
  flex-direction: row;
}

.settings-tabs :deep(.n-tabs-nav--left) {
  width: 128px;
  flex: 0 0 128px;
}

.settings-tabs :deep(.n-tabs-tab-wrapper),
.settings-tabs :deep(.n-tabs-tab) {
  width: 100%;
}

.settings-tabs :deep(.n-tabs-tab) {
  justify-content: flex-start;
  padding: 6px 16px;
}

.settings-tabs :deep(.n-tabs-tab-pad) {
  height: 4px;
}

.settings-tabs :deep(.n-tab-pane) {
  box-sizing: border-box;
  height: 100%;
  min-width: 0;
  min-height: 0;
  overflow-y: auto;
  flex: 1;
  scrollbar-width: none;
  padding: 20px 24px;
}

.settings-tabs :deep(.n-tab-pane)::-webkit-scrollbar {
  display: none;
}

@container (max-width: 520px) {
  .settings-tabs :deep(.n-tabs-nav--left) {
    width: 112px;
    flex-basis: 112px;
  }

  .settings-tabs :deep(.n-tabs-tab) {
    padding: 6px 10px;
  }

  .settings-tabs :deep(.n-tab-pane) {
    padding: 16px;
  }
}
</style>
