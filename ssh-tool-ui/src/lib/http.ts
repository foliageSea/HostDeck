import axios from 'axios'
import { useSshStore } from '../stores/ssh'
import { toast } from '@/components/ui/toast/use-toast'

export const http = axios.create({
  baseURL: '/', // Use relative paths to match current behavior
})

let isRedirecting = false

http.interceptors.response.use(
  (response) => response,
  async (error) => {
    if (error.response && error.response.status === 404) {
      const url = error.config.url
      if (url && url.includes('/api/')) {
        const data = error.response.data
        // Backend returns plain text for "Session not found" usually
        const message = typeof data === 'string' ? data : JSON.stringify(data)
        
        if (message.includes('Session not found')) {
             if (!isRedirecting) {
                 // Access store directly - Pinia should be active when requests happen
                 const sshStore = useSshStore() 
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
        }
      }
    }
    return Promise.reject(error)
  }
)
