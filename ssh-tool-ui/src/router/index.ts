import { createRouter, createWebHistory } from 'vue-router'
import Dashboard from '../views/Dashboard.vue'
import Terminal from '../views/Terminal.vue'
import Files from '../views/Files.vue'
import { useSshStore } from '../stores/ssh'

const router = createRouter({
  history: createWebHistory(import.meta.env.BASE_URL),
  routes: [
    {
      path: '/dashboard',
      name: 'dashboard',
      component: Dashboard,
      meta: { requiresAuth: true }
    },
    {
      path: '/terminal',
      name: 'terminal',
      component: Terminal,
      meta: { requiresAuth: true }
    },
    {
      path: '/files',
      name: 'files',
      component: Files,
      meta: { requiresAuth: true }
    }
  ]
})

router.beforeEach((to, _from, next) => {
  const sshStore = useSshStore()
  if (to.meta.requiresAuth && !sshStore.isConnected) {
    next('/')
  } else {
    next()
  }
})

export default router
