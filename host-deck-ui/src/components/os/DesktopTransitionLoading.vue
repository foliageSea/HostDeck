<script setup lang="ts">
import { computed } from 'vue'
import BrandLogo from '@/components/common/BrandLogo.vue'
import { createWallpaperFilter, createWallpaperStyle } from '@/lib/wallpapers'
import { useSettingsStore } from '@/stores/settings'

defineProps<{
  endpoint: string
  serverName: string
  show: boolean
  cancellable?: boolean
}>()

defineEmits<{ cancel: [] }>()

const settingsStore = useSettingsStore()
const wallpaperStyle = computed(() =>
  createWallpaperStyle('desktop', settingsStore.desktopWallpaper, settingsStore.isDark),
)
const wallpaperFilter = computed(() => createWallpaperFilter(settingsStore.desktopWallpaper))
const videoWallpaperUrl = computed(() => {
  const wallpaper = settingsStore.desktopWallpaper
  return wallpaper.mode === 'custom' && wallpaper.customType === 'video'
    ? wallpaper.customDataUrl || undefined
    : undefined
})

const FLY_DURATION = 640
const FLY_EASING = 'cubic-bezier(0.65, 0, 0.35, 1)'

function handleLeave(el: Element, done: () => void) {
  const root = el as HTMLElement
  const logo = root.querySelector<HTMLElement>('.desktop-loading-logo-image')
  const target = document.querySelector<HTMLElement>('[data-desktop-logo]')
  const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches

  if (!logo || !target || reduceMotion) {
    root.animate({ opacity: [1, 0] }, { duration: 320, easing: 'ease' }).finished.then(done, done)
    return
  }

  const from = logo.getBoundingClientRect()
  const to = target.getBoundingClientRect()
  const dx = to.left + to.width / 2 - (from.left + from.width / 2)
  const dy = to.top + to.height / 2 - (from.top + from.height / 2)
  const scale = to.width / from.width
  const timing = { duration: FLY_DURATION, easing: FLY_EASING, fill: 'forwards' as const }

  const animations = [
    logo.animate(
      [
        { transform: 'translate(0, 0) scale(1)' },
        { transform: `translate(${dx}px, ${dy}px) scale(${scale})` },
      ],
      timing,
    ),
    ...Array.from(
      root.querySelectorAll<HTMLElement>(
        '.desktop-loading-fade, .desktop-loading-ring, .desktop-loading-plate',
      ),
    ).map((item) => item.animate({ opacity: [1, 0] }, { ...timing, duration: FLY_DURATION * 0.5 })),
    root
      .querySelector<HTMLElement>('.desktop-loading-backdrop')!
      .animate({ opacity: [1, 0] }, timing),
  ]

  Promise.all(animations.map((animation) => animation.finished))
    .then(() => logo.animate({ opacity: [1, 0] }, { duration: 120, fill: 'forwards' }).finished)
    .then(done, done)
}
</script>

<template>
  <Transition name="desktop-loading" @leave="handleLeave">
    <div
      v-if="show"
      class="desktop-transition-loading fixed inset-0 z-[9999] grid place-items-center overflow-hidden"
      :class="{ 'desktop-transition-loading-light': !settingsStore.isDark }"
      role="status"
      aria-live="polite"
      aria-busy="true"
    >
      <div class="desktop-loading-backdrop" aria-hidden="true">
        <div class="desktop-loading-wallpaper-blur">
          <video
            v-if="videoWallpaperUrl"
            class="desktop-loading-wallpaper"
            :src="videoWallpaperUrl"
            :style="{ filter: wallpaperFilter }"
            autoplay
            muted
            loop
            playsinline
          />
          <div v-else class="desktop-loading-wallpaper" :style="wallpaperStyle" />
        </div>
      </div>

      <div class="relative z-1 flex max-w-[min(420px,calc(100vw-48px))] flex-col items-center">
        <div class="desktop-loading-mark" aria-hidden="true">
          <div class="desktop-loading-ring desktop-loading-ring-outer" />
          <div class="desktop-loading-ring desktop-loading-ring-inner" />
          <div class="desktop-loading-logo">
            <div class="desktop-loading-plate" />
            <BrandLogo class="desktop-loading-logo-image" :size="52" />
          </div>
        </div>

        <h2
          class="desktop-loading-fade mb-0 mt-[30px] text-center text-[1.2rem] font-700 tracking-[0.02em]"
        >
          HostDeck
        </h2>
        <p
          class="desktop-loading-fade mb-0 mt-[8px] max-w-full truncate text-center text-[0.84rem] opacity-60"
        >
          {{ endpoint || serverName }}
        </p>

        <div
          class="desktop-loading-dots desktop-loading-fade mt-[22px] flex items-center gap-[7px]"
          aria-hidden="true"
        >
          <span />
          <span />
          <span />
        </div>
        <NButton
          v-if="cancellable"
          class="desktop-loading-fade mt-[24px]"
          secondary
          @click="$emit('cancel')"
        >
          取消连接
        </NButton>
      </div>
    </div>
  </Transition>
</template>

<style scoped>
.desktop-transition-loading {
  color: #f8fafc;
}

.desktop-loading-backdrop {
  position: absolute;
  inset: 0;
  overflow: hidden;
  background: #020617;
}

.desktop-loading-backdrop::after {
  position: absolute;
  inset: 0;
  background: rgba(2, 6, 23, 0.36);
  content: '';
}

.desktop-loading-wallpaper-blur {
  position: absolute;
  inset: -48px;
  filter: blur(24px);
}

.desktop-loading-wallpaper {
  position: absolute;
  inset: 0;
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.desktop-transition-loading-light {
  color: #0f172a;
}

.desktop-transition-loading-light .desktop-loading-backdrop {
  background: #e2e8f0;
}

.desktop-transition-loading-light .desktop-loading-backdrop::after {
  background: rgba(241, 245, 249, 0.48);
}

.desktop-loading-mark {
  position: relative;
  display: grid;
  width: 112px;
  height: 112px;
  place-items: center;
}

.desktop-loading-logo {
  position: relative;
  display: grid;
  width: 72px;
  height: 72px;
  place-items: center;
}

.desktop-loading-plate {
  position: absolute;
  inset: 0;
  border: 1px solid rgba(255, 255, 255, 0.18);
  border-radius: 24px;
  background: rgba(15, 23, 42, 0.42);
  box-shadow:
    0 18px 48px rgba(2, 6, 23, 0.28),
    inset 0 1px 0 rgba(255, 255, 255, 0.16);
  backdrop-filter: blur(12px);
}

.desktop-transition-loading-light .desktop-loading-plate {
  border-color: rgba(255, 255, 255, 0.68);
  background: rgba(255, 255, 255, 0.46);
  box-shadow:
    0 18px 48px rgba(71, 85, 105, 0.18),
    inset 0 1px 0 rgba(255, 255, 255, 0.72);
}

.desktop-loading-logo-image {
  position: relative;
  width: 52px;
  height: 52px;
}

.desktop-loading-ring {
  position: absolute;
  border-radius: 50%;
}

.desktop-loading-ring-outer {
  inset: 0;
  border: 2px solid rgba(148, 163, 184, 0.16);
  border-top-color: var(--app-primary-color);
  border-right-color: rgba(var(--app-primary-rgb), 0.58);
  animation: desktop-loading-spin 1.4s linear infinite;
}

.desktop-loading-ring-inner {
  inset: 10px;
  border: 1px solid transparent;
  border-bottom-color: rgba(45, 212, 191, 0.8);
  border-left-color: rgba(45, 212, 191, 0.32);
  animation: desktop-loading-spin 1.8s linear infinite reverse;
}

.desktop-loading-dots span {
  width: 6px;
  height: 6px;
  border-radius: 50%;
  background: currentColor;
  animation: desktop-loading-dot 1.15s ease-in-out infinite;
}

.desktop-loading-dots span:nth-child(2) {
  animation-delay: 0.14s;
}

.desktop-loading-dots span:nth-child(3) {
  animation-delay: 0.28s;
}

.desktop-loading-enter-active {
  transition: opacity 0.32s ease;
}

.desktop-loading-enter-active .desktop-loading-mark,
.desktop-loading-enter-active h2,
.desktop-loading-enter-active p,
.desktop-loading-enter-active .desktop-loading-dots {
  transition:
    opacity 0.42s ease,
    transform 0.48s cubic-bezier(0.16, 1, 0.3, 1);
}

.desktop-loading-enter-from,
.desktop-loading-enter-from .desktop-loading-mark,
.desktop-loading-enter-from h2,
.desktop-loading-enter-from p,
.desktop-loading-enter-from .desktop-loading-dots {
  opacity: 0;
}

.desktop-loading-enter-from .desktop-loading-mark,
.desktop-loading-enter-from h2,
.desktop-loading-enter-from p,
.desktop-loading-enter-from .desktop-loading-dots {
  transform: translateY(12px) scale(0.94);
}

@keyframes desktop-loading-spin {
  to {
    transform: rotate(360deg);
  }
}

@keyframes desktop-loading-dot {
  0%,
  60%,
  100% {
    opacity: 0.28;
    transform: translateY(0);
  }

  30% {
    opacity: 0.9;
    transform: translateY(-5px);
  }
}

@media (prefers-reduced-motion: reduce) {
  .desktop-loading-ring,
  .desktop-loading-dots span {
    animation: none;
  }
}
</style>
