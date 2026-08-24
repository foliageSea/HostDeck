<script setup lang="ts">
import { Renew } from '@vicons/carbon'
import { isAxiosError } from 'axios'
import { computed, onMounted, ref } from 'vue'
import { settingsApi } from '@/api/settings'
import { downloadBlob } from '@/lib/download'
import { getUiApi } from '@/lib/ui'
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
const canClearBrowserCache = computed(() => Boolean(window.hostDeck?.app?.clearBrowserCache))
const canManageExternalAccess = computed(() =>
  Boolean(window.hostDeck?.app?.getExternalAccess && window.hostDeck?.app?.setExternalAccess),
)

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
    class="settings-view scrollbar-none h-full overflow-hidden px-[20px] pb-[20px] lt-md:px-[16px] lt-md:pb-[16px]"
  >
    <NTabs type="line" animated class="settings-tabs h-full">
      <NTabPane name="appearance" tab="外观">
        <NCard title="基础设置" size="large">
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
                <div class="w-[180px]">
                  <NColorPicker
                    :value="settingsStore.primaryColor"
                    :show-alpha="false"
                    :modes="['hex']"
                    @update:value="settingsStore.setPrimaryColor"
                  />
                </div>
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
        </NCard>
      </NTabPane>

      <NTabPane name="wallpaper" tab="壁纸">
        <NCard title="壁纸设置" size="large">
          <NSpace vertical :size="24">
            <WallpaperSection
              target="desktop"
              title="桌面与登录页壁纸"
              :controller="controller"
            />
          </NSpace>
        </NCard>
      </NTabPane>

      <NTabPane name="app" tab="应用">
        <NCard title="应用维护" size="large">
          <div class="flex flex-col gap-[12px]">
            <div
              class="app-radius-item flex flex-wrap items-center justify-between gap-[16px] rounded-[14px] border border-[rgba(148,163,184,0.16)] p-[14px]"
            >
              <div>
                <div class="text-[14px] font-600">前端版本</div>
                <div class="mt-[4px] text-[12px] text-[rgba(148,163,184,0.96)]">
                  当前 UI 版本
                </div>
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
                {{ serviceVersionLoading ? '获取中' : serviceVersion ? `v${serviceVersion}` : '获取失败' }}
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
        </NCard>
      </NTabPane>
    </NTabs>
  </div>
</template>

<style scoped>
.settings-view::-webkit-scrollbar {
  width: 0;
  height: 0;
  display: none;
}

.wallpaper-section + .wallpaper-section {
  padding-top: 4px;
}

.settings-tabs {
  display: flex;
  flex-direction: column;
}

.settings-tabs :deep(.n-tabs-pane-wrapper) {
  min-height: 0;
  overflow-y: auto;
  flex: 1;
  scrollbar-width: none;
  padding-top: 4px;
}

.settings-tabs :deep(.n-tabs-pane-wrapper)::-webkit-scrollbar {
  display: none;
}

.settings-tabs :deep(.n-tabs-content) {
  min-height: 0;
}
</style>
