<script setup lang="ts">
import { computed } from 'vue'
import { wallpaperPresets, type WallpaperSettings, type WallpaperTarget } from '@/lib/wallpapers'
import type { useWallpaperSettings } from '../hooks/useWallpaperSettings'

const props = defineProps<{
  target: WallpaperTarget
  title: string
  defaultLabel: string
  presetLabel: string
  controller: ReturnType<typeof useWallpaperSettings>
}>()

const wallpaperSettings = computed(() =>
  props.target === 'desktop' ? props.controller.settingsStore.desktopWallpaper : props.controller.settingsStore.loginWallpaper,
)
const isDark = computed(() => props.controller.settingsStore.isDark)
const wallpaperOptionCardClass = computed(() =>
  isDark.value
    ? 'border-[rgba(148,163,184,0.14)] bg-[linear-gradient(180deg,rgba(30,41,59,0.76),rgba(15,23,42,0.72))] text-[rgba(226,232,240,0.92)] shadow-[0_12px_28px_rgba(2,6,23,0.26)] hover:border-[rgba(96,165,250,0.24)] hover:shadow-[0_16px_32px_rgba(15,23,42,0.3)]'
    : 'border-[rgba(148,163,184,0.18)] bg-[linear-gradient(180deg,rgba(255,255,255,0.92),rgba(248,250,252,0.84))] text-[rgba(30,41,59,0.9)] shadow-[0_10px_24px_rgba(15,23,42,0.05)] hover:border-[rgba(96,165,250,0.24)] hover:shadow-[0_16px_30px_rgba(148,163,184,0.16)]',
)
const wallpaperOptionCardActiveClass = computed(() =>
  isDark.value
    ? 'border-[rgba(96,165,250,0.44)] shadow-[0_0_0_1px_rgba(96,165,250,0.26),0_18px_36px_rgba(30,64,175,0.18)]'
    : 'border-[rgba(59,130,246,0.42)] shadow-[0_0_0_1px_rgba(96,165,250,0.22),0_18px_34px_rgba(59,130,246,0.12)]'
)
const wallpaperPreviewClass = computed(() =>
  isDark.value
    ? 'bg-[rgba(51,65,85,0.34)] shadow-[inset_0_1px_0_rgba(255,255,255,0.05)]'
    : 'bg-[rgba(148,163,184,0.14)] shadow-[inset_0_1px_0_rgba(255,255,255,0.55)]',
)
const headingTextClass = computed(() =>
  isDark.value ? 'text-[rgba(241,245,249,0.96)]' : 'text-[rgba(15,23,42,0.92)]',
)
const secondaryTextClass = computed(() =>
  isDark.value ? 'text-[rgba(148,163,184,0.94)]' : 'text-[rgba(100,116,139,0.92)]',
)
const effectPanelClass = computed(() =>
  isDark.value
    ? 'border-[rgba(148,163,184,0.14)] bg-[linear-gradient(180deg,rgba(30,41,59,0.8),rgba(15,23,42,0.72))] shadow-[0_14px_32px_rgba(2,6,23,0.24)]'
    : 'border-[rgba(148,163,184,0.16)] bg-[linear-gradient(180deg,rgba(255,255,255,0.82),rgba(241,245,249,0.9))] shadow-[0_12px_28px_rgba(148,163,184,0.12)]',
)
const sliderLabelClass = computed(() =>
  isDark.value ? 'text-[rgba(226,232,240,0.88)]' : 'text-[rgba(51,65,85,0.88)]',
)
const customEmptyMaskClass = computed(() =>
  isDark.value
    ? 'bg-[rgba(15,23,42,0.52)] text-[rgba(148,163,184,0.94)]'
    : 'bg-[rgba(255,255,255,0.46)] text-[rgba(71,85,105,0.9)]',
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
        class="cursor-pointer rounded-[16px] border p-[10px] text-left text-inherit backdrop-blur-[18px] transition-[border-color,transform,box-shadow] duration-[180ms] ease-in-out hover:translate-y-[-1px]"
        :class="[wallpaperOptionCardClass, controller.isDefaultActive(target) ? wallpaperOptionCardActiveClass : '']"
        @click="controller.resetWallpaper(target)"
      >
        <div class="wallpaper-preview-default relative h-[92px] overflow-hidden rounded-[12px] bg-cover bg-center bg-no-repeat" :class="[wallpaperPreviewClass, target === 'desktop' ? 'desktop-default-preview' : 'login-default-preview']" />
        <div class="mt-[10px] grid gap-[4px]">
          <strong class="text-[0.94rem]" :class="headingTextClass">默认</strong>
          <span class="text-[0.84rem]" :class="secondaryTextClass">{{ defaultLabel }}</span>
        </div>
      </button>

      <button
        v-for="preset in wallpaperPresets"
        :key="`${target}-${preset.id}`"
        type="button"
        class="cursor-pointer rounded-[16px] border p-[10px] text-left text-inherit backdrop-blur-[18px] transition-[border-color,transform,box-shadow] duration-[180ms] ease-in-out hover:translate-y-[-1px]"
        :class="[wallpaperOptionCardClass, controller.isPresetActive(target, preset.id) ? wallpaperOptionCardActiveClass : '']"
        @click="controller.setPresetWallpaper(target, preset.id)"
      >
        <div class="relative h-[92px] overflow-hidden rounded-[12px] bg-cover bg-center bg-no-repeat" :class="wallpaperPreviewClass" :style="{ background: preset.background }" />
        <div class="mt-[10px] grid gap-[4px]">
          <strong class="text-[0.94rem]" :class="headingTextClass">{{ preset.label }}</strong>
          <span class="text-[0.84rem]" :class="secondaryTextClass">{{ presetLabel }}</span>
        </div>
      </button>

      <div
        class="cursor-default rounded-[16px] border p-[10px] text-left text-inherit backdrop-blur-[18px] transition-[border-color,transform,box-shadow] duration-[180ms] ease-in-out"
        :class="[wallpaperOptionCardClass, controller.isCustomActive(target) ? wallpaperOptionCardActiveClass : '']"
      >
        <div
          class="relative h-[92px] overflow-hidden rounded-[12px] bg-cover bg-center bg-no-repeat"
          :class="wallpaperPreviewClass"
          :style="wallpaperSettings.customDataUrl
            ? { backgroundImage: `url(${wallpaperSettings.customDataUrl})`, backgroundPosition: 'center', backgroundSize: 'cover' }
            : undefined"
        >
          <span v-if="!wallpaperSettings.customDataUrl" class="absolute inset-0 flex items-center justify-center text-[0.84rem]" :class="customEmptyMaskClass">未上传</span>
        </div>
        <div class="mt-[10px] grid gap-[4px]">
          <strong class="text-[0.94rem]" :class="headingTextClass">自定义图片</strong>
          <span class="text-[0.84rem]" :class="secondaryTextClass">最大 10MB</span>
        </div>
      </div>
    </div>

    <div class="mt-[20px] rounded-[18px] border p-[16px] backdrop-blur-[20px] lt-md:p-[14px]" :class="effectPanelClass">
      <div class="mb-[14px] flex items-start justify-between gap-[12px] lt-md:flex-col">
        <div>
          <h4 class="m-0 text-[0.96rem] font-600" :class="headingTextClass">背景效果</h4>
        </div>
        <NButton tertiary @click="resetWallpaperEffects">重置效果</NButton>
      </div>

      <NSpace vertical size="large">
        <div>
          <div class="mb-[10px] flex items-center justify-between gap-[12px] text-[0.88rem]" :class="sliderLabelClass">
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
          <div class="mb-[10px] flex items-center justify-between gap-[12px] text-[0.88rem]" :class="sliderLabelClass">
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
