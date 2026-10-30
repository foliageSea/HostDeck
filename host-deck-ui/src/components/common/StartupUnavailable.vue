<script setup lang="ts">
function retry() {
  window.location.reload()
}
</script>

<template>
  <main class="startup-unavailable">
    <img src="/pwa-192x192.png" alt="HostDeck" width="72" height="72" />
    <h1>无法连接到 HostDeck 服务</h1>
    <p>请检查网络和服务状态后重试。</p>
    <button type="button" @click="retry">重新连接</button>
  </main>
</template>

<style scoped>
.startup-unavailable {
  min-height: 100vh;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 16px;
  padding: 24px;
  box-sizing: border-box;
  background: #f5f5f7;
  color: #1d1d1f;
  text-align: center;
}

h1 {
  margin: 0;
  font-size: 22px;
}

p {
  margin: 0;
  color: #6e6e73;
}

button {
  border: 0;
  border-radius: 20px;
  padding: 10px 24px;
  background: #1d1d1f;
  color: #fff;
  font: inherit;
  cursor: pointer;
}

@media (prefers-color-scheme: dark) {
  .startup-unavailable {
    background: #1d1d1f;
    color: #f5f5f7;
  }

  p {
    color: #a1a1a6;
  }

  button {
    background: #f5f5f7;
    color: #1d1d1f;
  }
}
</style>
