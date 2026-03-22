<template>
  <AlertDialog>
    <AlertDialogTrigger asChild>
      <slot></slot>
    </AlertDialogTrigger>
    <AlertDialogContent @click.stop>
      <AlertDialogHeader>
        <AlertDialogTitle>{{ title }}</AlertDialogTitle>
        <AlertDialogDescription>
          <slot name="description">{{ description }}</slot>
        </AlertDialogDescription>
      </AlertDialogHeader>
      <AlertDialogFooter>
        <AlertDialogCancel @click.stop="onCancel">{{ cancelText }}</AlertDialogCancel>
        <AlertDialogAction @click.stop="onConfirm">{{ confirmText }}</AlertDialogAction>
      </AlertDialogFooter>
    </AlertDialogContent>
  </AlertDialog>
</template>

<script setup lang="ts">
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from '@/components/ui/alert-dialog'

/**
 * 通用确认弹窗组件
 */
withDefaults(defineProps<{
  title?: string;
  description?: string;
  confirmText?: string;
  cancelText?: string;
}>(), {
  title: '确认操作',
  description: '您确定要执行此操作吗？此操作无法撤销。',
  confirmText: '确定',
  cancelText: '取消',
});

const emit = defineEmits<{
  (e: 'confirm'): void;
  (e: 'cancel'): void;
}>();

/**
 * 确认按钮点击处理函数
 */
const onConfirm = () => {
  emit('confirm');
};

/**
 * 取消按钮点击处理函数
 */
const onCancel = () => {
  emit('cancel');
};
</script>
