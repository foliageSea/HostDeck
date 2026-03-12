<script setup lang="ts">
import { computed } from 'vue'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'

const props = defineProps<{
  show: boolean
  title: string
}>()

const emit = defineEmits<{
  (e: 'update:show', value: boolean): void
  (e: 'close'): void
  (e: 'confirm'): void
}>()

const open = computed({
  get: () => props.show,
  set: (val) => {
    emit('update:show', val)
    if (!val) emit('close')
  }
})
</script>

<template>
  <Dialog v-model:open="open">
    <DialogContent>
      <DialogHeader>
        <DialogTitle>{{ title }}</DialogTitle>
      </DialogHeader>
      
      <div class="grid gap-4 py-4">
        <slot></slot>
      </div>
      
      <DialogFooter>
        <slot name="footer">
          <Button variant="outline" @click="open = false">
            取消
          </Button>
          <Button @click="$emit('confirm')">
            确定
          </Button>
        </slot>
      </DialogFooter>
    </DialogContent>
  </Dialog>
</template>