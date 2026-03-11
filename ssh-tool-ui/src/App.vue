<template>
  <div class="flex h-screen bg-gray-100 dark:bg-gray-900 text-gray-900 dark:text-gray-100 font-sans">
    <!-- Sidebar -->
    <aside v-if="sshStore.isConnected" class="w-64 bg-white dark:bg-gray-800 shadow-md flex flex-col transition-all duration-300">
      <div class="p-6 text-xl font-bold border-b dark:border-gray-700 flex items-center">
        <span class="w-3 h-3 rounded-full bg-red-500 mr-2"></span>
        <span class="w-3 h-3 rounded-full bg-yellow-500 mr-2"></span>
        <span class="w-3 h-3 rounded-full bg-green-500 mr-4"></span>
        SSH Tool
      </div>
      <div class="p-4 text-sm text-gray-500 dark:text-gray-400">
        {{ sshStore.username }}@{{ sshStore.host }}
      </div>
      <nav class="flex-1 p-4 space-y-2">
        <router-link to="/dashboard" class="flex items-center px-4 py-2 rounded hover:bg-gray-200 dark:hover:bg-gray-700 transition-colors" active-class="bg-blue-100 dark:bg-blue-900 text-blue-600 dark:text-blue-300">
          Dashboard
        </router-link>
        <router-link to="/terminal" class="flex items-center px-4 py-2 rounded hover:bg-gray-200 dark:hover:bg-gray-700 transition-colors" active-class="bg-blue-100 dark:bg-blue-900 text-blue-600 dark:text-blue-300">
          Terminal
        </router-link>
        <router-link to="/files" class="flex items-center px-4 py-2 rounded hover:bg-gray-200 dark:hover:bg-gray-700 transition-colors" active-class="bg-blue-100 dark:bg-blue-900 text-blue-600 dark:text-blue-300">
          Files
        </router-link>
      </nav>
      <div class="p-4 border-t dark:border-gray-700">
        <button @click="disconnect" class="w-full px-4 py-2 text-white bg-red-600 rounded hover:bg-red-700 transition-colors shadow-sm">Disconnect</button>
      </div>
    </aside>

    <!-- Main Content -->
    <main class="flex-1 overflow-auto bg-gray-50 dark:bg-gray-900">
      <div class="p-6 h-full">
        <router-view v-slot="{ Component }">
          <transition name="fade" mode="out-in">
            <component :is="Component" />
          </transition>
        </router-view>
      </div>
    </main>
  </div>
</template>

<script setup lang="ts">
import { useSshStore } from './stores/ssh'
import { useRouter } from 'vue-router'

const sshStore = useSshStore()
const router = useRouter()

function disconnect() {
  sshStore.clearSession()
  router.push('/')
}
</script>

<style>
.fade-enter-active,
.fade-leave-active {
  transition: opacity 0.2s ease;
}

.fade-enter-from,
.fade-leave-to {
  opacity: 0;
}
</style>
