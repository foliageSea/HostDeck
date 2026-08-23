<script setup lang="ts">
import type { FileItem } from '@/api/files'
import { useSettingsStore } from '@/stores/settings'
import type { PermissionAction, PermissionMatrix, PermissionSubject } from '../utils/permissions'

const props = defineProps<{
  changing: boolean
  currentPermission: string
  file: FileItem | null
  hasSpecialPermissionBits: boolean
  isPermissionParsed: boolean
  matrix: PermissionMatrix
  mode: string
  path: string
  recursive: boolean
  show: boolean
}>()

const emit = defineEmits<{
  applyPreset: [mode: string]
  confirm: []
  'update:matrix': [value: PermissionMatrix]
  'update:recursive': [value: boolean]
  'update:show': [value: boolean]
}>()

const settingsStore = useSettingsStore()
const permissionSubjects: { key: PermissionSubject; label: string }[] = [
  { key: 'owner', label: '所有者' },
  { key: 'group', label: '用户组' },
  { key: 'others', label: '其他人' },
]
const permissionActions: { key: PermissionAction; label: string }[] = [
  { key: 'read', label: '读取' },
  { key: 'write', label: '写入' },
  { key: 'execute', label: '执行' },
]
const permissionPresets = [
  { label: '普通文件 644', mode: '644' },
  { label: '可执行/目录 755', mode: '755' },
  { label: '私密文件 600', mode: '600' },
  { label: '私密目录 700', mode: '700' },
]

function updateChecked(subject: PermissionSubject, action: PermissionAction, checked: boolean) {
  emit('update:matrix', {
    ...props.matrix,
    [subject]: { ...props.matrix[subject], [action]: checked },
  })
}
</script>

<template>
  <NModal
    :show="show"
    preset="card"
    title="修改权限"
    style="width: min(560px, calc(100vw - 24px))"
    @update:show="(value: boolean) => emit('update:show', value)"
  >
    <div v-if="file" class="flex flex-col gap-[14px]">
      <div class="flex flex-col gap-[8px]">
        <div class="property-row">
          <span class="property-label">名称</span>
          <span class="property-value">{{ file.filename }}</span>
        </div>
        <div class="property-row">
          <span class="property-label">路径</span>
          <span class="property-value break-all">{{ path }}</span>
        </div>
        <div class="property-row">
          <span class="property-label">当前权限</span>
          <span class="property-value font-mono">{{ currentPermission }}</span>
        </div>
      </div>

      <NAlert v-if="!isPermissionParsed" type="warning" :bordered="false">
        无法解析当前权限，请手动选择要应用的权限。
      </NAlert>
      <NAlert v-else-if="hasSpecialPermissionBits" type="warning" :bordered="false">
        当前包含特殊权限位，应用后将只设置读取、写入和执行权限。
      </NAlert>

      <div class="grid grid-cols-[88px_repeat(3,minmax(0,1fr))] items-center gap-[8px] text-[13px]">
        <span />
        <span v-for="action in permissionActions" :key="action.key" class="text-center font-600">
          {{ action.label }}
        </span>
        <template v-for="subject in permissionSubjects" :key="subject.key">
          <span class="font-600">{{ subject.label }}</span>
          <NCheckbox
            v-for="action in permissionActions"
            :key="`${subject.key}-${action.key}`"
            class="justify-center"
            :checked="matrix[subject.key][action.key]"
            @update:checked="(checked: boolean) => updateChecked(subject.key, action.key, checked)"
          />
        </template>
      </div>

      <div class="flex flex-wrap gap-[8px]">
        <NButton
          v-for="preset in permissionPresets"
          :key="preset.mode"
          quaternary
          size="small"
          @click="emit('applyPreset', preset.mode)"
        >
          {{ preset.label }}
        </NButton>
      </div>

      <NAlert v-if="file.isDirectory" type="info" :bordered="false">
        <div class="flex flex-col gap-[8px]">
          <NCheckbox
            :checked="recursive"
            @update:checked="(checked: boolean) => emit('update:recursive', checked)"
          >
            递归应用到目录内所有文件和子目录
          </NCheckbox>
          <span v-if="recursive">递归修改会影响该目录下全部项目，请确认权限策略后再应用。</span>
        </div>
      </NAlert>

      <div
        class="app-radius-item rounded-[12px] px-[12px] py-[10px] text-[13px]"
        :class="
          settingsStore.isDark
            ? 'bg-[rgba(15,23,42,0.54)] text-[rgba(226,232,240,0.96)]'
            : 'bg-[rgba(241,245,249,0.92)] text-[rgba(51,65,85,0.96)]'
        "
      >
        将应用权限：<span class="font-mono font-700">{{ mode }}</span>
      </div>

      <NSpace justify="end">
        <NButton quaternary :disabled="changing" @click="emit('update:show', false)">取消</NButton>
        <NButton quaternary type="primary" :loading="changing" @click="emit('confirm')"
          >应用权限</NButton
        >
      </NSpace>
    </div>
  </NModal>
</template>
