<template>
  <TooltipProvider>
    <div class="fixed bottom-4 left-1/2 transform -translate-x-1/2 bg-background/80 backdrop-blur-xl border border-border rounded-2xl px-4 py-2 flex items-end space-x-4 shadow-2xl z-50">
      <Tooltip v-for="app in apps" :key="app.id">
        <TooltipTrigger as-child>
          <div 
            class="group relative flex flex-col items-center cursor-pointer transition-all duration-300 hover:scale-110"
            @click="openApp(app.id)"
          >
            <div class="w-12 h-12 rounded-xl flex items-center justify-center text-3xl shadow-lg bg-card text-card-foreground relative overflow-hidden border border-border">
              <!-- Icon Placeholder -->
              <component 
                v-if="iconMap[app.icon]" 
                :is="iconMap[app.icon]" 
                class="w-6 h-6" 
              />
              <img v-else-if="app.icon.startsWith('http')" :src="app.icon" class="w-full h-full object-cover" />
              <span v-else>{{ app.icon }}</span>
            </div>
            
            <!-- Indicator for open apps -->
            <div v-if="isAppOpen(app.id)" class="w-1 h-1 bg-primary rounded-full mt-1"></div>
          </div>
        </TooltipTrigger>
        <TooltipContent>
          <p>{{ app.title }}</p>
        </TooltipContent>
      </Tooltip>
    </div>
  </TooltipProvider>
</template>

<script setup lang="ts">
import { computed } from 'vue';
import { useDesktopStore } from '@/stores/desktop';
import { Terminal, Folder, Activity, Lock } from 'lucide-vue-next';
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from '@/components/ui/tooltip'

const desktopStore = useDesktopStore();

const apps = computed(() => Object.values(desktopStore.apps));

const iconMap: Record<string, any> = {
  'terminal': Terminal,
  'folder': Folder,
  'activity': Activity,
  'lock': Lock
};

const isAppOpen = (appId: string) => {
  return desktopStore.windows.some(w => w.appId === appId);
};

const openApp = (appId: string) => {
  desktopStore.openWindow(appId);
};
</script>