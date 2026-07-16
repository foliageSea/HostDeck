<script lang="ts">
import { defineComponent, h } from 'vue'
import { NButton } from 'naive-ui'

export default defineComponent({
  name: 'RoundedButton',
  inheritAttrs: false,
  setup(_, { attrs, slots }) {
    return () => h(NButton, { ...attrs, round: true }, slots)
  },
})
</script>
