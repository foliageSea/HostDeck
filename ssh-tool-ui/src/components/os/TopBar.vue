<template>
  <div
    class="fixed top-0 left-0 right-0 h-9 bg-background/40 backdrop-blur-xl border-b border-border/50 z-50 flex items-center justify-between px-4 select-none">
    <div class="flex items-center space-x-1">
      <span class="font-bold text-sm flex items-center mr-4 text-foreground">
        <Terminal class="w-4 h-4 mr-2" /> SSH Tool
      </span>

      <DropdownMenu>
        <DropdownMenuTrigger as-child>
          <Button variant="ghost" size="sm" class="h-7 px-2 text-sm font-normal">外观</Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent>
          <DropdownMenuItem @click="triggerBackgroundUpload">设置桌面背景</DropdownMenuItem>
          <DropdownMenuItem @click="resetBackground">恢复默认背景</DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>

      <DropdownMenu>
        <DropdownMenuTrigger as-child>
          <Button variant="ghost" size="sm" class="h-7 px-2 text-sm font-normal">帮助</Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent>
          <DropdownMenuItem>关于 SSH Tool</DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>
    </div>
    <div class="flex items-center space-x-4">
      <SystemMonitor />
      <span class="text-sm font-medium text-foreground">{{ currentTime }}</span>
    </div>

    <!-- Hidden file input for background upload -->
    <input type="file" ref="bgInputRef" accept="image/*" class="hidden" @change="onBackgroundSelected" />
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted, onUnmounted } from 'vue';
import { Terminal } from 'lucide-vue-next';
import { Button } from '@/components/ui/button'
import SystemMonitor from './SystemMonitor.vue';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import { useSettingsStore } from '@/stores/settings';
import { useToast } from '@/components/ui/toast/use-toast';
import { processBackgroundImage } from '@/utils/image';

const currentTime = ref('');
const settingsStore = useSettingsStore();
const { toast } = useToast();

const bgInputRef = ref<HTMLInputElement | null>(null);

const triggerBackgroundUpload = () => {
  bgInputRef.value?.click();
};

const setBackgroundQuality = (quality: number) => {
  settingsStore.setBackgroundQuality(quality);
  toast({
    title: "清晰度已更新",
    description: `背景清晰度已设置为 ${quality * 100}%，重新上传背景后生效。`,
  });
};

// Make it available to template
defineExpose({ setBackgroundQuality });

const onBackgroundSelected = async (event: Event) => {
  const target = event.target as HTMLInputElement;
  const file = target.files?.[0];
  if (!file) return;

  try {
    const dataUrl = await processBackgroundImage(file, settingsStore.backgroundQuality);
    settingsStore.setCustomBackground(dataUrl);
    toast({
      title: "背景已更新",
      description: "自定义背景已保存。",
    });
  } catch (err) {
    console.error('Failed to save background:', err);
    toast({
      title: "保存失败",
      description: "图片过大，请尝试降低清晰度或选择更小的图片。",
      variant: "destructive"
    });
  }

  // Reset input
  if (target) {
    target.value = '';
  }
};

const resetBackground = () => {
  settingsStore.resetCustomBackground();
  toast({
    title: "背景已重置",
    description: "已恢复默认背景。",
  });
};

const updateTime = () => {
  const now = new Date();
  currentTime.value = now.toLocaleTimeString('zh-CN', {
    hour: 'numeric',
    minute: '2-digit',
    hour12: false
  });
};

let interval: number;

onMounted(() => {
  updateTime();
  interval = setInterval(updateTime, 1000);
});

onUnmounted(() => {
  clearInterval(interval);
});
</script>