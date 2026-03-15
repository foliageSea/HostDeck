import axios, { AxiosError } from 'axios'
import { useSshStore } from '../stores/ssh'
import { toast } from '@/components/ui/toast/use-toast'

export const http = axios.create({
  baseURL: '/', // Use relative paths to match current behavior
})

interface ApiError {
  code?: string
  message?: string
}

let isRedirecting = false

http.interceptors.response.use(
  (response) => response,
  async (error: AxiosError<ApiError | string>) => {
    if (error.response) {
      const { status, data, config } = error.response
      const url = config?.url

      if (url && url.includes('/api/')) {
        let errorCode = ''
        let errorMessage = ''

        if (typeof data === 'string') {
          errorMessage = data
          try {
            const parsed = JSON.parse(data)
            if (parsed.code) errorCode = parsed.code
            if (parsed.message) errorMessage = parsed.message
          } catch {
            // Ignore parse error
          }
        } else if (typeof data === 'object' && data !== null) {
          errorCode = (data as ApiError).code || ''
          errorMessage = (data as ApiError).message || JSON.stringify(data)
        }

        // Check for session errors:
        // 1. 404 SESSION_NOT_FOUND (Structured) or "Session not found" (Legacy)
        // 2. 500 SSHChannelOpenError (Connection lost) or SocketException
        const isSessionError =
          (status === 404 && (errorCode === 'SESSION_NOT_FOUND' || errorMessage.includes('Session not found'))) ||
          (status === 500 && (errorMessage.includes('SSHChannelOpenError') || errorMessage.includes('SocketException')))

        if (isSessionError) {
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
