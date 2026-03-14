<template>
  <div class="fixed top-0 left-0 right-0 h-9 bg-background/40 backdrop-blur-xl border-b border-border/50 z-50 flex items-center justify-between px-4 select-none">
    <div class="flex items-center space-x-1">
      <span class="font-bold text-sm flex items-center mr-4 text-foreground"><Terminal class="w-4 h-4 mr-2"/> SSH Tool</span>
      
      <DropdownMenu>
        <DropdownMenuTrigger as-child>
           <Button variant="ghost" size="sm" class="h-7 px-2 text-sm font-normal">文件</Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent>
           <DropdownMenuItem>新建窗口</DropdownMenuItem>
           <DropdownMenuItem>关闭窗口</DropdownMenuItem>
           <DropdownMenuSeparator />
           <DropdownMenuItem>退出</DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>

      <DropdownMenu>
        <DropdownMenuTrigger as-child>
           <Button variant="ghost" size="sm" class="h-7 px-2 text-sm font-normal">编辑</Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent>
           <DropdownMenuItem>撤销</DropdownMenuItem>
           <DropdownMenuItem>重做</DropdownMenuItem>
           <DropdownMenuSeparator />
           <DropdownMenuItem>剪切</DropdownMenuItem>
           <DropdownMenuItem>复制</DropdownMenuItem>
           <DropdownMenuItem>粘贴</DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>

      <DropdownMenu>
        <DropdownMenuTrigger as-child>
           <Button variant="ghost" size="sm" class="h-7 px-2 text-sm font-normal">视图</Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent>
           <DropdownMenuItem>全屏</DropdownMenuItem>
           <DropdownMenuItem>最小化</DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>

      <DropdownMenu>
        <DropdownMenuTrigger as-child>
           <Button variant="ghost" size="sm" class="h-7 px-2 text-sm font-normal">窗口</Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent>
           <DropdownMenuItem>最小化所有</DropdownMenuItem>
           <DropdownMenuItem>全部显示</DropdownMenuItem>
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
  DropdownMenuSeparator,
} from '@/components/ui/dropdown-menu'

const currentTime = ref('');

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