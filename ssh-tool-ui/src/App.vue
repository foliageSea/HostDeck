<template>
  <div class="h-screen w-screen overflow-hidden font-sans select-none">
    <Transition name="fade" mode="out-in">
      <Desktop v-if="sshStore.isConnected" />
      <LoginScreen v-else />
    </Transition>
    <Toaster />
    <SonnerToaster position="top-right" richColors />
  </div>
</template>

<script setup lang="ts">
import { useSshStore } from './stores/ssh';
import { useSettingsStore } from './stores/settings';
import Desktop from './components/os/Desktop.vue';
import LoginScreen from './components/os/LoginScreen.vue';
import Toaster from '@/components/ui/toast/Toaster.vue';
import { Toaster as SonnerToaster } from 'vue-sonner';

const sshStore = useSshStore();
useSettingsStore(); // Initialize settings store to apply theme
</script>

<style>
.fade-enter-active,
.fade-leave-active {
  transition: opacity 0.5s ease;
}

.fade-enter-from,
.fade-leave-to {
  opacity: 0;
}
</style>
