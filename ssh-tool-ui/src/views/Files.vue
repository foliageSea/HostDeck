<template>
  <div class="h-full flex flex-col bg-gray-50 text-sm font-sans">
    <!-- Toolbar -->
    <div class="h-10 bg-gray-100 border-b border-gray-200 flex items-center px-2 space-x-2">
      <button @click="navigate('..')" class="p-1 hover:bg-gray-200 rounded disabled:opacity-50" :disabled="currentPath === '/' || currentPath === '.'">
        <span class="text-gray-600 flex items-center"><ArrowUp class="w-4 h-4 mr-1"/> 上级目录</span>
      </button>
      <div class="flex-1 px-2 py-1 bg-white border border-gray-300 rounded text-gray-700 truncate select-all">
        {{ currentPath }}
      </div>
      <button @click="fetchFiles" class="p-1 hover:bg-gray-200 rounded">
        <RefreshCcw class="w-4 h-4 text-gray-600"/>
      </button>
    </div>

    <!-- Content -->
    <div class="flex-1 overflow-auto bg-white">
      <table class="w-full text-left border-collapse">
        <thead class="bg-gray-50 sticky top-0 z-10 border-b border-gray-200 text-xs text-gray-500 uppercase tracking-wider">
          <tr>
            <th class="p-2 font-medium w-8"></th>
            <th class="p-2 font-medium">名称</th>
            <th class="p-2 font-medium w-24 text-right">大小</th>
            <th class="p-2 font-medium w-32 text-right">修改日期</th>
            <th class="p-2 font-medium w-16 text-center"></th>
          </tr>
        </thead>
        <tbody class="text-gray-700">
          <tr 
            v-if="files.length === 0" 
            class="text-center text-gray-400 py-8"
          >
            <td colspan="5" class="p-8">暂无文件</td>
          </tr>
          <tr 
            v-for="file in files" 
            :key="file.filename" 
            class="hover:bg-blue-50 cursor-pointer group transition-colors border-b border-gray-50"
            @dblclick="handleItemClick(file)"
          >
            <td class="p-2 text-center text-lg">
              <Folder v-if="file.isDirectory" class="w-5 h-5 text-blue-500 inline-block" />
              <File v-else class="w-5 h-5 text-gray-500 inline-block" />
            </td>
            <td class="p-2 font-medium truncate max-w-[200px]" :title="file.filename">
              {{ file.filename }}
            </td>
            <td class="p-2 text-right text-xs text-gray-500 font-mono">
              {{ file.isDirectory ? '--' : formatSize(file.size) }}
            </td>
            <td class="p-2 text-right text-xs text-gray-500 whitespace-nowrap">
              {{ new Date(file.mtime * 1000).toLocaleDateString() }}
            </td>
             <td class="p-2 text-center">
              <button 
                @click.stop="deleteFile(file.filename)" 
                class="opacity-0 group-hover:opacity-100 text-red-500 hover:text-red-700 p-1 rounded hover:bg-red-50 transition-all"
                title="删除"
              >
                <Trash2 class="w-4 h-4" />
              </button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    
    <!-- Status Bar -->
    <div class="h-6 bg-gray-100 border-t border-gray-200 flex items-center px-2 text-xs text-gray-500">
      {{ files.length }} 项
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted, watch } from 'vue';
import { useSshStore } from '../stores/ssh';
import { ArrowUp, RefreshCcw, Folder, File, Trash2 } from 'lucide-vue-next';

const props = defineProps<{
  windowId?: string
}>();

const sshStore = useSshStore();
const currentPath = ref('.');
const files = ref<any[]>([]);

// Watch for path changes if we add navigation history later
watch(currentPath, () => {
  fetchFiles();
});

async function fetchFiles() {
  if (!sshStore.sessionId) return;
  try {
    const res = await fetch(`/api/files/list?sessionId=${sshStore.sessionId}&path=${encodeURIComponent(currentPath.value)}`);
    if (res.ok) {
      const data = await res.json();
      files.value = data.sort((a: any, b: any) => {
        if (a.isDirectory === b.isDirectory) {
          return a.filename.localeCompare(b.filename);
        }
        return a.isDirectory ? -1 : 1;
      });
    }
  } catch (e) {
    console.error(e);
  }
}

function handleItemClick(file: any) {
  if (file.isDirectory) {
    navigate(file.filename);
  } else {
    // Open editor logic (future)
    // alert('Open file: ' + file.filename);
  }
}

function navigate(dir: string) {
  if (dir === '..') {
    if (currentPath.value === '.' || currentPath.value === '/') return;
    const parts = currentPath.value.split('/');
    parts.pop();
    currentPath.value = parts.join('/') || '/'; // Fix root handling
  } else {
    if (currentPath.value === '.' || currentPath.value === '/') {
        // If current is root, just append dir (avoid //)
        currentPath.value = currentPath.value === '/' ? `/${dir}` : dir;
    } else {
      currentPath.value = `${currentPath.value}/${dir}`;
    }
  }
  // fetchFiles called by watcher
}

async function deleteFile(filename: string) {
  if (!confirm(`Are you sure you want to delete "${filename}"?`)) return;
  if (!sshStore.sessionId) return;
  
  const fullPath = currentPath.value === '.' ? filename : `${currentPath.value}/${filename}`;
  try {
    const res = await fetch(`/api/files/delete?sessionId=${sshStore.sessionId}&path=${encodeURIComponent(fullPath)}`, { method: 'POST' });
    if (res.ok) {
      fetchFiles();
    } else {
      alert('Delete failed');
    }
  } catch (e) {
    alert('Error: ' + e);
  }
}

function formatSize(bytes: number) {
  if (bytes === 0) return '0 B';
  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + ' ' + sizes[i];
}

onMounted(() => {
  if (sshStore.isConnected) {
    fetchFiles();
  }
});
</script>
