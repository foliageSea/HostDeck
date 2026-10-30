<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { settingsApi, type TlsConfig, type TlsState } from '@/api/settings'
import { downloadBlob } from '@/lib/download'
import { getUiApi } from '@/lib/ui'

const state = ref<TlsState>()
const loading = ref(true)
const submitting = ref(false)
const enabled = ref(false)
const source = ref<TlsConfig['source']>('selfSigned')
const hosts = ref('')
const certificateFile = ref<File>()
const privateKeyFile = ref<File>()
const fileInputKey = ref(0)

function applyState(value: TlsState) {
  state.value = value
  enabled.value = value.saved.enabled
  source.value = value.saved.source
  hosts.value = value.saved.hosts.join('\n')
  certificateFile.value = undefined
  privateKeyFile.value = undefined
  fileInputKey.value++
}

async function refresh() {
  loading.value = true
  try {
    applyState(await settingsApi.getTlsSettings())
  } catch (error) {
    getUiApi().message.error(error instanceof Error ? error.message : '获取 TLS 配置失败。')
  } finally {
    loading.value = false
  }
}

function selectFile(event: Event, kind: 'certificate' | 'key') {
  const file = (event.target as HTMLInputElement).files?.[0]
  const limit = kind === 'certificate' ? 262144 : 65536
  if (file && file.size > limit) {
    getUiApi().message.error('文件过大，请选择 PEM 格式的证书或私钥。')
    ;(event.target as HTMLInputElement).value = ''
    return
  }
  if (kind === 'certificate') certificateFile.value = file
  else privateKeyFile.value = file
}

async function save(regenerate = false) {
  if (submitting.value) return
  if (
    source.value === 'imported' &&
    Boolean(certificateFile.value) !== Boolean(privateKeyFile.value)
  ) {
    getUiApi().message.error('请同时选择证书链和私钥。')
    return
  }
  submitting.value = true
  try {
    const value = await settingsApi.saveTlsSettings({
      enabled: enabled.value,
      source: source.value,
      hosts: hosts.value.split(/[\s,，]+/).filter(Boolean),
      regenerate,
      certificatePem: source.value === 'imported' ? await certificateFile.value?.text() : undefined,
      privateKeyPem: source.value === 'imported' ? await privateKeyFile.value?.text() : undefined,
    })
    applyState(value)
    getUiApi().message.success(
      value.restartRequired ? 'TLS 配置已保存，重启服务后生效。' : 'TLS 配置已保存。',
    )
  } catch (error) {
    getUiApi().message.error(error instanceof Error ? error.message : '保存 TLS 配置失败。')
  } finally {
    submitting.value = false
  }
}

function regenerate() {
  const dialog = getUiApi().dialog.warning({
    title: '重新生成自签名证书',
    content: '新证书在重启服务后生效，外部浏览器需要重新信任证书。',
    positiveText: '生成并保存',
    negativeText: '取消',
    onPositiveClick: async () => {
      dialog.loading = true
      try {
        await save(true)
      } finally {
        dialog.loading = false
      }
    },
  })
}

async function downloadCertificate() {
  try {
    downloadBlob(await settingsApi.downloadTlsCertificate(), 'hostdeck-cert.pem')
  } catch (error) {
    getUiApi().message.error(error instanceof Error ? error.message : '下载证书失败。')
  }
}

onMounted(refresh)
</script>

<template>
  <section class="mb-[28px]">
    <div class="mb-[20px] flex flex-wrap items-center justify-between gap-[12px]">
      <h2 class="m-0 text-[16px] font-600">TLS 访问</h2>
      <NSpace v-if="state" :size="8">
        <NTag :type="state.active.enabled ? 'success' : 'default'" size="small" :bordered="false">
          {{ state.active.enabled ? '当前 HTTPS' : '当前 HTTP' }}
        </NTag>
        <NTag v-if="state.restartRequired" type="warning" size="small" :bordered="false">
          待重启生效
        </NTag>
        <NTag v-if="state.managedExternally" type="info" size="small" :bordered="false">
          启动参数覆盖中
        </NTag>
      </NSpace>
    </div>
    <NSpin :show="loading">
      <NForm v-if="state" label-placement="top" :disabled="submitting">
        <NFormItem label="启用 TLS（重启服务后生效）">
          <NSwitch v-model:value="enabled" :disabled="submitting" />
        </NFormItem>
        <NFormItem label="证书来源">
          <NRadioGroup v-model:value="source">
            <NSpace>
              <NRadio value="selfSigned">自动生成自签名证书</NRadio>
              <NRadio value="imported">导入 PEM 证书</NRadio>
            </NSpace>
          </NRadioGroup>
        </NFormItem>
        <NFormItem v-if="source === 'selfSigned'" label="访问域名 / IP">
          <NInput
            v-model:value="hosts"
            type="textarea"
            :autosize="{ minRows: 3, maxRows: 6 }"
            placeholder="localhost&#10;127.0.0.1&#10;::1"
          />
        </NFormItem>
        <template v-else>
          <NFormItem label="证书链（PEM，服务端证书在首位）">
            <input
              :key="`cert-${fileInputKey}`"
              type="file"
              accept=".pem,.crt,.cer"
              :disabled="submitting"
              @change="selectFile($event, 'certificate')"
            />
          </NFormItem>
          <NFormItem label="未加密私钥（PEM）">
            <input
              :key="`key-${fileInputKey}`"
              type="file"
              accept=".pem,.key"
              :disabled="submitting"
              @change="selectFile($event, 'key')"
            />
          </NFormItem>
        </template>
        <div
          v-if="state.saved.certificate && state.saved.source === source"
          class="mb-[20px] flex flex-col gap-[8px] text-[12px]"
        >
          <div>已保存证书：{{ state.saved.certificate.subject }}</div>
          <div class="break-all">适用地址：{{ state.saved.certificate.hosts.join('、') }}</div>
          <div>有效期至：{{ new Date(state.saved.certificate.notAfter).toLocaleString() }}</div>
          <div class="break-all">SHA-256：{{ state.saved.certificate.fingerprint256 }}</div>
        </div>
        <NSpace>
          <NButton type="primary" :loading="submitting" @click="save()">保存</NButton>
          <NButton
            v-if="source === 'selfSigned' && state.saved.certificate"
            :disabled="submitting"
            @click="regenerate"
          >
            重新生成证书
          </NButton>
          <NButton
            v-if="state.saved.certificate"
            :disabled="submitting"
            @click="downloadCertificate"
          >
            下载证书
          </NButton>
        </NSpace>
      </NForm>
      <NButton v-else :disabled="loading" @click="refresh">重新加载</NButton>
    </NSpin>
  </section>
</template>
