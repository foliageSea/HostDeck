<script setup lang="ts">
import { computed, ref } from 'vue'
import { getUiApi } from '@/lib/ui'
import WallpaperSection from './components/WallpaperSection.vue'
import { useWallpaperSettings } from './hooks/useWallpaperSettings'

const controller = useWallpaperSettings()
const { settingsStore } = controller
const clearingBrowserCache = ref(false)
const canClearBrowserCache = computed(() => Boolean(window.sshTool?.app?.clearBrowserCache))

const primaryColorPresets = [
  '#2563eb',
  '#0891b2',
  '#059669',
  '#7c3aed',
  '#db2777',
  '#ea580c',
]

function confirmClearBrowserCache() {
  const dialog = getUiApi().dialog.warning({
    title: '清理浏览器缓存',
    content: '将清理 Electron 内置浏览器缓存，不会删除登录信息、应用设置、壁纸或本地数据。是否继续？',
    positiveText: '清理缓存',
    negativeText: '取消',
    onPositiveClick: async () => {
      dialog.loading = true
      clearingBrowserCache.value = true
      try {
        await window.sshTool?.app?.clearBrowserCache()
        getUiApi().message.success('浏览器缓存已清理。')
      }
      catch (error) {
        getUiApi().message.error(error instanceof Error ? error.message : '清理浏览器缓存失败。')
      }
      finally {
        dialog.loading = false
        clearingBrowserCache.value = false
      }
    },
  })
}
</script>

<template>
  <div class="settings-view scrollbar-none grid h-full gap-[20px] overflow-y-auto p-[20px] lt-md:p-[16px]">
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
            <NColorPicker
              class="w-[180px]"
              :value="settingsStore.primaryColor"
              :show-alpha="false"
              :modes="['hex']"
              @update:value="settingsStore.setPrimaryColor"
            />
            <div class="flex items-center gap-[8px]">
              <button
                v-for="color in primaryColorPresets"
                :key="color"
                type="button"
                class="h-[28px] w-[28px] rounded-full border border-[rgba(148,163,184,0.28)] p-0 transition-[transform,box-shadow] duration-[160ms] ease-in-out hover:scale-[1.08] cursor-pointer"
                :class="settingsStore.primaryColor === color ? 'shadow-[0_0_0_3px_var(--app-primary-soft)]' : ''"
                :style="{ backgroundColor: color }"
                :aria-label="`设置主题色 ${color}`"
                @click="settingsStore.setPrimaryColor(color)"
              />
            </div>
            <NButton secondary @click="settingsStore.resetPrimaryColor">恢复默认</NButton>
          </div>
        </NFormItem>
      </NForm>
    </NCard>

    <NCard title="壁纸设置" size="large">
      <NSpace vertical :size="24">
        <WallpaperSection
          target="desktop"
          title="桌面壁纸"
          default-label="跟随当前主题"
          preset-label="桌面预设"
          :controller="controller"
        />
      </NSpace>
    </NCard>

    <NCard v-if="canClearBrowserCache" title="应用维护" size="large">
      <div class="flex flex-col gap-[12px]">
        <div>
          <div class="text-[14px] font-600">浏览器缓存</div>
          <div class="mt-[4px] text-[12px] text-[rgba(148,163,184,0.96)]">
            清理 Electron 内置浏览器缓存，不影响登录信息、应用设置、壁纸和本地数据。
          </div>
        </div>
        <div>
          <NButton type="warning" secondary :loading="clearingBrowserCache" @click="confirmClearBrowserCache">
            清理浏览器缓存
          </NButton>
        </div>
      </div>
    </NCard>
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

</style>
