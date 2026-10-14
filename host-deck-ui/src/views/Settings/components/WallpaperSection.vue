<script setup lang="ts">
import { Renew, Upload } from '@vicons/carbon'
import { computed } from 'vue'
import {
  getDefaultWallpaperBackground,
  wallpaperPresets,
  type WallpaperSettings,
  type WallpaperTarget,
} from '@/lib/wallpapers'
import type { useWallpaperSettings } from '../hooks/useWallpaperSettings'

const props = defineProps<{
  target: WallpaperTarget
  title: string
  controller: ReturnType<typeof useWallpaperSettings>
}>()

const wallpaperSettings = computed(() =>
  props.target === 'desktop'
    ? props.controller.settingsStore.desktopWallpaper
    : props.controller.settingsStore.loginWallpaper,
)
const isDark = computed(() => props.controller.settingsStore.isDark)
const defaultWallpaperPreviewStyle = computed(() => ({
  background: getDefaultWallpaperBackground(isDark.value),
}))
const headingTextClass = computed(() =>
  isDark.value ? 'text-[rgba(241,245,249,0.96)]' : 'text-[rgba(15,23,42,0.92)]',
)
const sliderLabelClass = computed(() =>
  isDark.value ? 'text-[rgba(226,232,240,0.88)]' : 'text-[rgba(51,65,85,0.88)]',
)

function updateWallpaperSettings(nextValue: WallpaperSettings) {
  if (props.target === 'desktop') {
    props.controller.settingsStore.setDesktopWallpaper(nextValue)
    return
  }

  props.controller.settingsStore.setLoginWallpaper(nextValue)
}

function updateWallpaperEffect(effect: 'brightness' | 'contrast', value: number) {
  updateWallpaperSettings({
    ...wallpaperSettings.value,
    [effect]: value,
  })
}

function resetWallpaperEffects() {
  updateWallpaperSettings({
    ...wallpaperSettings.value,
    brightness: 100,
    contrast: 100,
  })
}
</script>

<template>
  <section class="wallpaper-section">
    <div class="mb-[16px] flex items-start justify-between gap-[16px] lt-md:flex-col">
      <div>
        <h3 class="m-0 text-[1rem]">{{ title }}</h3>
      </div>
      <div class="flex shrink-0 flex-nowrap items-center gap-[8px] lt-md:w-full">
        <NTooltip>
          <template #trigger>
            <NButton
              circle
              secondary
              aria-label="上传壁纸"
              @click="controller.openWallpaperPicker(target)"
            >
              <template #icon>
                <NIcon>
                  <Upload />
                </NIcon>
              </template>
            </NButton>
          </template>
          上传
        </NTooltip>
        <NTooltip>
          <template #trigger>
            <NButton
              circle
              tertiary
              aria-label="恢复默认壁纸"
              @click="controller.resetWallpaper(target)"
            >
              <template #icon>
                <NIcon>
                  <Renew />
                </NIcon>
              </template>
            </NButton>
          </template>
          恢复
        </NTooltip>
      </div>
    </div>

    <input
      :ref="
        (el) => {
          if (target === 'desktop') {
            controller.desktopWallpaperInput.value = el as HTMLInputElement | null
          } else {
            controller.loginWallpaperInput.value = el as HTMLInputElement | null
          }
        }
      "
      class="hidden"
      type="file"
      accept="image/*,video/*"
      @change="controller.handleWallpaperUpload(target, $event)"
    />

    <div class="grid grid-cols-[repeat(auto-fill,minmax(150px,1fr))] gap-[12px]">
      <button
        type="button"
        class="wallpaper-card wallpaper-card--clickable app-radius-item"
        :class="{ 'wallpaper-card--active': controller.isDefaultActive(target) }"
        @click="controller.resetWallpaper(target)"
      >
        <div
          class="wallpaper-card__preview default-wallpaper-motion"
          :style="defaultWallpaperPreviewStyle"
        />
        <div class="wallpaper-card__label">
          <strong class="text-[0.88rem] font-500" :class="headingTextClass">默认</strong>
        </div>
      </button>

      <button
        v-for="preset in wallpaperPresets"
        :key="`${target}-${preset.id}`"
        type="button"
        class="wallpaper-card wallpaper-card--clickable app-radius-item"
        :class="{ 'wallpaper-card--active': controller.isPresetActive(target, preset.id) }"
        @click="controller.setPresetWallpaper(target, preset.id)"
      >
        <div class="wallpaper-card__preview" :style="{ background: preset.background }" />
        <div class="wallpaper-card__label">
          <strong class="text-[0.88rem] font-500" :class="headingTextClass">{{
            preset.label
          }}</strong>
        </div>
      </button>

      <div
        class="wallpaper-card app-radius-item"
        :class="{ 'wallpaper-card--active': controller.isCustomActive(target) }"
      >
        <div
          class="wallpaper-card__preview"
          :style="
            wallpaperSettings.customDataUrl && wallpaperSettings.customType !== 'video'
              ? {
                  backgroundColor: isDark ? '#020617' : '#e2e8f0',
                  backgroundImage: `url(${wallpaperSettings.customDataUrl})`,
                  backgroundPosition: 'center',
                  backgroundRepeat: 'no-repeat',
                  backgroundSize: 'contain',
                }
              : undefined
          "
        >
          <video
            v-if="wallpaperSettings.customDataUrl && wallpaperSettings.customType === 'video'"
            class="h-full w-full object-cover"
            :src="wallpaperSettings.customDataUrl"
            autoplay
            muted
            loop
            playsinline
          />
          <span v-if="!wallpaperSettings.customDataUrl" class="wallpaper-card__empty">
            未上传
          </span>
        </div>
        <div class="wallpaper-card__label">
          <strong class="text-[0.88rem] font-500" :class="headingTextClass">自定义媒体</strong>
        </div>
      </div>
    </div>

    <div class="mt-[20px]">
      <div class="mb-[14px] flex items-start justify-between gap-[12px] lt-md:flex-col">
        <div>
          <h4 class="m-0 text-[0.96rem] font-600" :class="headingTextClass">背景效果</h4>
        </div>
        <NTooltip>
          <template #trigger>
            <NButton circle tertiary aria-label="重置背景效果" @click="resetWallpaperEffects">
              <template #icon>
                <NIcon>
                  <Renew />
                </NIcon>
              </template>
            </NButton>
          </template>
          重置效果
        </NTooltip>
      </div>

      <NSpace vertical size="large">
        <div>
          <div
            class="mb-[10px] flex items-center justify-between gap-[12px] text-[0.88rem]"
            :class="sliderLabelClass"
          >
            <span>亮度</span>
            <strong>{{ wallpaperSettings.brightness }}%</strong>
          </div>
          <NSlider
            :value="wallpaperSettings.brightness"
            :min="50"
            :max="150"
            :step="1"
            @update:value="(value: number) => updateWallpaperEffect('brightness', value)"
          />
        </div>

        <div>
          <div
            class="mb-[10px] flex items-center justify-between gap-[12px] text-[0.88rem]"
            :class="sliderLabelClass"
          >
            <span>对比度</span>
            <strong>{{ wallpaperSettings.contrast }}%</strong>
          </div>
          <NSlider
            :value="wallpaperSettings.contrast"
            :min="50"
            :max="150"
            :step="1"
            @update:value="(value: number) => updateWallpaperEffect('contrast', value)"
          />
        </div>
      </NSpace>
    </div>
  </section>
</template>

<style scoped>
.wallpaper-card {
  box-sizing: border-box;
  min-width: 0;
  border: 1px solid rgba(148, 163, 184, 0.16);
  padding: 8px;
  color: inherit;
  background: rgba(148, 163, 184, 0.06);
  text-align: left;
  transition:
    border-color 160ms ease,
    background-color 160ms ease,
    box-shadow 160ms ease;
}

.wallpaper-card--clickable {
  cursor: pointer;
}

.wallpaper-card--clickable:hover {
  border-color: rgba(148, 163, 184, 0.36);
  background: rgba(148, 163, 184, 0.1);
}

.wallpaper-card--active,
.wallpaper-card--active:hover {
  border-color: var(--app-primary-color);
  background: var(--app-primary-soft);
  box-shadow: 0 0 0 3px var(--app-primary-soft);
}

.wallpaper-card__preview {
  position: relative;
  height: 88px;
  overflow: hidden;
  border-radius: calc(var(--app-radius-item) - 4px);
  background-color: rgba(148, 163, 184, 0.12);
  background-position: center;
  background-repeat: no-repeat;
  background-size: cover;
}

.wallpaper-card__empty {
  position: absolute;
  inset: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  color: rgba(148, 163, 184, 0.9);
  font-size: 0.8rem;
}

.wallpaper-card__label {
  margin-top: 8px;
  padding: 0 2px;
}
</style>
