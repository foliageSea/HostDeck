<script setup lang="ts">
import { onMounted, reactive, ref, watch } from 'vue'
import { Database, FilePenLine, Gauge, Globe2, Plus, Save, Trash2 } from '@lucide/vue'
import { dockerApi, type DockerProxyConfiguration, type DockerRegistrySetting } from '@/api/docker'
import { getUiApi } from '@/lib/ui'
import { useDesktopStore } from '@/stores/desktop'

const props = defineProps<{ connectionId: string; windowId?: string }>()
const desktopStore = useDesktopStore()

const loading = ref(false)
const savingMirrors = ref(false)
const savingProxy = ref(false)
const savingRegistries = ref(false)
const mirrorsText = ref('')
const proxy = reactive<DockerProxyConfiguration>({
  enabled: false,
  httpProxy: '',
  httpsProxy: '',
  noProxy: '',
})
const registries = ref<DockerRegistrySetting[]>([])

function emptyRegistry(): DockerRegistrySetting {
  return {
    address: '',
    name: '',
    namespace: '',
    authentication: false,
    username: '',
    password: '',
  }
}

function openDaemonConfig() {
  desktopStore.openWindow(
    'editor',
    {
      connectionId: props.connectionId,
      path: '/etc/docker/daemon.json',
      title: 'daemon.json',
    },
    { parentId: props.windowId },
  )
}

function applyConfiguration(configuration: Awaited<ReturnType<typeof dockerApi.getConfiguration>>) {
  mirrorsText.value = configuration.mirrors.join('\n')
  Object.assign(proxy, configuration.proxy)
  registries.value = configuration.registries.map((registry) => ({ ...registry, password: '' }))
}

async function loadConfiguration() {
  loading.value = true
  try {
    applyConfiguration(await dockerApi.getConfiguration(props.connectionId))
  } catch (error) {
    console.error('Failed to load Docker configuration', error)
    getUiApi().message.error(error instanceof Error ? error.message : 'Docker 配置加载失败。')
  } finally {
    loading.value = false
  }
}

async function saveMirrors() {
  savingMirrors.value = true
  try {
    const mirrors = mirrorsText.value
      .split('\n')
      .map((value) => value.trim())
      .filter(Boolean)
    const configuration = await dockerApi.updateDaemonConfiguration(props.connectionId, { mirrors })
    mirrorsText.value = configuration.mirrors.join('\n')
    getUiApi().message.success('镜像加速配置已保存并重启 Docker。')
  } catch (error) {
    console.error('Failed to save Docker mirrors', error)
    getUiApi().message.error(error instanceof Error ? error.message : '镜像加速配置保存失败。')
  } finally {
    savingMirrors.value = false
  }
}

async function saveProxy() {
  savingProxy.value = true
  try {
    const configuration = await dockerApi.updateDaemonConfiguration(props.connectionId, {
      proxy: { ...proxy },
    })
    Object.assign(proxy, configuration.proxy)
    getUiApi().message.success('Docker 代理配置已保存并重启 Docker。')
  } catch (error) {
    console.error('Failed to save Docker proxy', error)
    getUiApi().message.error(error instanceof Error ? error.message : 'Docker 代理配置保存失败。')
  } finally {
    savingProxy.value = false
  }
}

async function saveRegistries() {
  savingRegistries.value = true
  try {
    registries.value = (
      await dockerApi.updateRegistries(
        props.connectionId,
        registries.value.map((registry) => ({ ...registry })),
      )
    ).map((registry) => ({ ...registry, password: '' }))
    getUiApi().message.success('镜像仓库设置已保存。')
  } catch (error) {
    console.error('Failed to save Docker registries', error)
    getUiApi().message.error(error instanceof Error ? error.message : '镜像仓库设置保存失败。')
  } finally {
    savingRegistries.value = false
  }
}

onMounted(loadConfiguration)
watch(() => props.connectionId, loadConfiguration)
</script>

<template>
  <div v-if="loading" class="settings-loading">
    <NSpin size="large" />
  </div>
  <div v-else class="docker-settings">
    <section class="settings-section">
      <div class="section-heading">
        <div class="section-title"><Gauge :size="18" /><span>镜像加速</span></div>
        <span class="section-meta">按行依次尝试镜像源</span>
      </div>
      <NInput
        v-model:value="mirrorsText"
        type="textarea"
        placeholder="https://mirror.example.com"
        :autosize="{ minRows: 4, maxRows: 8 }"
      />
      <div class="section-actions">
        <NButton @click="openDaemonConfig">
          <template #icon><FilePenLine :size="16" /></template>
          打开配置文件
        </NButton>
        <NButton type="primary" :loading="savingMirrors" @click="saveMirrors">
          <template #icon><Save :size="16" /></template>
          保存
        </NButton>
      </div>
    </section>

    <section class="settings-section">
      <div class="section-heading">
        <div class="section-title"><Globe2 :size="18" /><span>Docker 代理</span></div>
        <NSwitch v-model:value="proxy.enabled" />
      </div>
      <div class="proxy-grid">
        <NFormItem label="HTTP 代理" :show-feedback="false">
          <NInput
            v-model:value="proxy.httpProxy"
            :disabled="!proxy.enabled"
            placeholder="http://127.0.0.1:7890"
          />
        </NFormItem>
        <NFormItem label="HTTPS 代理" :show-feedback="false">
          <NInput
            v-model:value="proxy.httpsProxy"
            :disabled="!proxy.enabled"
            placeholder="http://127.0.0.1:7890"
          />
        </NFormItem>
        <NFormItem label="不代理的地址" :show-feedback="false">
          <NInput
            v-model:value="proxy.noProxy"
            :disabled="!proxy.enabled"
            placeholder="localhost,127.0.0.1"
          />
        </NFormItem>
      </div>
      <div class="section-actions">
        <NButton type="primary" :loading="savingProxy" @click="saveProxy">
          <template #icon><Save :size="16" /></template>
          保存
        </NButton>
      </div>
    </section>

    <section class="settings-section registry-section">
      <div class="section-heading">
        <div class="section-title"><Database :size="18" /><span>镜像仓库</span></div>
        <NTooltip>
          <template #trigger>
            <NButton
              quaternary
              circle
              aria-label="添加镜像仓库"
              @click="registries.push(emptyRegistry())"
            >
              <template #icon><Plus :size="18" /></template>
            </NButton>
          </template>
          添加镜像仓库
        </NTooltip>
      </div>

      <NEmpty v-if="registries.length === 0" description="暂无镜像仓库" size="small" />
      <div v-else class="registry-list">
        <div
          v-for="(registry, index) in registries"
          :key="registry.id ?? `new-${index}`"
          class="registry-row"
        >
          <div class="registry-main-grid">
            <NFormItem label="仓库地址" :show-feedback="false">
              <NInput v-model:value="registry.address" placeholder="https://registry.example.com" />
            </NFormItem>
            <NFormItem label="仓库名称" :show-feedback="false">
              <NInput v-model:value="registry.name" placeholder="生产仓库" />
            </NFormItem>
            <NFormItem label="命名空间" :show-feedback="false">
              <NInput v-model:value="registry.namespace" placeholder="team" />
            </NFormItem>
            <NFormItem label="认证" :show-feedback="false" class="auth-toggle">
              <NSwitch v-model:value="registry.authentication" />
            </NFormItem>
            <NTooltip>
              <template #trigger>
                <NButton
                  quaternary
                  circle
                  type="error"
                  aria-label="删除镜像仓库"
                  @click="registries.splice(index, 1)"
                >
                  <template #icon><Trash2 :size="17" /></template>
                </NButton>
              </template>
              删除镜像仓库
            </NTooltip>
          </div>
          <div v-if="registry.authentication" class="registry-auth-grid">
            <NFormItem label="用户名" :show-feedback="false">
              <NInput v-model:value="registry.username" placeholder="请输入用户名" />
            </NFormItem>
            <NFormItem label="密码" :show-feedback="false">
              <NInput
                v-model:value="registry.password"
                type="password"
                show-password-on="click"
                placeholder="留空表示不更新密码"
              />
            </NFormItem>
          </div>
        </div>
      </div>
      <div class="section-actions">
        <NButton type="primary" :loading="savingRegistries" @click="saveRegistries">
          <template #icon><Save :size="16" /></template>
          保存
        </NButton>
      </div>
    </section>
  </div>
</template>

<style scoped>
.settings-loading {
  display: grid;
  min-height: 220px;
  padding: 12px 16px 24px;
  place-items: center;
}

.docker-settings {
  display: flex;
  flex-direction: column;
  gap: 18px;
  padding: 12px 16px 24px;
}

.settings-section {
  border-bottom: 1px solid var(--docker-tab-card-border);
  padding: 2px 2px 18px;
}

.registry-section {
  border-bottom: 0;
}

.section-heading {
  display: flex;
  min-height: 34px;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  margin-bottom: 12px;
}

.section-title {
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: 15px;
  font-weight: 600;
}

.section-meta {
  color: var(--docker-text-muted);
  font-size: 12px;
}

.proxy-grid {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 16px;
}

.section-actions {
  display: flex;
  justify-content: flex-end;
  gap: 10px;
  margin-top: 14px;
}

.registry-list {
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.registry-row {
  border: 1px solid var(--docker-tab-card-border);
  border-radius: 6px;
  padding: 14px;
}

.registry-main-grid {
  display: grid;
  grid-template-columns: minmax(180px, 1.25fr) minmax(150px, 1fr) minmax(150px, 1fr) 76px 34px;
  gap: 12px;
  align-items: end;
}

.registry-auth-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 12px;
  margin-top: 12px;
}

.auth-toggle :deep(.n-form-item-blank) {
  min-height: 34px;
}

@media (max-width: 900px) {
  .proxy-grid,
  .registry-auth-grid {
    grid-template-columns: 1fr;
  }

  .registry-main-grid {
    grid-template-columns: 1fr 1fr;
  }
}

@media (max-width: 560px) {
  .docker-settings,
  .settings-loading {
    padding: 10px 10px 20px;
  }

  .registry-main-grid {
    grid-template-columns: 1fr;
  }

  .section-meta {
    display: none;
  }
}
</style>
