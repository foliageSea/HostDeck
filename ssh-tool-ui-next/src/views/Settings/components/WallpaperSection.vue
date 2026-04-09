<script setup lang="ts">
import { computed } from 'vue'
import { wallpaperPresets, type WallpaperTarget } from '@/lib/wallpapers'
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
</script>

<template>
  <section class="wallpaper-section">
    <div class="wallpaper-header">
      <div>
        <h3>{{ title }}</h3>
        <p>{{ description }}</p>
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
      class="wallpaper-file-input"
      type="file"
      accept="image/*"
      @change="controller.handleWallpaperUpload(target, $event)"
    >

    <div class="wallpaper-grid">
      <button
        type="button"
        class="wallpaper-option"
        :class="{ 'wallpaper-option-active': controller.isDefaultActive(target) }"
        @click="controller.resetWallpaper(target)"
      >
        <div class="wallpaper-preview wallpaper-preview-default" :class="target === 'desktop' ? 'desktop-default-preview' : 'login-default-preview'" />
        <div class="wallpaper-option-meta">
          <strong>默认</strong>
          <span>{{ defaultLabel }}</span>
        </div>
      </button>

      <button
        v-for="preset in wallpaperPresets"
        :key="`${target}-${preset.id}`"
        type="button"
        class="wallpaper-option"
        :class="{ 'wallpaper-option-active': controller.isPresetActive(target, preset.id) }"
        @click="controller.setPresetWallpaper(target, preset.id)"
      >
        <div class="wallpaper-preview" :style="{ background: preset.background }" />
        <div class="wallpaper-option-meta">
          <strong>{{ preset.label }}</strong>
          <span>{{ presetLabel }}</span>
        </div>
      </button>

      <div class="wallpaper-option wallpaper-option-static" :class="{ 'wallpaper-option-active': controller.isCustomActive(target) }">
        <div
          class="wallpaper-preview"
          :style="wallpaperSettings.customDataUrl
            ? { backgroundImage: `url(${wallpaperSettings.customDataUrl})`, backgroundPosition: 'center', backgroundSize: 'cover' }
            : undefined"
        >
          <span v-if="!wallpaperSettings.customDataUrl" class="wallpaper-empty">未上传</span>
        </div>
        <div class="wallpaper-option-meta">
          <strong>自定义图片</strong>
          <span>最大 10MB</span>
        </div>
      </div>
    </div>
  </section>
</template>

<style scoped>
.wallpaper-header {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 16px;
  margin-bottom: 16px;
}

.wallpaper-header h3 {
  margin: 0;
  font-size: 1rem;
}

.wallpaper-header p {
  margin: 6px 0 0;
  color: rgba(100, 116, 139, 0.92);
  font-size: 0.9rem;
}

.wallpaper-file-input {
  display: none;
}

.wallpaper-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
  gap: 14px;
}

.wallpaper-option {
  padding: 10px;
  border: 1px solid rgba(148, 163, 184, 0.22);
  border-radius: 16px;
  background: rgba(255, 255, 255, 0.72);
  color: inherit;
  text-align: left;
  cursor: pointer;
  transition: border-color 0.18s ease, transform 0.18s ease, box-shadow 0.18s ease;
}

.wallpaper-option:hover {
  transform: translateY(-1px);
}

.wallpaper-option-active {
  border-color: rgba(59, 130, 246, 0.56);
  box-shadow: 0 0 0 1px rgba(96, 165, 250, 0.22);
}

.wallpaper-option-static {
  cursor: default;
}

.wallpaper-preview {
  position: relative;
  height: 92px;
  border-radius: 12px;
  background-color: rgba(148, 163, 184, 0.14);
  background-repeat: no-repeat;
  background-position: center;
  background-size: cover;
  overflow: hidden;
}

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

.wallpaper-option-meta {
  display: grid;
  gap: 4px;
  margin-top: 10px;
}

.wallpaper-option-meta strong {
  font-size: 0.94rem;
}

.wallpaper-option-meta span {
  color: rgba(100, 116, 139, 0.92);
  font-size: 0.84rem;
}

.wallpaper-empty {
  position: absolute;
  inset: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  color: rgba(71, 85, 105, 0.9);
  font-size: 0.84rem;
  background: rgba(255, 255, 255, 0.46);
}

@media (max-width: 768px) {
  .wallpaper-header {
    flex-direction: column;
  }
}
</style>
