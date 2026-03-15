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
          <DropdownMenuSub>
            <DropdownMenuSubTrigger>
              <Sun class="mr-2 h-4 w-4" v-if="settingsStore.themeMode === 'light'" />
              <Moon class="mr-2 h-4 w-4" v-else-if="settingsStore.themeMode === 'dark'" />
              <Monitor class="mr-2 h-4 w-4" v-else />
              <span>主题模式</span>
            </DropdownMenuSubTrigger>
            <DropdownMenuSubContent>
              <DropdownMenuRadioGroup v-model="settingsStore.themeMode">
                <DropdownMenuRadioItem value="light">
                  <Sun class="mr-2 h-4 w-4" />
                  <span>明亮模式</span>
                </DropdownMenuRadioItem>
                <DropdownMenuRadioItem value="dark">
                  <Moon class="mr-2 h-4 w-4" />
                  <span>暗黑模式</span>
                </DropdownMenuRadioItem>
                <DropdownMenuRadioItem value="auto">
                  <Monitor class="mr-2 h-4 w-4" />
                  <span>跟随系统</span>
                </DropdownMenuRadioItem>
              </DropdownMenuRadioGroup>
            </DropdownMenuSubContent>
          </DropdownMenuSub>
          <DropdownMenuSeparator />
          <DropdownMenuItem @click="triggerBackgroundUpload">设置桌面背景</DropdownMenuItem>
          <DropdownMenuItem @click="triggerVideoUpload">设置视频背景</DropdownMenuItem>
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
    <input type="file" ref="videoInputRef" accept="video/*" class="hidden" @change="onVideoSelected" />
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted, onUnmounted } from 'vue';
import { Terminal, Sun, Moon, Monitor } from 'lucide-vue-next';
import { Button } from '@/components/ui/button'
import SystemMonitor from './SystemMonitor.vue';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
  DropdownMenuSub,
  DropdownMenuSubTrigger,
  DropdownMenuSubContent,
  DropdownMenuRadioGroup,
  DropdownMenuRadioItem,
  DropdownMenuSeparator,
} from '@/components/ui/dropdown-menu'
import { useSettingsStore } from '@/stores/settings';
import { useToast } from '@/components/ui/toast/use-toast';
import { processBackgroundImage } from '@/utils/image';

const currentTime = ref('');
const settingsStore = useSettingsStore();
const { toast } = useToast();

const bgInputRef = ref<HTMLInputElement | null>(null);
const videoInputRef = ref<HTMLInputElement | null>(null);

const triggerBackgroundUpload = () => {
  bgInputRef.value?.click();
};

const triggerVideoUpload = () => {
  videoInputRef.value?.click();
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

const onVideoSelected = async (event: Event) => {
  const target = event.target as HTMLInputElement;
  const file = target.files?.[0];
  if (!file) return;

  // 100MB limit
  if (file.size > 100 * 1024 * 1024) {
    toast({
      title: "文件过大",
      description: "视频文件大小不能超过 100MB。",
      variant: "destructive"
    });
    target.value = '';
    return;
  }

  try {
    await settingsStore.setVideoBackground(file);
    toast({
      title: "背景已更新",
      description: "视频背景已设置。",
    });
  } catch (err) {
    console.error('Failed to save video background:', err);
    toast({
      title: "保存失败",
      description: "无法保存视频背景，请重试。",
      variant: "destructive"
    });
  }

  // Reset input
  if (target) {
    target.value = '';
  }
};

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