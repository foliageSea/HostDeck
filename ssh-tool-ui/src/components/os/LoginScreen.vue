<template>
  <div class="h-screen w-screen bg-cover bg-center flex items-center justify-center relative overflow-hidden">
    <!-- Background Layer -->
    <div class="absolute inset-0 overflow-hidden">
      <video
        v-if="settingsStore.backgroundType === 'video' && videoUrl"
        :src="videoUrl"
        class="absolute inset-0 w-full h-full object-cover"
        autoplay
        loop
        muted
        playsinline
      ></video>
      <div 
        v-else
        class="absolute inset-0 bg-cover bg-center bg-no-repeat transition-all duration-300"
        :style="{ backgroundImage: `url(${currentBgImage})` }"
      ></div>
    </div>

    <!-- Blur Overlay -->
    <div class="absolute inset-0 bg-background/20 backdrop-blur-md"></div>

    <!-- Login Container -->
    <Card
      class="relative z-10 w-full max-w-md bg-background/60 backdrop-blur-xl border-white/20 shadow-2xl animate-fade-in">
      <CardHeader class="flex flex-col items-center pb-6">
        <div
          class="w-24 h-24 rounded-full bg-muted/80 backdrop-blur-xl flex items-center justify-center text-4xl mb-2 shadow-2xl border border-white/20">
          <Monitor class="w-12 h-12 text-foreground" />
        </div>

        <div v-if="!selectedServer && !isNewConnection" class="w-full text-center">
          <CardTitle class="text-xl">选择服务器</CardTitle>
        </div>
        <div v-else class="flex items-center w-full relative">
          <Button variant="ghost" size="sm" @click="resetSelection" class="absolute left-0 -ml-2">
            <ArrowLeft class="w-4 h-4 mr-1" /> 返回
          </Button>
          <CardTitle class="mx-auto">{{ isNewConnection ? '新建连接' : selectedServer?.name }}</CardTitle>
        </div>
      </CardHeader>

      <CardContent>
        <!-- Server Selection -->
        <div v-if="!selectedServer && !isNewConnection" class="space-y-4">
          <div class="space-y-2 max-h-60 overflow-y-auto custom-scrollbar px-1">
            <div v-for="server in sshStore.savedServers" :key="server.id" @click="selectServer(server)"
              class="flex items-center p-3 bg-white/10 hover:bg-white/20 backdrop-blur-sm rounded-xl cursor-pointer transition-all border border-white/10 group">
              <div
                class="w-10 h-10 rounded-full bg-primary/80 flex items-center justify-center text-primary-foreground mr-3 shadow-sm">
                {{ server.name?.[0]?.toUpperCase() || 'S' }}
              </div>
              <div class="flex-1 min-w-0">
                <div class="text-foreground font-medium truncate group-hover:text-primary transition-colors">{{
                  server.name || server.host }}</div>
                <div class="text-muted-foreground text-xs truncate">{{ server.username }}@{{ server.host }}</div>
              </div>
            </div>
          </div>

          <Button @click="isNewConnection = true" class="w-full" variant="secondary">
            <span class="mr-2">+</span> 新建连接
          </Button>
        </div>

        <!-- Login Form -->
        <form v-else @submit.prevent="connect" class="space-y-4">
          <template v-if="isNewConnection">
            <div class="space-y-2">
              <Label>名称</Label>
              <Input v-model="form.name" placeholder="显示名称（可选）" autofocus />
            </div>
            <div class="grid grid-cols-3 gap-2">
              <div class="col-span-2 space-y-2">
                <Label>主机</Label>
                <Input v-model="form.host" placeholder="主机 IP" required />
              </div>
              <div class="space-y-2">
                <Label>端口</Label>
                <Input v-model.number="form.port" type="number" placeholder="22" required />
              </div>
            </div>
            <div class="space-y-2">
              <Label>用户名</Label>
              <Input v-model="form.username" placeholder="root" required />
            </div>
          </template>

          <div class="space-y-2">
            <Label>密码</Label>
            <Input ref="passwordInputRef" v-model="form.password" type="password" placeholder="请输入密码"
              :required="!form.privateKey" />
          </div>

          <div v-if="isNewConnection" class="space-y-2">
            <Label>私钥 (可选)</Label>
            <textarea v-model="form.privateKey" placeholder="-----BEGIN RSA PRIVATE KEY-----"
              class="flex min-h-[80px] w-full rounded-md border border-input bg-background px-3 py-2 text-sm ring-offset-background placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50 resize-none"></textarea>
          </div>

          <Button type="submit" class="w-full mt-4" :disabled="loading">
            <Loader2 v-if="loading" class="animate-spin mr-2 w-4 h-4" />
            {{ loading ? '连接中...' : '登录' }}
          </Button>
        </form>
      </CardContent>
    </Card>

    <!-- Background Settings Button -->
    <div class="absolute bottom-4 right-4 z-20">
      <DropdownMenu>
        <DropdownMenuTrigger as-child>
          <Button variant="ghost" size="icon"
            class="rounded-full bg-background/20 backdrop-blur-sm hover:bg-background/40">
            <ImageIcon class="w-5 h-5 text-foreground/80" />
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end">
          <DropdownMenuItem @click="triggerBackgroundUpload">设置自定义背景</DropdownMenuItem>
          <DropdownMenuItem @click="triggerVideoUpload">设置视频背景</DropdownMenuItem>
          <DropdownMenuItem @click="resetBackground">恢复默认背景</DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>
      <input type="file" ref="bgInputRef" accept="image/*" class="hidden" @change="onBackgroundSelected" />
      <input type="file" ref="videoInputRef" accept="video/*" class="hidden" @change="onVideoSelected" />
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, reactive, nextTick, computed, onMounted, onUnmounted, watch } from 'vue';
import { useSshStore, type SavedServer } from '@/stores/ssh';
import { useSettingsStore } from '@/stores/settings';
import { Monitor, ArrowLeft, Loader2, Image as ImageIcon } from 'lucide-vue-next';
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import { useToast } from '@/components/ui/toast/use-toast';
import { processBackgroundImage } from '@/utils/image';
import { db } from '@/utils/db';
import bgImage from '@/assets/bg.jpg';
import { useMutation } from '@tanstack/vue-query';
import { authApi } from '@/api/auth';

const sshStore = useSshStore();
const settingsStore = useSettingsStore();
const { toast } = useToast();

const currentBgImage = computed(() => settingsStore.customBackground || bgImage);
const videoUrl = ref<string>('');

const loadVideo = async () => {
  if (settingsStore.backgroundType === 'video') {
    try {
      const blob = await db.getVideo();
      if (blob) {
        if (videoUrl.value) URL.revokeObjectURL(videoUrl.value);
        videoUrl.value = URL.createObjectURL(blob);
      }
    } catch (error) {
      console.error('Failed to load video background:', error);
    }
  }
};

watch([() => settingsStore.backgroundType, () => settingsStore.backgroundVideoTimestamp], ([newType]) => {
  if (newType === 'video') {
    loadVideo();
  } else {
    if (videoUrl.value) {
      URL.revokeObjectURL(videoUrl.value);
      videoUrl.value = '';
    }
  }
});

onMounted(() => {
  loadVideo();
});

onUnmounted(() => {
  if (videoUrl.value) URL.revokeObjectURL(videoUrl.value);
});

const isNewConnection = ref(false);
const selectedServer = ref<SavedServer | null>(null);

const form = reactive({
  name: '',
  host: '',
  port: 22,
  username: '',
  password: '',
  privateKey: ''
});

const passwordInputRef = ref<any>(null);

const bgInputRef = ref<HTMLInputElement | null>(null);
const videoInputRef = ref<HTMLInputElement | null>(null);

const triggerBackgroundUpload = () => {
  bgInputRef.value?.click();
};

const triggerVideoUpload = () => {
  videoInputRef.value?.click();
};

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

  if (target) {
    target.value = '';
  }
};

const onBackgroundSelected = async (event: Event) => {
  const target = event.target as HTMLInputElement;
  const file = target.files?.[0];
  if (!file) return;

  try {
    const dataUrl = await processBackgroundImage(file, settingsStore.backgroundQuality, 1920, 1080);
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

const selectServer = (server: SavedServer) => {
  selectedServer.value = server;
  form.name = server.name;
  form.host = server.host;
  form.port = server.port;
  form.username = server.username;
  form.password = '';
  form.privateKey = '';
  nextTick(() => {
    passwordInputRef.value?.focus();
  });
};

const resetSelection = () => {
  selectedServer.value = null;
  isNewConnection.value = false;
  form.name = '';
  form.host = '';
  form.port = 22;
  form.username = '';
  form.password = '';
  form.privateKey = '';
};

const { mutate: connectMutate, isPending: loading } = useMutation({
  mutationFn: authApi.connect,
  onSuccess: (data) => {
    if (isNewConnection.value) {
      sshStore.addServer({
        name: form.name || `${form.username}@${form.host}`,
        host: form.host,
        port: form.port,
        username: form.username
      })
    }
    sshStore.setSession(data.sessionId, data.connectionId, form.host, form.username);
  },
  onError: (error: any) => {
    const msg = error.response?.data || error.message || 'Unknown error';
    alert('Connection failed: ' + msg);
  }
})

const connect = () => {
  connectMutate(form);
};
</script>

<style scoped>
/* Custom Scrollbar */
.custom-scrollbar::-webkit-scrollbar {
  width: 4px;
}

.custom-scrollbar::-webkit-scrollbar-track {
  background: transparent;
}

.custom-scrollbar::-webkit-scrollbar-thumb {
  background-color: rgba(255, 255, 255, 0.3);
  border-radius: 2px;
}

@keyframes fade-in {
  from {
    opacity: 0;
    transform: translateY(20px);
  }

  to {
    opacity: 1;
    transform: translateY(0);
  }
}

.animate-fade-in {
  animation: fade-in 0.5s ease-out;
}
</style>
