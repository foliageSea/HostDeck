<script setup lang="ts">
import { computed, ref } from 'vue'
import { KeyRound, ShieldCheck } from '@lucide/vue'
import { NButton, NButtonGroup, NInput } from 'naive-ui'
import { createWallpaperFilter, createWallpaperStyle } from '@/lib/wallpapers'
import { useAccessStore } from '@/stores/access'
import { useSettingsStore } from '@/stores/settings'

const accessStore = useAccessStore()
const settingsStore = useSettingsStore()
const credential = ref('')
const submitting = ref(false)
const errorMessage = ref('')
const loginMode = ref<'password' | 'totp'>('totp')
const useTotp = computed(
  () =>
    accessStore.totpLoginEnabled &&
    (loginMode.value === 'totp' || !accessStore.passwordLoginEnabled),
)
const loginWallpaperStyle = computed(() =>
  createWallpaperStyle('desktop', settingsStore.desktopWallpaper, settingsStore.isDark),
)
const loginWallpaperFilter = computed(() => createWallpaperFilter(settingsStore.desktopWallpaper))
const isDefaultWallpaper = computed(() => settingsStore.desktopWallpaper.mode === 'default')
const isVideoWallpaper = computed(
  () =>
    settingsStore.desktopWallpaper.mode === 'custom' &&
    settingsStore.desktopWallpaper.customType === 'video' &&
    Boolean(settingsStore.desktopWallpaper.customDataUrl),
)
const loginVideoWallpaperUrl = computed(() => {
  const wallpaperUrl = settingsStore.desktopWallpaper.customDataUrl
  if (
    !wallpaperUrl ||
    !wallpaperUrl.startsWith('/') ||
    !import.meta.env.DEV ||
    !import.meta.env.VITE_DEV_PROXY_TARGET
  ) {
    return wallpaperUrl ?? undefined
  }

  try {
    return new URL(wallpaperUrl, import.meta.env.VITE_DEV_PROXY_TARGET).toString()
  } catch {
    return wallpaperUrl
  }
})

function selectLoginMode(mode: 'password' | 'totp') {
  loginMode.value = mode
  credential.value = ''
  errorMessage.value = ''
}

async function submit() {
  if (!credential.value || submitting.value) return

  submitting.value = true
  errorMessage.value = ''
  try {
    if (useTotp.value) {
      await accessStore.login({ code: credential.value })
    } else {
      await accessStore.login({ password: credential.value })
    }
    credential.value = ''
    await settingsStore.initialize()
  } catch {
    errorMessage.value = useTotp.value ? 'Authenticator 验证码不正确' : '访问凭据不正确'
  } finally {
    submitting.value = false
  }
}
</script>

<template>
  <main class="relative min-h-screen overflow-hidden">
    <video
      v-if="isVideoWallpaper"
      class="absolute inset-0 h-full w-full object-cover"
      :src="loginVideoWallpaperUrl"
      :style="{ filter: loginWallpaperFilter }"
      autoplay
      muted
      loop
      playsinline
    />
    <div
      v-else
      class="absolute inset-0 bg-cover bg-center bg-no-repeat"
      :class="{ 'default-wallpaper-motion': isDefaultWallpaper }"
      :style="loginWallpaperStyle"
    />

    <div
      class="relative z-1 grid min-h-screen w-full box-border place-items-center p-[40px] lt-lg:p-[20px]"
    >
      <section
        class="app-radius-card box-border w-full max-w-[520px] rounded-[24px] p-[24px] backdrop-blur-[18px]"
        :class="settingsStore.isDark ? 'glass-panel-dark' : 'glass-panel-light'"
        aria-labelledby="access-title"
      >
        <div class="mb-[22px] flex items-center gap-[12px]">
          <div class="access-brand-icon flex-none" aria-hidden="true">
            <img src="/favicon.png" alt="" />
          </div>
          <div class="min-w-0">
            <h1
              id="access-title"
              class="m-0 truncate text-[1.5rem] font-bold leading-[1.25]"
              :class="settingsStore.isDark ? 'text-[#f8fafc]' : 'text-[#0f172a]'"
            >
              HostDeck
            </h1>
            <p
              class="mb-0 mt-[3px] text-[0.82rem]"
              :class="
                settingsStore.isDark ? 'text-[rgba(203,213,225,0.7)]' : 'text-[rgba(51,65,85,0.76)]'
              "
            >
              管理访问验证
            </p>
          </div>
        </div>

        <form
          v-if="accessStore.passwordLoginEnabled || accessStore.totpLoginEnabled"
          class="flex flex-col gap-[14px]"
          @submit.prevent="submit"
        >
          <NButtonGroup
            v-if="accessStore.passwordLoginEnabled && accessStore.totpLoginEnabled"
            class="w-full"
          >
            <NButton
              class="flex-1"
              :type="loginMode === 'totp' ? 'primary' : 'default'"
              :secondary="loginMode !== 'totp'"
              @click="selectLoginMode('totp')"
            >
              Authenticator
            </NButton>
            <NButton
              class="flex-1"
              :type="loginMode === 'password' ? 'primary' : 'default'"
              :secondary="loginMode !== 'password'"
              @click="selectLoginMode('password')"
            >
              访问密码
            </NButton>
          </NButtonGroup>

          <NInput
            v-model:value="credential"
            :type="useTotp ? 'text' : 'password'"
            size="large"
            :placeholder="useTotp ? 'Authenticator 验证码或恢复码' : '访问密码'"
            :maxlength="useTotp ? 19 : undefined"
            :show-password-on="useTotp ? undefined : 'click'"
            autofocus
          >
            <template #prefix>
              <ShieldCheck v-if="useTotp" :size="17" aria-hidden="true" />
              <KeyRound v-else :size="17" aria-hidden="true" />
            </template>
          </NInput>

          <p v-if="errorMessage" class="access-error" role="alert">{{ errorMessage }}</p>

          <NButton
            type="primary"
            size="large"
            attr-type="submit"
            :loading="submitting"
            :disabled="!credential"
            block
          >
            登录
          </NButton>
        </form>

        <div
          v-else
          class="app-radius-item flex items-center gap-[12px] border px-[14px] py-[13px] text-[0.84rem]"
          :class="
            settingsStore.isDark
              ? 'border-[rgba(148,163,184,0.18)] bg-[rgba(15,23,42,0.34)] text-[rgba(203,213,225,0.8)]'
              : 'border-[rgba(148,163,184,0.28)] bg-[rgba(255,255,255,0.46)] text-[rgba(51,65,85,0.78)]'
          "
        >
          <ShieldCheck :size="18" class="flex-none text-[var(--app-primary-color)]" />
          <span>此实例仅允许 API Token 访问</span>
        </div>
      </section>
    </div>
  </main>
</template>

<style scoped>
.access-brand-icon {
  display: grid;
  width: 46px;
  height: 46px;
  place-items: center;
}

.access-brand-icon img {
  width: 46px;
  height: 46px;
  object-fit: contain;
}

.access-error {
  margin: -4px 0 0;
  color: #ef4444;
  font-size: 0.78rem;
}
</style>
