<script setup lang="ts">
import { computed } from 'vue'
import { wallpaperPresets, type WallpaperSettings, type WallpaperTarget } from '@/lib/wallpapers'
import type { useWallpaperSettings } from '../hooks/useWallpaperSettings'

const props = defineProps<{
  target: WallpaperTarget
  title: string
  description: string
  defaultLabel: string
  presetLabel: string
  controller: ReturnType<typeof useWallpaperSettings>
}>()

const wallpaperSettings = computed(() =>
  props.target === 'desktop' ? props.controller.settingsStore.desktopWallpaper : props.controller.settingsStore.loginWallpaper,
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
        <p class="mb-0 mt-[6px] text-[0.9rem] text-[rgba(100,116,139,0.92)]">{{ description }}</p>
      </div>
      <NSpace>
        <NButton secondary @click="controller.openWallpaperPicker(target)">上传图片</NButton>
        <NButton tertiary @click="controller.resetWallpaper(target)">恢复默认</NButton>
      </NSpace>
    </div>

    <input
      :ref="(el) => {
        if (target === 'desktop') {
          controller.desktopWallpaperInput.value = el as HTMLInputElement | null
        } else {
          controller.loginWallpaperInput.value = el as HTMLInputElement | null
        }
      }"
      class="hidden"
      type="file"
      accept="image/*"
      @change="controller.handleWallpaperUpload(target, $event)"
    >

    <div class="grid grid-cols-[repeat(auto-fit,minmax(150px,1fr))] gap-[14px]">
      <button
        type="button"
        class="border border-[rgba(148,163,184,0.22)] rounded-[16px] bg-[rgba(255,255,255,0.72)] p-[10px] text-left text-inherit transition-[border-color,transform,box-shadow] duration-[180ms] ease-in-out hover:translate-y-[-1px] cursor-pointer"
        :class="{ 'border-[rgba(59,130,246,0.56)] shadow-[0_0_0_1px_rgba(96,165,250,0.22)]': controller.isDefaultActive(target) }"
        @click="controller.resetWallpaper(target)"
      >
        <div class="wallpaper-preview-default relative h-[92px] overflow-hidden rounded-[12px] bg-[rgba(148,163,184,0.14)] bg-cover bg-center bg-no-repeat" :class="target === 'desktop' ? 'desktop-default-preview' : 'login-default-preview'" />
        <div class="mt-[10px] grid gap-[4px]">
          <strong class="text-[0.94rem]">默认</strong>
          <span class="text-[0.84rem] text-[rgba(100,116,139,0.92)]">{{ defaultLabel }}</span>
        </div>
      </button>

      <button
        v-for="preset in wallpaperPresets"
        :key="`${target}-${preset.id}`"
        type="button"
        class="border border-[rgba(148,163,184,0.22)] rounded-[16px] bg-[rgba(255,255,255,0.72)] p-[10px] text-left text-inherit transition-[border-color,transform,box-shadow] duration-[180ms] ease-in-out hover:translate-y-[-1px] cursor-pointer"
        :class="{ 'border-[rgba(59,130,246,0.56)] shadow-[0_0_0_1px_rgba(96,165,250,0.22)]': controller.isPresetActive(target, preset.id) }"
        @click="controller.setPresetWallpaper(target, preset.id)"
      >
        <div class="relative h-[92px] overflow-hidden rounded-[12px] bg-[rgba(148,163,184,0.14)] bg-cover bg-center bg-no-repeat" :style="{ background: preset.background }" />
        <div class="mt-[10px] grid gap-[4px]">
          <strong class="text-[0.94rem]">{{ preset.label }}</strong>
          <span class="text-[0.84rem] text-[rgba(100,116,139,0.92)]">{{ presetLabel }}</span>
        </div>
      </button>

      <div
        class="border border-[rgba(148,163,184,0.22)] rounded-[16px] bg-[rgba(255,255,255,0.72)] p-[10px] text-left text-inherit transition-[border-color,transform,box-shadow] duration-[180ms] ease-in-out cursor-default"
        :class="{ 'border-[rgba(59,130,246,0.56)] shadow-[0_0_0_1px_rgba(96,165,250,0.22)]': controller.isCustomActive(target) }"
      >
        <div
          class="relative h-[92px] overflow-hidden rounded-[12px] bg-[rgba(148,163,184,0.14)] bg-cover bg-center bg-no-repeat"
          :style="wallpaperSettings.customDataUrl
            ? { backgroundImage: `url(${wallpaperSettings.customDataUrl})`, backgroundPosition: 'center', backgroundSize: 'cover' }
            : undefined"
        >
          <span v-if="!wallpaperSettings.customDataUrl" class="absolute inset-0 flex items-center justify-center bg-[rgba(255,255,255,0.46)] text-[0.84rem] text-[rgba(71,85,105,0.9)]">未上传</span>
        </div>
        <div class="mt-[10px] grid gap-[4px]">
          <strong class="text-[0.94rem]">自定义图片</strong>
          <span class="text-[0.84rem] text-[rgba(100,116,139,0.92)]">最大 10MB</span>
        </div>
      </div>
    </div>

    <div class="mt-[20px] rounded-[18px] border border-[rgba(148,163,184,0.18)] bg-[rgba(248,250,252,0.78)] p-[16px] lt-md:p-[14px]">
      <div class="mb-[14px] flex items-start justify-between gap-[12px] lt-md:flex-col">
        <div>
          <h4 class="m-0 text-[0.96rem] font-600 text-[rgba(15,23,42,0.92)]">背景效果</h4>
          <p class="mb-0 mt-[6px] text-[0.84rem] text-[rgba(100,116,139,0.92)]">亮度和对比度会立即应用到桌面与登录背景，并在下次进入时保持。</p>
        </div>
        <NButton tertiary @click="resetWallpaperEffects">重置效果</NButton>
      </div>

      <NSpace vertical size="large">
        <div>
          <div class="mb-[10px] flex items-center justify-between gap-[12px] text-[0.88rem] text-[rgba(51,65,85,0.88)]">
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
          <div class="mb-[10px] flex items-center justify-between gap-[12px] text-[0.88rem] text-[rgba(51,65,85,0.88)]">
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
.wallpaper-preview-default.desktop-default-preview {
  background:
    radial-gradient(circle at 15% 18%, rgba(59, 130, 246, 0.16), transparent 24%),
    radial-gradient(circle at 85% 15%, rgba(217, 70, 239, 0.14), transparent 18%),
    linear-gradient(160deg, #dbeafe 0%, #e2e8f0 50%, #cbd5e1 100%);
}

.wallpaper-preview-default.login-default-preview {
  background:
    radial-gradient(circle at 20% 20%, rgba(56, 189, 248, 0.2), transparent 24%),
    radial-gradient(circle at 80% 16%, rgba(168, 85, 247, 0.18), transparent 22%),
    linear-gradient(135deg, rgba(15, 23, 42, 0.78), rgba(2, 6, 23, 0.92));
}
</style>
