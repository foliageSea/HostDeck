<script setup lang="ts">
import { ref } from 'vue'
import { LockKeyhole } from '@lucide/vue'
import { NButton, NInput, NSpin } from 'naive-ui'
import { useAccessStore } from '@/stores/access'
import { useSettingsStore } from '@/stores/settings'

const accessStore = useAccessStore()
const settingsStore = useSettingsStore()
const password = ref('')
const submitting = ref(false)
const errorMessage = ref('')

async function submit() {
  if (!password.value || submitting.value) return

  submitting.value = true
  errorMessage.value = ''
  try {
    await accessStore.login(password.value)
    password.value = ''
    await settingsStore.initialize()
  } catch {
    errorMessage.value = '访问密码不正确'
  } finally {
    submitting.value = false
  }
}
</script>

<template>
  <main class="access-screen">
    <section class="access-panel" aria-labelledby="access-title">
      <div class="access-brand">
        <div class="access-mark"><LockKeyhole :size="24" /></div>
        <div>
          <h1 id="access-title">HostDeck</h1>
          <p>管理访问验证</p>
        </div>
      </div>

      <form v-if="accessStore.passwordLoginEnabled" class="access-form" @submit.prevent="submit">
        <NInput
          v-model:value="password"
          type="password"
          size="large"
          placeholder="访问密码"
          show-password-on="click"
          autofocus
        />
        <p v-if="errorMessage" class="access-error" role="alert">{{ errorMessage }}</p>
        <NButton type="primary" size="large" attr-type="submit" :loading="submitting" block>
          解锁
        </NButton>
      </form>

      <div v-else class="access-token-only">
        <NSpin size="small" />
        <span>此实例仅允许 API Token 访问</span>
      </div>
    </section>
  </main>
</template>

<style scoped>
.access-screen {
  min-height: 100vh;
  display: grid;
  place-items: center;
  padding: 24px;
  background: #101418;
  color: #f3f4f6;
}

.access-panel {
  width: min(100%, 360px);
  padding: 28px;
  border: 1px solid #303840;
  border-radius: 8px;
  background: #181d22;
  box-shadow: 0 18px 60px rgb(0 0 0 / 30%);
}

.access-brand {
  display: flex;
  align-items: center;
  gap: 14px;
  margin-bottom: 28px;
}

.access-mark {
  width: 46px;
  height: 46px;
  display: grid;
  place-items: center;
  border: 1px solid #3b879a;
  border-radius: 8px;
  color: #67d3e8;
  background: #132a30;
}

h1 {
  margin: 0;
  font-size: 21px;
  line-height: 1.2;
  letter-spacing: 0;
}

.access-brand p,
.access-token-only {
  margin: 4px 0 0;
  color: #9ca3af;
  font-size: 13px;
}

.access-form {
  display: grid;
  gap: 14px;
}

.access-error {
  margin: -4px 0 0;
  color: #fb7185;
  font-size: 12px;
}

.access-token-only {
  display: flex;
  align-items: center;
  gap: 10px;
}
</style>
