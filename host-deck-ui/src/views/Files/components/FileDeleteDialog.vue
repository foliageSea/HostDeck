<script setup lang="ts">
defineProps<{
  deleting: boolean
  selectedCount: number
  selectedFilename?: string
  show: boolean
}>()

const emit = defineEmits<{
  confirm: []
  'update:show': [value: boolean]
}>()
</script>

<template>
  <NModal
    :show="show"
    preset="dialog"
    title="确认删除"
    positive-text="删除"
    negative-text="取消"
    :positive-button-props="{ loading: deleting }"
    @update:show="(value: boolean) => emit('update:show', value)"
    @positive-click="emit('confirm')"
    @negative-click="emit('update:show', false)"
  >
    删除
    {{ selectedCount > 1 ? `这 ${selectedCount} 个项目` : '`' + (selectedFilename ?? '') + '`' }}
    后不可恢复。
  </NModal>
</template>
