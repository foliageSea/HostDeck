<template>
  <div class="h-full flex flex-col p-4">
    <div class="flex justify-between items-center mb-4">
      <h1 class="text-xl font-bold">Files: {{ currentPath }}</h1>
      <button @click="fetchFiles" class="px-3 py-1 bg-blue-600 text-white rounded hover:bg-blue-700 transition-colors">Refresh</button>
    </div>
    
    <div class="flex-1 overflow-auto border rounded bg-white dark:bg-gray-800 shadow-sm">
      <table class="w-full text-left border-collapse">
        <thead class="bg-gray-100 dark:bg-gray-700 sticky top-0">
          <tr>
            <th class="p-3 border-b dark:border-gray-600 font-semibold">Name</th>
            <th class="p-3 border-b dark:border-gray-600 font-semibold w-24">Size</th>
            <th class="p-3 border-b dark:border-gray-600 font-semibold w-48">Modified</th>
            <th class="p-3 border-b dark:border-gray-600 font-semibold w-20">Actions</th>
          </tr>
        </thead>
        <tbody>
          <tr v-if="currentPath !== '.' && currentPath !== '/'" @click="navigate('..')" class="cursor-pointer hover:bg-gray-50 dark:hover:bg-gray-700 transition-colors">
            <td class="p-3 border-b dark:border-gray-700 font-medium text-blue-600 dark:text-blue-400" colspan="4">..</td>
          </tr>
          <tr v-for="file in files" :key="file.filename" class="border-b dark:border-gray-700 hover:bg-gray-50 dark:hover:bg-gray-700 transition-colors">
            <td class="p-3 cursor-pointer flex items-center" @click="handleItemClick(file)">
              <span v-if="file.isDirectory" class="mr-2 text-yellow-500">📁</span>
              <span v-else class="mr-2 text-gray-500">📄</span>
              {{ file.filename }}
            </td>
            <td class="p-3 text-sm text-gray-600 dark:text-gray-400">{{ file.isDirectory ? '-' : formatSize(file.size) }}</td>
            <td class="p-3 text-sm text-gray-600 dark:text-gray-400">{{ new Date(file.mtime * 1000).toLocaleString() }}</td>
            <td class="p-3">
              <button @click.stop="deleteFile(file.filename)" class="text-red-500 hover:text-red-700 transition-colors text-sm font-medium">Delete</button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { useSshStore } from '../stores/ssh'

const sshStore = useSshStore()
const currentPath = ref('.')
const files = ref<any[]>([])

async function fetchFiles() {
  if (!sshStore.sessionId) return
  try {
    const res = await fetch(`/api/files/list?sessionId=${sshStore.sessionId}&path=${encodeURIComponent(currentPath.value)}`)
    if (res.ok) {
      const data = await res.json()
      // Sort: Directories first, then files
      files.value = data.sort((a: any, b: any) => {
        if (a.isDirectory === b.isDirectory) {
          return a.filename.localeCompare(b.filename)
        }
        return a.isDirectory ? -1 : 1
      })
    }
  } catch (e) {
    console.error(e)
  }
}

function handleItemClick(file: any) {
  if (file.isDirectory) {
    navigate(file.filename)
  } else {
    // Open editor logic (future)
    alert('Open file: ' + file.filename)
  }
}

function navigate(dir: string) {
  if (dir === '..') {
    if (currentPath.value === '.') return
    const parts = currentPath.value.split('/')
    parts.pop()
    currentPath.value = parts.join('/') || '.'
  } else {
    if (currentPath.value === '.') {
      currentPath.value = dir
    } else {
      currentPath.value = `${currentPath.value}/${dir}`
    }
  }
  fetchFiles()
}

async function deleteFile(filename: string) {
  if (!confirm(`Delete ${filename}?`)) return
  if (!sshStore.sessionId) return
  
  const fullPath = currentPath.value === '.' ? filename : `${currentPath.value}/${filename}`
  try {
    const res = await fetch(`/api/files/delete?sessionId=${sshStore.sessionId}&path=${encodeURIComponent(fullPath)}`, { method: 'POST' })
    if (res.ok) {
      fetchFiles()
    } else {
      alert('Delete failed')
    }
  } catch (e) {
    alert('Error: ' + e)
  }
}

function formatSize(bytes: number) {
  if (bytes === 0) return '0 B'
  const k = 1024
  const sizes = ['B', 'KB', 'MB', 'GB']
  const i = Math.floor(Math.log(bytes) / Math.log(k))
  return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i]
}

onMounted(() => {
  fetchFiles()
})
</script>
