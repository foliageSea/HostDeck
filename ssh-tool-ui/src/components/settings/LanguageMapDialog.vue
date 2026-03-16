<template>
  <Dialog :open="open" @update:open="$emit('update:open', $event)">
    <DialogContent class="sm:max-w-[600px] max-h-[80vh] flex flex-col">
      <DialogHeader>
        <DialogTitle>语言关联设置</DialogTitle>
        <DialogDescription>
          配置不同文件扩展名对应的编辑器语言。
        </DialogDescription>
      </DialogHeader>

      <div class="flex-1 overflow-y-auto py-4 custom-scrollbar">
        <Table>
          <TableHeader class="sticky top-0 z-10 bg-background">
            <TableRow>
              <TableHead>扩展名</TableHead>
              <TableHead>语言 ID</TableHead>
              <TableHead class="w-[50px]"></TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            <TableRow v-for="(lang, ext) in settingsStore.languageMap" :key="ext">
              <TableCell class="font-medium">.{{ ext }}</TableCell>
              <TableCell>{{ lang }}</TableCell>
              <TableCell>
                <Button variant="ghost" size="icon" @click="removeMapping(String(ext))">
                  <Trash2 class="h-4 w-4 text-destructive" />
                </Button>
              </TableCell>
            </TableRow>
          </TableBody>
        </Table>
      </div>

      <div class="flex flex-col gap-4 border-t pt-4">
        <div class="grid grid-cols-3 gap-2">
          <Input v-model="newExt" placeholder="扩展名 (不带点)" />
          <Input v-model="newLang" placeholder="语言 ID (如 javascript)" />
          <Button @click="addMapping" :disabled="!newExt || !newLang">添加</Button>
        </div>
        <div class="flex justify-between">
          <Button variant="outline" @click="resetDefaults">恢复默认</Button>
          <Button @click="$emit('update:open', false)">关闭</Button>
        </div>
      </div>
    </DialogContent>
  </Dialog>
</template>

<script setup lang="ts">
import { ref } from 'vue'
import { useSettingsStore } from '@/stores/settings'
import { Trash2 } from 'lucide-vue-next'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import { Input } from '@/components/ui/input'
import { Button } from '@/components/ui/button'

defineProps<{
  open: boolean
}>()

defineEmits(['update:open'])

const settingsStore = useSettingsStore()
const newExt = ref('')
const newLang = ref('')

const addMapping = () => {
  if (newExt.value && newLang.value) {
    settingsStore.updateLanguageMap(newExt.value, newLang.value)
    newExt.value = ''
    newLang.value = ''
  }
}

const removeMapping = (ext: string) => {
  settingsStore.removeLanguageMap(ext)
}

const resetDefaults = () => {
  if (confirm('确定要恢复默认设置吗？这将清除所有自定义映射。')) {
    settingsStore.resetLanguageMap()
  }
}
</script>
