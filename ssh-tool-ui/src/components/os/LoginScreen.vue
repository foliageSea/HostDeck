<template>
  <div class="h-screen w-screen bg-cover bg-center flex items-center justify-center relative overflow-hidden"
       style="background-image: url('https://images.unsplash.com/photo-1494548162494-384bba4ab999?ixlib=rb-1.2.1&auto=format&fit=crop&w=1920&q=80')">
    
    <!-- Blur Overlay -->
    <div class="absolute inset-0 bg-black/20 backdrop-blur-md"></div>

    <!-- Login Container -->
    <div class="relative z-10 flex flex-col items-center w-full max-w-md p-8 animate-fade-in">
      
      <!-- Avatar -->
      <div class="w-24 h-24 rounded-full bg-gray-200/50 backdrop-blur-xl flex items-center justify-center text-4xl mb-6 shadow-2xl border border-white/20">
        🖥️
      </div>

      <!-- Server Selection -->
      <div v-if="!selectedServer && !isNewConnection" class="w-full space-y-4">
        <h2 class="text-white text-xl font-semibold text-center mb-6 drop-shadow-md">Select a Server</h2>
        
        <div class="space-y-2 max-h-60 overflow-y-auto custom-scrollbar px-2">
          <div 
            v-for="server in sshStore.savedServers" 
            :key="server.id"
            @click="selectServer(server)"
            class="flex items-center p-3 bg-white/10 hover:bg-white/20 backdrop-blur-sm rounded-xl cursor-pointer transition-all border border-white/10"
          >
            <div class="w-10 h-10 rounded-full bg-blue-500/80 flex items-center justify-center text-white mr-3">
              {{ server.name?.[0]?.toUpperCase() || 'S' }}
            </div>
            <div class="flex-1 min-w-0">
              <div class="text-white font-medium truncate">{{ server.name || server.host }}</div>
              <div class="text-white/60 text-xs truncate">{{ server.username }}@{{ server.host }}</div>
            </div>
          </div>
        </div>

        <button 
          @click="isNewConnection = true"
          class="w-full py-3 bg-white/10 hover:bg-white/20 backdrop-blur-sm text-white rounded-xl transition-all border border-white/10 flex items-center justify-center mt-4"
        >
          <span class="mr-2">+</span> New Connection
        </button>
      </div>

      <!-- Login Form (Password or New Connection) -->
      <div v-else class="w-full bg-white/20 backdrop-blur-xl p-6 rounded-2xl shadow-2xl border border-white/20">
        
        <!-- Header -->
        <div class="flex items-center justify-between mb-4">
          <button @click="resetSelection" class="text-white/70 hover:text-white text-sm flex items-center">
            ← Back
          </button>
          <h3 class="text-white font-semibold">
            {{ isNewConnection ? 'New Connection' : selectedServer?.name }}
          </h3>
          <div class="w-8"></div> <!-- Spacer -->
        </div>

        <form @submit.prevent="connect" class="space-y-4">
          
          <template v-if="isNewConnection">
            <input v-model="form.name" placeholder="Display Name (Optional)" class="input-field" />
            <div class="grid grid-cols-3 gap-2">
              <input v-model="form.host" placeholder="Host" class="input-field col-span-2" required />
              <input v-model.number="form.port" type="number" placeholder="Port" class="input-field" required />
            </div>
            <input v-model="form.username" placeholder="Username" class="input-field" required />
          </template>

          <input 
            v-model="form.password" 
            type="password" 
            placeholder="Password" 
            class="input-field" 
            :required="!form.privateKey"
          />

           <textarea 
              v-if="isNewConnection"
              v-model="form.privateKey" 
              placeholder="Private Key (Optional)"
              class="input-field h-20 resize-none py-2"
            ></textarea>

          <button 
            type="submit" 
            class="w-full py-2.5 bg-blue-600 hover:bg-blue-500 text-white font-medium rounded-lg shadow-lg transition-all transform hover:scale-[1.02] flex justify-center items-center mt-2"
            :disabled="loading"
          >
            <span v-if="loading" class="animate-spin mr-2">⏳</span>
            {{ loading ? 'Connecting...' : 'Login' }}
          </button>
        </form>

      </div>

    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, reactive } from 'vue';
import { useSshStore, type SavedServer } from '@/stores/ssh';
import { useDesktopStore } from '@/stores/desktop';

const sshStore = useSshStore();
const desktopStore = useDesktopStore(); // Maybe not needed directly here, but good to have context

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
    // If new connection, save it locally first? Or just connect.
    // Let's just connect.
    
    // API call to connect
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
    
    // Save if new
    if (isNewConnection.value) {
       sshStore.addServer({
        name: form.name || `${form.username}@${form.host}`,
        host: form.host,
        port: form.port,
        username: form.username
      })
    }

    sshStore.setSession(data.sessionId, form.host, form.username);
    
    // No router push needed if App.vue switches component based on store
    
  } catch (e) {
    alert('Connection failed: ' + e);
  } finally {
    loading.value = false;
  }
};
</script>

<style scoped>
.input-field {
  width: 100%;
  padding: 10px 16px;
  background: rgba(255, 255, 255, 0.1);
  border: 1px solid rgba(255, 255, 255, 0.2);
  border-radius: 10px;
  color: white;
  outline: none;
  transition: all 0.2s;
  font-size: 14px;
}

.input-field:focus {
  background: rgba(255, 255, 255, 0.2);
  border-color: rgba(255, 255, 255, 0.5);
}

.input-field::placeholder {
  color: rgba(255, 255, 255, 0.5);
}

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
