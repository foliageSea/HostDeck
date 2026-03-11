<template>
  <div class="p-6">
    <h1 class="text-2xl font-bold mb-6">System Dashboard</h1>
    
    <div class="grid grid-cols-1 md:grid-cols-3 gap-6 mb-8">
      <!-- CPU Card -->
      <div class="bg-white dark:bg-gray-800 p-6 rounded-lg shadow-sm border dark:border-gray-700">
        <h3 class="text-gray-500 text-sm font-medium uppercase tracking-wider mb-2">CPU Load</h3>
        <div class="text-3xl font-bold text-blue-600">{{ cpuLoad }}</div>
        <div class="text-sm text-gray-400 mt-2">Load Average</div>
      </div>
      
      <!-- RAM Card -->
      <div class="bg-white dark:bg-gray-800 p-6 rounded-lg shadow-sm border dark:border-gray-700">
        <h3 class="text-gray-500 text-sm font-medium uppercase tracking-wider mb-2">RAM Usage</h3>
        <div class="text-3xl font-bold text-green-600">{{ ramUsage }}%</div>
        <div class="text-sm text-gray-400 mt-2">{{ ramDetails }}</div>
      </div>
      
      <!-- Disk Card -->
      <div class="bg-white dark:bg-gray-800 p-6 rounded-lg shadow-sm border dark:border-gray-700">
        <h3 class="text-gray-500 text-sm font-medium uppercase tracking-wider mb-2">Disk Usage (/)</h3>
        <div class="text-3xl font-bold text-purple-600">{{ diskUsage }}</div>
        <div class="text-sm text-gray-400 mt-2">Root Partition</div>
      </div>
    </div>
    
    <!-- Chart placeholder -->
    <div class="bg-white dark:bg-gray-800 p-6 rounded-lg shadow-sm border dark:border-gray-700 h-64 flex items-center justify-center">
      <span class="text-gray-400">Real-time charts coming soon (ECharts integration)</span>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted, onUnmounted } from 'vue'
import { useSshStore } from '../stores/ssh'

const sshStore = useSshStore()
const cpuLoad = ref('0.0')
const ramUsage = ref(0)
const ramDetails = ref('0 / 0 MB')
const diskUsage = ref('0%')
let interval: any = null

async function fetchData() {
  if (!sshStore.sessionId) return
  try {
    const res = await fetch(`/api/monitor?sessionId=${sshStore.sessionId}`)
    if (res.ok) {
      const data = await res.json()
      cpuLoad.value = data.cpu
      diskUsage.value = data.disk
      
      const total = data.ram.total
      const used = data.ram.used
      ramUsage.value = total > 0 ? Math.round((used / total) * 100) : 0
      ramDetails.value = `${used} / ${total} MB`
    }
  } catch (e) {
    console.error(e)
  }
}

onMounted(() => {
  fetchData()
  interval = setInterval(fetchData, 3000)
})

onUnmounted(() => {
  if (interval) clearInterval(interval)
})
</script>
