import { useSshStore } from '../stores/ssh'
import { toast } from '@/components/ui/toast/use-toast'
import type { Pinia } from 'pinia'

let isRedirecting = false

export function setupFetchInterceptor(pinia: Pinia) {
  const originalFetch = window.fetch
  
  window.fetch = async (...args) => {
    const response = await originalFetch(...args)
    
    if (response.status === 404 && !isRedirecting) {
      const url = typeof args[0] === 'string' 
        ? args[0] 
        : (args[0] instanceof Request ? args[0].url : args[0].toString())
        
      if (url.includes('/api/')) {
        try {
          const cloned = response.clone()
          const text = await cloned.text()
          
          if (text.includes('Session not found')) {
            const sshStore = useSshStore(pinia)
            if (sshStore.isConnected) {
              isRedirecting = true
              toast({
                title: '会话已断开',
                description: 'SSH会话已失效，请重新登录。',
                variant: 'destructive',
              })
              sshStore.clearSession()
              
              setTimeout(() => {
                isRedirecting = false
              }, 2000)
            }
          }
        } catch (e) {
          console.error('Failed to parse response in fetch interceptor:', e)
        }
      }
    }
    
    return response
  }
}
