<template>
  <div class="h-screen w-screen overflow-hidden font-sans select-none">
    <Transition name="fade" mode="out-in">
      <Desktop v-if="sshStore.isConnected" />
      <LoginScreen v-else />
    </Transition>
    <Toast />
  </div>
</template>

<script setup lang="ts">
import { useSshStore } from './stores/ssh';
import Desktop from './components/os/Desktop.vue';
import LoginScreen from './components/os/LoginScreen.vue';
import Toast from './components/ui/Toast.vue';

const sshStore = useSshStore();
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
