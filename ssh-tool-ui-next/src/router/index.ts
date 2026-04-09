import { createRouter, createWebHistory } from 'vue-router'
import { useSshStore } from '@/stores/ssh'
import DashboardView from '@/views/DashboardView.vue'
import FilesView from '@/views/FilesView.vue'
import TerminalView from '@/views/TerminalView.vue'

const router = createRouter({
  history: createWebHistory(import.meta.env.BASE_URL),
  routes: [
    {
      path: '/',
      redirect: '/dashboard',
    },
    {
      path: '/dashboard',
      name: 'dashboard',
      component: DashboardView,
      meta: { requiresAuth: true },
    },
    {
      path: '/terminal',
      name: 'terminal',
      component: TerminalView,
      meta: { requiresAuth: true },
    },
    {
      path: '/files',
      name: 'files',
      component: FilesView,
      meta: { requiresAuth: true },
    },
  ],
})

router.beforeEach((to) => {
  const sshStore = useSshStore()

  if (to.meta.requiresAuth && !sshStore.isConnected) {
    return false
  }

  return true
})

export default router
