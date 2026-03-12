<template>
  <div class="h-screen w-screen bg-cover bg-center flex items-center justify-center relative overflow-hidden"
       :style="{ backgroundImage: `url(${bgImage})` }">
    
    <!-- Blur Overlay -->
    <div class="absolute inset-0 bg-background/20 backdrop-blur-md"></div>

    <!-- Login Container -->
    <Card class="relative z-10 w-full max-w-md bg-background/60 backdrop-blur-xl border-white/20 shadow-2xl animate-fade-in">
      <CardHeader class="flex flex-col items-center pb-6">
        <div class="w-24 h-24 rounded-full bg-muted/80 backdrop-blur-xl flex items-center justify-center text-4xl mb-2 shadow-2xl border border-white/20">
          <Monitor class="w-12 h-12 text-foreground" />
        </div>
        
        <div v-if="!selectedServer && !isNewConnection" class="w-full text-center">
          <CardTitle class="text-xl">选择服务器</CardTitle>
        </div>
        <div v-else class="flex items-center w-full relative">
          <Button variant="ghost" size="sm" @click="resetSelection" class="absolute left-0 -ml-2">
            <ArrowLeft class="w-4 h-4 mr-1"/> 返回
          </Button>
          <CardTitle class="mx-auto">{{ isNewConnection ? '新建连接' : selectedServer?.name }}</CardTitle>
        </div>
      </CardHeader>

      <CardContent>
        <!-- Server Selection -->
        <div v-if="!selectedServer && !isNewConnection" class="space-y-4">
          <div class="space-y-2 max-h-60 overflow-y-auto custom-scrollbar px-1">
            <div 
              v-for="server in sshStore.savedServers" 
              :key="server.id"
              @click="selectServer(server)"
              class="flex items-center p-3 bg-white/10 hover:bg-white/20 backdrop-blur-sm rounded-xl cursor-pointer transition-all border border-white/10 group"
            >
              <div class="w-10 h-10 rounded-full bg-primary/80 flex items-center justify-center text-primary-foreground mr-3 shadow-sm">
                {{ server.name?.[0]?.toUpperCase() || 'S' }}
              </div>
              <div class="flex-1 min-w-0">
                <div class="text-foreground font-medium truncate group-hover:text-primary transition-colors">{{ server.name || server.host }}</div>
                <div class="text-muted-foreground text-xs truncate">{{ server.username }}@{{ server.host }}</div>
              </div>
            </div>
          </div>

          <Button 
            @click="isNewConnection = true"
            class="w-full"
            variant="secondary"
          >
            <span class="mr-2">+</span> 新建连接
          </Button>
        </div>

        <!-- Login Form -->
        <form v-else @submit.prevent="connect" class="space-y-4">
          <template v-if="isNewConnection">
            <div class="space-y-2">
              <Label>名称</Label>
              <Input v-model="form.name" placeholder="显示名称（可选）" />
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
            <Input 
              v-model="form.password" 
              type="password" 
              placeholder="请输入密码" 
              :required="!form.privateKey"
            />
          </div>

          <div v-if="isNewConnection" class="space-y-2">
            <Label>私钥 (可选)</Label>
            <textarea 
              v-model="form.privateKey" 
              placeholder="-----BEGIN RSA PRIVATE KEY-----"
              class="flex min-h-[80px] w-full rounded-md border border-input bg-background px-3 py-2 text-sm ring-offset-background placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50 resize-none"
            ></textarea>
          </div>

          <Button type="submit" class="w-full mt-4" :disabled="loading">
            <Loader2 v-if="loading" class="animate-spin mr-2 w-4 h-4" />
            {{ loading ? '连接中...' : '登录' }}
          </Button>
        </form>
      </CardContent>
    </Card>
  </div>
</template>

<script setup lang="ts">
import { ref, reactive } from 'vue';
import { useSshStore, type SavedServer } from '@/stores/ssh';
import { Monitor, ArrowLeft, Loader2 } from 'lucide-vue-next';
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import bgImage from '@/assets/bg.jpg';

const sshStore = useSshStore();

const loading = ref(false);
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

const selectServer = (server: SavedServer) => {
  selectedServer.value = server;
  form.name = server.name;
  form.host = server.host;
  form.port = server.port;
  form.username = server.username;
  form.password = '';
  form.privateKey = '';
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

const connect = async () => {
  loading.value = true;
  try {
    const res = await fetch('/api/connect', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(form)
    })
    
    if (!res.ok) {
      const text = await res.text()
      throw new Error(text)
    }
    
    const data = await res.json()
    
    if (isNewConnection.value) {
       sshStore.addServer({
        name: form.name || `${form.username}@${form.host}`,
        host: form.host,
        port: form.port,
        username: form.username
      })
    }

    sshStore.setSession(data.sessionId, form.host, form.username);
    
  } catch (e) {
    alert('Connection failed: ' + e);
  } finally {
    loading.value = false;
  }
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
  from { opacity: 0; transform: translateY(20px); }
  to { opacity: 1; transform: translateY(0); }
}
.animate-fade-in {
  animation: fade-in 0.5s ease-out;
}
</style>