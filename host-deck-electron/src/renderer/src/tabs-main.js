import { createApp, h } from 'vue'
import { darkTheme, NConfigProvider, NDialogProvider } from 'naive-ui'

import TabsShell from './views/TabsShell.vue'

createApp({
  render: () =>
    h(
      NConfigProvider,
      { theme: darkTheme },
      {
        default: () => h(NDialogProvider, null, { default: () => h(TabsShell) })
      }
    )
}).mount('#app')
