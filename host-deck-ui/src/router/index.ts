import { createRouter, createWebHistory } from 'vue-router'
import { useSshStore } from '@/stores/ssh'
import DashboardView from '@/views/Dashboard/index.vue'
import FilesView from '@/views/Files/index.vue'
import PortForwardView from '@/views/PortForward/index.vue'
import RuntimeSessionsView from '@/views/RuntimeSessions/index.vue'
import TerminalView from '@/views/Terminal/index.vue'

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
    {
      path: '/runtime-sessions',
      name: 'runtime-sessions',
      component: RuntimeSessionsView,
      meta: { requiresAuth: true },
    },
    {
      path: '/port-forward',
      name: 'port-forward',
      component: PortForwardView,
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
