<template>
  <div class="flex flex-col md:flex-row h-full gap-6 text-gray-800 dark:text-gray-100 overflow-hidden">
    
    <!-- Left: Saved Servers List -->
    <div class="w-full md:w-1/3 lg:w-1/4 flex flex-col space-y-4 min-w-[280px]">
      <div class="flex justify-between items-center px-1">
        <h2 class="text-xl font-bold tracking-tight">服务器列表</h2>
        <button 
          @click="resetForm" 
          class="flex items-center text-sm font-medium text-blue-600 hover:text-blue-800 dark:text-blue-400 dark:hover:text-blue-300 transition-colors bg-blue-50 dark:bg-blue-900/30 px-3 py-1.5 rounded-full"
        >
          <span class="mr-1">+</span> 新建
        </button>
      </div>
      
      <div class="flex-1 overflow-y-auto space-y-3 pr-2 custom-scrollbar pb-4">
        <div v-if="sshStore.savedServers.length === 0" class="flex flex-col items-center justify-center py-12 text-gray-400 border-2 border-dashed border-gray-200 dark:border-gray-700 rounded-xl">
          <Monitor class="text-4xl mb-2 w-10 h-10" />
          <p class="text-sm">暂无保存的服务器</p>
        </div>
        
        <div 
          v-for="server in sshStore.savedServers" 
          :key="server.id"
          @click="selectServer(server)"
          class="group relative p-4 bg-white dark:bg-gray-800 rounded-xl shadow-sm hover:shadow-md cursor-pointer transition-all border border-gray-100 dark:border-gray-700 hover:border-blue-400 dark:hover:border-blue-500"
          :class="{ 'ring-2 ring-blue-500 border-transparent dark:border-transparent': currentServerId === server.id }"
        >
          <div class="flex justify-between items-start">
            <div class="flex-1 min-w-0">
              <h3 class="font-semibold text-base truncate pr-6">{{ server.name || server.host }}</h3>
              <div class="flex items-center text-xs text-gray-500 dark:text-gray-400 mt-1 space-x-2">
                <span class="bg-gray-100 dark:bg-gray-700 px-1.5 py-0.5 rounded text-[10px] font-mono">{{ server.username }}</span>
                <span class="truncate">{{ server.host }}:{{ server.port }}</span>
              </div>
            </div>
            <button 
              @click.stop="deleteServer(server.id)" 
              class="absolute top-3 right-3 opacity-0 group-hover:opacity-100 p-1.5 text-gray-400 hover:text-red-500 hover:bg-red-50 dark:hover:bg-red-900/30 rounded-lg transition-all"
              title="删除"
            >
              <Trash2 class="h-4 w-4" />
            </button>
          </div>
        </div>
      </div>
    </div>

    <!-- Right: Connection Form -->
    <div class="flex-1 flex flex-col justify-center items-center p-4 md:p-8 overflow-y-auto">
      <div class="bg-white dark:bg-gray-800 p-8 rounded-2xl shadow-xl max-w-2xl w-full border border-gray-100 dark:border-gray-700 transition-all">
        <div class="mb-8 text-center">
          <h1 class="text-3xl font-bold text-gray-900 dark:text-white mb-2">
            {{ currentServerId ? '连接到服务器' : '新建连接' }}
          </h1>
          <p class="text-gray-500 dark:text-gray-400 text-sm">
            {{ currentServerId ? '输入密码以连接' : '输入服务器信息以连接' }}
          </p>
        </div>
        
        <form @submit.prevent="connect" class="space-y-5">
          <!-- Server Name (Only for saving) -->
          <div class="relative">
            <label class="block text-xs font-semibold text-gray-500 uppercase tracking-wider mb-1">显示名称</label>
            <input 
              v-model="form.name" 
              type="text" 
              placeholder="例如：生产环境数据库" 
              class="w-full px-4 py-2.5 bg-gray-50 dark:bg-gray-700/50 border border-gray-200 dark:border-gray-600 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent outline-none transition-all placeholder-gray-400"
            />
          </div>

          <div class="grid grid-cols-1 md:grid-cols-3 gap-5">
            <div class="md:col-span-2">
              <label class="block text-xs font-semibold text-gray-500 uppercase tracking-wider mb-1">主机</label>
              <input 
                v-model="form.host" 
                type="text" 
                placeholder="192.168.1.1"
                class="w-full px-4 py-2.5 bg-gray-50 dark:bg-gray-700/50 border border-gray-200 dark:border-gray-600 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent outline-none transition-all font-mono text-sm" 
                required 
              />
            </div>
            <div>
              <label class="block text-xs font-semibold text-gray-500 uppercase tracking-wider mb-1">端口</label>
              <input 
                v-model.number="form.port" 
                type="number" 
                placeholder="22"
                class="w-full px-4 py-2.5 bg-gray-50 dark:bg-gray-700/50 border border-gray-200 dark:border-gray-600 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent outline-none transition-all font-mono text-sm" 
                required 
              />
            </div>
          </div>

          <div>
            <label class="block text-xs font-semibold text-gray-500 uppercase tracking-wider mb-1">用户名</label>
            <input 
              v-model="form.username" 
              type="text" 
              placeholder="root"
              class="w-full px-4 py-2.5 bg-gray-50 dark:bg-gray-700/50 border border-gray-200 dark:border-gray-600 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent outline-none transition-all font-mono text-sm" 
              required 
            />
          </div>

          <div>
            <label class="block text-xs font-semibold text-gray-500 uppercase tracking-wider mb-1">
              密码 <span class="text-gray-400 font-normal normal-case">(不保存)</span>
            </label>
            <div class="relative">
              <input 
                v-model="form.password" 
                :type="showPassword ? 'text' : 'password'" 
                class="w-full px-4 py-2.5 bg-gray-50 dark:bg-gray-700/50 border border-gray-200 dark:border-gray-600 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent outline-none transition-all font-mono text-sm pr-10" 
              />
              <button 
                type="button"
                @click="showPassword = !showPassword"
                class="absolute right-3 top-1/2 transform -translate-y-1/2 text-gray-400 hover:text-gray-600 dark:hover:text-gray-300 focus:outline-none"
              >
                <EyeOff v-if="showPassword" class="h-4 w-4" />
                <Eye v-else class="h-4 w-4" />
              </button>
            </div>
          </div>

          <div>
            <label class="block text-xs font-semibold text-gray-500 uppercase tracking-wider mb-1">
              私钥 <span class="text-gray-400 font-normal normal-case">(可选)</span>
            </label>
            <textarea 
              v-model="form.privateKey" 
              placeholder="-----BEGIN RSA PRIVATE KEY-----"
              class="w-full px-4 py-2.5 bg-gray-50 dark:bg-gray-700/50 border border-gray-200 dark:border-gray-600 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent outline-none transition-all font-mono text-xs h-24 resize-none"
            ></textarea>
          </div>
          
          <div class="pt-4 flex gap-4">
            <button 
              type="submit" 
              class="flex-1 py-3 px-4 bg-blue-600 hover:bg-blue-700 text-white font-semibold rounded-lg shadow-md hover:shadow-lg transition-all transform hover:-translate-y-0.5 disabled:opacity-70 disabled:cursor-not-allowed flex justify-center items-center" 
              :disabled="loading"
            >
              <Loader2 v-if="loading" class="animate-spin -ml-1 mr-2 h-5 w-5 text-white" />
              {{ loading ? '连接中...' : '连接' }}
            </button>
            
            <button 
              type="button" 
              @click="saveServer"
              class="px-6 py-3 bg-gray-100 hover:bg-gray-200 dark:bg-gray-700 dark:hover:bg-gray-600 text-gray-700 dark:text-gray-200 font-semibold rounded-lg transition-all shadow-sm hover:shadow flex items-center justify-center"
            >
              <Save class="w-4 h-4 mr-2" />
              {{ currentServerId ? '更新' : '保存' }}
            </button>
          </div>
        </form>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, reactive } from 'vue'
import { useRouter } from 'vue-router'
import { useSshStore, type SavedServer } from '../stores/ssh'
import { Monitor, Trash2, Eye, EyeOff, Loader2, Save } from 'lucide-vue-next'

const router = useRouter()
const sshStore = useSshStore()
const loading = ref(false)
const showPassword = ref(false)
const currentServerId = ref<string | null>(null)

const form = reactive({
  name: '',
  host: '',
  port: 22,
  username: '',
  password: '',
  privateKey: ''
})

function resetForm() {
  currentServerId.value = null
  form.name = ''
  form.host = ''
  form.port = 22
  form.username = ''
  form.password = ''
  form.privateKey = ''
}

function selectServer(server: SavedServer) {
  currentServerId.value = server.id
  form.name = server.name
  form.host = server.host
  form.port = server.port
  form.username = server.username
  form.password = '' // Don't load password as it's not saved
  form.privateKey = '' // Assuming private key is also not saved or loaded differently
}

function deleteServer(id: string) {
  if (confirm('Are you sure you want to delete this server?')) {
    sshStore.removeServer(id)
    if (currentServerId.value === id) {
      resetForm()
    }
  }
}

function saveServer() {
  if (!form.host || !form.username) {
    alert('Host and Username are required to save.')
    return
  }
  
  const serverData = {
    name: form.name || `${form.username}@${form.host}`,
    host: form.host,
    port: form.port,
    username: form.username
  }

  if (currentServerId.value) {
    sshStore.updateServer(currentServerId.value, serverData)
  } else {
    sshStore.addServer(serverData)
    // Try to find the newly added server to select it (optional)
    // For now, just reset form or keep it? Let's keep it but clear password field maybe?
    // Actually, let's keep it as is so user can connect immediately.
  }
}

async function connect() {
  loading.value = true
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
    sshStore.setSession(data.sessionId, data.connectionId, form.host, form.username)
    router.push('/dashboard')
  } catch (e) {
    alert('Connection failed: ' + e)
  } finally {
    loading.value = false
  }
}
</script>

<style scoped>
/* Custom Scrollbar for Webkit */
.custom-scrollbar::-webkit-scrollbar {
  width: 6px;
}
.custom-scrollbar::-webkit-scrollbar-track {
  background: transparent;
}
.custom-scrollbar::-webkit-scrollbar-thumb {
  background-color: rgba(156, 163, 175, 0.3);
  border-radius: 3px;
}
.custom-scrollbar::-webkit-scrollbar-thumb:hover {
  background-color: rgba(156, 163, 175, 0.5);
}
</style>
