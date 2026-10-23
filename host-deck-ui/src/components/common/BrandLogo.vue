<script setup lang="ts">
withDefaults(defineProps<{ size?: number }>(), { size: 40 })
</script>

<template>
  <svg
    class="brand-logo"
    :width="size"
    :height="size"
    viewBox="0 0 512 512"
    role="img"
    aria-label="HostDeck"
  >
    <rect class="brand-logo__tile" width="512" height="512" rx="112" />
    <g transform="translate(256 256) skewX(-20) translate(-256 -256)">
      <rect class="brand-logo__mark" x="120" y="126" width="272" height="70" rx="26" />
      <rect class="brand-logo__mark" x="120" y="221" width="272" height="70" rx="26" />
      <rect class="brand-logo__mark" x="120" y="316" width="272" height="70" rx="26" />
      <rect class="brand-logo__slot" x="156" y="152" width="88" height="20" rx="10" />
      <rect class="brand-logo__slot" x="156" y="247" width="88" height="20" rx="10" />
      <rect class="brand-logo__slot" x="156" y="342" width="88" height="20" rx="10" />
    </g>
    <rect class="brand-logo__ring" width="512" height="512" rx="112" />
  </svg>
</template>

<style scoped>
.brand-logo {
  display: block;
  flex: none;
}

.brand-logo__tile {
  fill: var(--brand-logo-tile, #ffffff);
}

.brand-logo__mark {
  fill: var(--brand-logo-mark, #000000);
}

.brand-logo__slot {
  fill: var(--brand-logo-tile, #ffffff);
}

.brand-logo__ring {
  fill: none;
  stroke: var(--brand-logo-tile-stroke, transparent);
  stroke-width: 16;
}
</style>
