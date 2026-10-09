<script setup lang="ts">
defineProps<{
  endpoint: string
  serverName: string
  show: boolean
}>()
</script>

<template>
  <Transition name="desktop-loading">
    <div
      v-if="show"
      class="desktop-transition-loading fixed inset-0 z-[9999] grid place-items-center overflow-hidden"
      role="status"
      aria-live="polite"
      aria-busy="true"
    >
      <div class="desktop-loading-glow desktop-loading-glow-primary" />
      <div class="desktop-loading-glow desktop-loading-glow-secondary" />

      <div class="relative z-1 flex max-w-[min(420px,calc(100vw-48px))] flex-col items-center">
        <div class="desktop-loading-mark" aria-hidden="true">
          <div class="desktop-loading-ring desktop-loading-ring-outer" />
          <div class="desktop-loading-ring desktop-loading-ring-inner" />
          <div class="desktop-loading-logo">
            <img src="/favicon.png" alt="" />
          </div>
        </div>

        <h2 class="mb-0 mt-[30px] text-center text-[1.2rem] font-700 tracking-[0.02em]">
          正在进入 HostDeck
        </h2>
        <p class="mb-0 mt-[10px] max-w-full truncate text-center text-[0.9rem] opacity-72">
          正在连接 {{ serverName }}
        </p>
        <p class="mb-0 mt-[5px] max-w-full truncate text-center text-[0.76rem] opacity-48">
          {{ endpoint }}
        </p>

        <div class="desktop-loading-dots mt-[24px] flex items-center gap-[7px]" aria-hidden="true">
          <span />
          <span />
          <span />
        </div>
      </div>
    </div>
  </Transition>
</template>

<style scoped>
.desktop-transition-loading {
  color: #f8fafc;
  background:
    linear-gradient(rgba(2, 6, 23, 0.72), rgba(2, 6, 23, 0.82)),
    radial-gradient(circle at 50% 42%, rgba(var(--app-primary-rgb), 0.28), transparent 34%), #020617;
  backdrop-filter: blur(22px) saturate(125%);
}

:global(:root[data-theme='light']) .desktop-transition-loading {
  color: #0f172a;
  background:
    linear-gradient(rgba(241, 245, 249, 0.78), rgba(226, 232, 240, 0.86)),
    radial-gradient(circle at 50% 42%, rgba(var(--app-primary-rgb), 0.2), transparent 34%), #e2e8f0;
}

.desktop-loading-glow {
  position: absolute;
  width: min(520px, 72vw);
  height: min(520px, 72vw);
  border-radius: 50%;
  filter: blur(72px);
  opacity: 0.3;
  pointer-events: none;
}

.desktop-loading-glow-primary {
  top: -24%;
  left: -12%;
  background: rgba(var(--app-primary-rgb), 0.55);
  animation: desktop-loading-glow-drift 5s ease-in-out infinite alternate;
}

.desktop-loading-glow-secondary {
  right: -16%;
  bottom: -28%;
  background: rgba(45, 212, 191, 0.32);
  animation: desktop-loading-glow-drift 5s ease-in-out 0.8s infinite alternate-reverse;
}

.desktop-loading-mark {
  position: relative;
  display: grid;
  width: 112px;
  height: 112px;
  place-items: center;
}

.desktop-loading-logo {
  display: grid;
  width: 72px;
  height: 72px;
  place-items: center;
  border: 1px solid rgba(255, 255, 255, 0.18);
  border-radius: 24px;
  background: rgba(15, 23, 42, 0.42);
  box-shadow:
    0 18px 48px rgba(2, 6, 23, 0.28),
    inset 0 1px 0 rgba(255, 255, 255, 0.16);
  backdrop-filter: blur(12px);
}

:global(:root[data-theme='light']) .desktop-loading-logo {
  border-color: rgba(255, 255, 255, 0.68);
  background: rgba(255, 255, 255, 0.46);
  box-shadow:
    0 18px 48px rgba(71, 85, 105, 0.18),
    inset 0 1px 0 rgba(255, 255, 255, 0.72);
}

.desktop-loading-logo img {
  width: 52px;
  height: 52px;
  object-fit: contain;
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

.desktop-loading-enter-active,
.desktop-loading-leave-active {
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
.desktop-loading-leave-to,
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

@keyframes desktop-loading-glow-drift {
  to {
    transform: translate3d(8%, 6%, 0) scale(1.08);
  }
}

@media (prefers-reduced-motion: reduce) {
  .desktop-loading-glow,
  .desktop-loading-ring,
  .desktop-loading-dots span {
    animation: none;
  }
}
</style>
