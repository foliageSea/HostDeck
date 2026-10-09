<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { Copy, RefreshCw, ShieldCheck, ShieldOff } from '@lucide/vue'
import QRCode from 'qrcode'
import { accessApi, type AccessState, type TotpSetup } from '@/api/access'
import { useAccessStore } from '@/stores/access'
import { getUiApi } from '@/lib/ui'

type DialogMode = 'setup' | 'disable' | 'recovery'

const accessStore = useAccessStore()
const state = ref<AccessState>()
const loading = ref(true)
const submitting = ref(false)
const dialogVisible = ref(false)
const dialogMode = ref<DialogMode>('setup')
const setup = ref<TotpSetup>()
const qrCodeUrl = ref('')
const currentCode = ref('')
const confirmationCode = ref('')
const recoveryCodes = ref<string[]>([])

const sourceLabel = computed(() => {
  if (state.value?.totpSource === 'stored') return '应用管理'
  if (state.value?.totpSource === 'environment') return '环境变量'
  return '未配置'
})

const needsCurrentCode = computed(() => state.value?.totpLoginEnabled === true && !setup.value)

async function refresh() {
  loading.value = true
  try {
    state.value = await accessApi.getState()
  } catch (error) {
    getUiApi().message.error(error instanceof Error ? error.message : '获取认证状态失败。')
  } finally {
    loading.value = false
  }
}

function openSetup() {
  resetDialog()
  dialogMode.value = 'setup'
  dialogVisible.value = true
  if (!state.value?.totpLoginEnabled) void beginSetup()
}

function openDisable() {
  resetDialog()
  dialogMode.value = 'disable'
  dialogVisible.value = true
}

async function beginSetup() {
  if (submitting.value) return
  submitting.value = true
  try {
    setup.value = await accessApi.beginTotpSetup(currentCode.value || undefined)
    qrCodeUrl.value = await QRCode.toDataURL(setup.value.provisioningUri, {
      width: 220,
      margin: 1,
      color: { dark: '#101418', light: '#ffffff' },
    })
    currentCode.value = ''
  } catch (error) {
    getUiApi().message.error(error instanceof Error ? error.message : '创建绑定信息失败。')
  } finally {
    submitting.value = false
  }
}

async function confirmSetup() {
  if (!confirmationCode.value || submitting.value) return
  submitting.value = true
  try {
    const result = await accessApi.confirmTotpSetup(confirmationCode.value)
    recoveryCodes.value = result.recoveryCodes
    dialogMode.value = 'recovery'
    setup.value = undefined
    confirmationCode.value = ''
    await Promise.all([refresh(), accessStore.initialize()])
    getUiApi().message.success('Authenticator 已启用。')
  } catch (error) {
    getUiApi().message.error(error instanceof Error ? error.message : '验证码校验失败。')
  } finally {
    submitting.value = false
  }
}

async function disableTotp() {
  if (!currentCode.value || submitting.value) return
  submitting.value = true
  try {
    await accessApi.disableTotp(currentCode.value)
    dialogVisible.value = false
    await Promise.all([refresh(), accessStore.initialize()])
    getUiApi().message.success('Authenticator 已停用。')
  } catch (error) {
    getUiApi().message.error(error instanceof Error ? error.message : '停用 Authenticator 失败。')
  } finally {
    submitting.value = false
  }
}

async function copyText(value: string, successMessage: string) {
  try {
    await navigator.clipboard.writeText(value)
    getUiApi().message.success(successMessage)
  } catch {
    getUiApi().message.error('复制失败。')
  }
}

function resetDialog() {
  setup.value = undefined
  qrCodeUrl.value = ''
  currentCode.value = ''
  confirmationCode.value = ''
  recoveryCodes.value = []
}

onMounted(refresh)
</script>

<template>
  <section>
    <h2 class="m-0 mb-[20px] text-[16px] font-600">Authenticator</h2>
    <NSpin :show="loading">
      <div class="flex flex-col gap-[16px]">
        <div class="flex flex-wrap items-center justify-between gap-[16px]">
          <div class="flex min-w-0 items-center gap-[12px]">
            <div class="security-icon" :class="state?.totpLoginEnabled ? 'is-enabled' : ''">
              <ShieldCheck v-if="state?.totpLoginEnabled" :size="20" />
              <ShieldOff v-else :size="20" />
            </div>
            <div class="min-w-0">
              <div class="text-[14px] font-600">
                {{ state?.totpLoginEnabled ? '已启用' : '未启用' }}
              </div>
              <div class="mt-[3px] text-[12px] text-[rgba(148,163,184,0.96)]">
                {{ sourceLabel }}
                <template v-if="state?.totpLoginEnabled">
                  · 剩余恢复码 {{ state.recoveryCodesRemaining }} 个
                </template>
              </div>
            </div>
          </div>

          <div class="flex flex-wrap gap-[8px]">
            <NButton
              v-if="state?.totpLoginEnabled"
              secondary
              @click="openSetup"
            >
              <template #icon><RefreshCw :size="16" /></template>
              轮换
            </NButton>
            <NButton
              v-if="state?.totpLoginEnabled"
              type="error"
              secondary
              :disabled="state.totpSource === 'environment'"
              @click="openDisable"
            >
              停用
            </NButton>
            <NButton v-else type="primary" @click="openSetup">绑定</NButton>
          </div>
        </div>

        <NAlert
          v-if="state?.totpSource === 'environment'"
          type="info"
          :show-icon="false"
        >
          当前 Secret 由环境变量管理。可轮换为应用管理的 Secret；停用需移除环境变量并重启服务。
        </NAlert>
      </div>
    </NSpin>
  </section>

  <NModal v-model:show="dialogVisible" :mask-closable="!submitting" @after-leave="resetDialog">
    <NCard
      class="totp-dialog"
      :title="dialogMode === 'disable' ? '停用 Authenticator' : dialogMode === 'recovery' ? '保存恢复码' : state?.totpLoginEnabled ? '轮换 Authenticator' : '绑定 Authenticator'"
      closable
      @close="dialogVisible = false"
    >
      <div v-if="dialogMode === 'disable'" class="dialog-content">
        <NInput
          v-model:value="currentCode"
          placeholder="当前验证码或恢复码"
          maxlength="19"
          autofocus
          @keyup.enter="disableTotp"
        />
        <NButton type="error" :loading="submitting" :disabled="!currentCode" @click="disableTotp">
          确认停用
        </NButton>
      </div>

      <div v-else-if="dialogMode === 'recovery'" class="dialog-content">
        <NAlert type="warning" :show-icon="false">
          恢复码仅显示一次。每个恢复码只能使用一次。
        </NAlert>
        <div class="recovery-grid">
          <code v-for="code in recoveryCodes" :key="code">{{ code }}</code>
        </div>
        <div class="flex justify-end gap-[8px]">
          <NButton @click="copyText(recoveryCodes.join('\n'), '恢复码已复制。')">
            <template #icon><Copy :size="16" /></template>
            复制全部
          </NButton>
          <NButton type="primary" @click="dialogVisible = false">完成</NButton>
        </div>
      </div>

      <div v-else-if="needsCurrentCode" class="dialog-content">
        <NInput
          v-model:value="currentCode"
          placeholder="当前验证码或恢复码"
          maxlength="19"
          autofocus
          @keyup.enter="beginSetup"
        />
        <NButton type="primary" :loading="submitting" :disabled="!currentCode" @click="beginSetup">
          继续
        </NButton>
      </div>

      <div v-else-if="setup" class="dialog-content">
        <div class="setup-grid">
          <img class="qr-code" :src="qrCodeUrl" alt="Authenticator 绑定二维码" />
          <div class="min-w-0">
            <div class="text-[13px] font-600">{{ state?.totpIssuer }} · {{ state?.totpAccount }}</div>
            <div class="secret-row">
              <code>{{ setup.secret }}</code>
              <NButton
                quaternary
                circle
                aria-label="复制 Secret"
                @click="copyText(setup.secret, 'Secret 已复制。')"
              >
                <template #icon><Copy :size="16" /></template>
              </NButton>
            </div>
            <NInput
              v-model:value="confirmationCode"
              class="mt-[16px]"
              placeholder="6 位验证码"
              maxlength="6"
              autofocus
              @keyup.enter="confirmSetup"
            />
          </div>
        </div>
        <NButton
          type="primary"
          :loading="submitting"
          :disabled="confirmationCode.length !== 6"
          @click="confirmSetup"
        >
          验证并启用
        </NButton>
      </div>
    </NCard>
  </NModal>
</template>

<style scoped>
.security-icon {
  width: 38px;
  height: 38px;
  display: grid;
  place-items: center;
  flex: none;
  border: 1px solid rgba(148, 163, 184, 0.24);
  border-radius: 8px;
  color: #94a3b8;
  background: rgba(148, 163, 184, 0.08);
}

.security-icon.is-enabled {
  color: #34d399;
  border-color: rgba(52, 211, 153, 0.28);
  background: rgba(52, 211, 153, 0.08);
}

.totp-dialog {
  width: min(92vw, 560px);
}

.dialog-content {
  display: grid;
  gap: 16px;
}

.setup-grid {
  display: grid;
  grid-template-columns: 220px minmax(0, 1fr);
  gap: 20px;
  align-items: center;
}

.qr-code {
  width: 220px;
  height: 220px;
  border-radius: 6px;
  background: #fff;
}

.secret-row {
  display: flex;
  align-items: center;
  gap: 6px;
  margin-top: 8px;
}

.secret-row code {
  min-width: 0;
  overflow-wrap: anywhere;
  font-size: 12px;
}

.recovery-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 8px;
}

.recovery-grid code {
  padding: 8px 10px;
  border: 1px solid rgba(148, 163, 184, 0.18);
  border-radius: 6px;
  text-align: center;
  font-size: 12px;
}

@media (max-width: 640px) {
  .setup-grid {
    grid-template-columns: 1fr;
    justify-items: center;
  }

  .setup-grid > div {
    width: 100%;
  }

  .recovery-grid {
    grid-template-columns: 1fr;
  }
}
</style>
