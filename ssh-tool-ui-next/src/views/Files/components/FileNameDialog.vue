<script setup lang="ts">
defineProps<{
  show: boolean
  title: string
  value: string
}>()

const emit = defineEmits<{
  'update:show': [value: boolean]
  'update:value': [value: string]
  confirm: []
}>()
</script>

<template>
  <NModal
    :show="show"
    preset="card"
    :title="title"
    class="file-dialog"
    @update:show="(value: boolean) => emit('update:show', value)"
  >
    <NSpace vertical>
      <NInput
        :value="value"
        placeholder="输入名称"
        @update:value="(nextValue: string) => emit('update:value', nextValue)"
        @keyup.enter="emit('confirm')"
      />
      <NSpace justify="end">
        <NButton @click="emit('update:show', false)">取消</NButton>
        <NButton type="primary" @click="emit('confirm')">确认</NButton>
      </NSpace>
    </NSpace>
  </NModal>
</template>

<style scoped>
.file-dialog {
  width: min(440px, calc(100vw - 24px));
}
</style>
