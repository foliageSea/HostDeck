<script setup lang="ts">
withDefaults(
  defineProps<{
    minWidth?: string
  }>(),
  {
    minWidth: '900px',
  },
)
</script>

<template>
  <div class="docker-table-shell">
    <div class="docker-table-scroll app-scrollbar app-scrollbar-compact">
      <NTable
        class="docker-resource-table"
        size="small"
        striped
        :bordered="false"
        :single-line="false"
        :style="{ minWidth }"
      >
        <slot />
      </NTable>
    </div>
    <div v-if="$slots.footer" class="docker-table-footer">
      <slot name="footer" />
    </div>
  </div>
</template>

<style scoped>
.docker-table-shell {
  display: flex;
  flex: 1;
  min-height: 0;
  flex-direction: column;
  overflow: hidden;
  border: 1px solid var(--docker-tab-card-border, rgba(148, 163, 184, 0.2));
  border-radius: 0;
}

.docker-table-scroll {
  flex: 1;
  min-height: 0;
  overflow: auto;
}

.docker-resource-table {
  width: 100%;
  table-layout: fixed;
}

.docker-resource-table :deep(th) {
  position: sticky;
  top: 0;
  z-index: 2;
  white-space: nowrap;
}

.docker-resource-table :deep(td) {
  vertical-align: middle;
}

.docker-resource-table :deep(.docker-table-nowrap) {
  white-space: nowrap;
}

.docker-resource-table :deep(th.docker-table-actions-column),
.docker-resource-table :deep(td.docker-table-actions-column) {
  position: sticky;
  right: 0;
  z-index: 1;
  background: var(--n-td-color);
  box-shadow: -8px 0 12px -12px rgba(15, 23, 42, 0.48);
}

.docker-resource-table :deep(th.docker-table-actions-column) {
  z-index: 3;
  background: var(--n-th-color);
}

.docker-resource-table :deep(tr:nth-of-type(even) td.docker-table-actions-column) {
  background: var(--n-td-color-striped);
}

.docker-resource-table :deep(.docker-table-primary),
.docker-resource-table :deep(.docker-table-secondary) {
  display: block;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.docker-resource-table :deep(.docker-table-primary) {
  font-weight: 600;
}

.docker-resource-table :deep(.docker-table-secondary) {
  margin-top: 3px;
  opacity: 0.62;
  font-size: 12px;
}

.docker-resource-table :deep(.docker-table-tags),
.docker-resource-table :deep(.docker-table-actions) {
  display: flex;
  min-width: 0;
  flex-wrap: wrap;
  align-items: center;
  gap: 4px;
}

.docker-resource-table :deep(.docker-table-tags) {
  overflow: hidden;
}

.docker-resource-table :deep(.docker-table-tags .n-tag) {
  max-width: 100%;
  min-width: 0;
}

.docker-resource-table :deep(.docker-table-tags .n-tag__content) {
  display: block;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.docker-resource-table :deep(.docker-table-actions) {
  flex-wrap: nowrap;
  justify-content: flex-end;
}

.docker-resource-table :deep(.docker-table-status) {
  display: block;
  min-width: 0;
  overflow: hidden;
}

.docker-resource-table :deep(.docker-table-status .n-tag) {
  max-width: 100%;
  overflow: hidden;
}

.docker-resource-table :deep(.docker-table-status .n-tag__content) {
  display: block;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.docker-table-footer {
  display: flex;
  flex: none;
  justify-content: flex-end;
  border-top: 1px solid var(--docker-tab-card-border, rgba(148, 163, 184, 0.2));
  padding: 8px;
}
</style>
