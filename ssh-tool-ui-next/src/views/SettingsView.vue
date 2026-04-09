<script setup lang="ts">
import { useSettingsStore } from '@/stores/settings'

const settingsStore = useSettingsStore()
</script>

<template>
  <div class="settings-view">
    <NCard title="基础设置" size="large">
      <NForm label-placement="top">
        <NFormItem label="主题模式">
          <NRadioGroup :value="settingsStore.themeMode" @update:value="settingsStore.setTheme">
            <NSpace>
              <NRadio value="system">跟随系统</NRadio>
              <NRadio value="dark">深色</NRadio>
              <NRadio value="light">浅色</NRadio>
            </NSpace>
          </NRadioGroup>
        </NFormItem>
      </NForm>
    </NCard>
  </div>
</template>

<style scoped>
.settings-view {
  height: 100%;
  padding: 20px;
}
</style>
