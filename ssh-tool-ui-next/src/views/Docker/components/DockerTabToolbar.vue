<template>
  <div class="docker-tab-toolbar">
    <div class="docker-tab-toolbar__main">
      <div v-if="$slots.left" class="docker-tab-toolbar__left">
        <slot name="left" />
      </div>

      <div v-if="$slots.actions" class="docker-tab-toolbar__actions">
        <slot name="actions" />
      </div>
    </div>

    <div v-if="$slots.meta" class="docker-tab-toolbar__meta">
      <slot name="meta" />
    </div>
  </div>
</template>

<style scoped>
.docker-tab-toolbar {
  display: flex;
  flex: none;
  flex-direction: column;
  gap: 10px;
  padding: 8px 0 12px;
}

.docker-tab-toolbar__main {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: space-between;
  gap: 10px 12px;
}

.docker-tab-toolbar__left,
.docker-tab-toolbar__actions,
.docker-tab-toolbar__meta {
  display: flex;
  min-width: 0;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px;
}

.docker-tab-toolbar__actions {
  margin-left: auto;
  justify-content: flex-end;
}

.docker-tab-toolbar__meta {
  color: rgba(100, 116, 139, 0.82);
  font-size: 12px;
}

@media (max-width: 640px) {
  .docker-tab-toolbar__left,
  .docker-tab-toolbar__actions {
    width: 100%;
  }

  .docker-tab-toolbar__actions {
    margin-left: 0;
    justify-content: flex-start;
  }
}
</style>
