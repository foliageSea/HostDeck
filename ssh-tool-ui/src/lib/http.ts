import axios, { AxiosError } from 'axios'
import { useSshStore } from '../stores/ssh'
import { toast } from '@/components/ui/toast/use-toast'

export const http = axios.create({
  baseURL: '/', // Use relative paths to match current behavior
})

interface ApiError {
  code?: string | number
  message?: string
}

let isRedirecting = false

const handleSessionError = () => {
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

http.interceptors.response.use(
  (response) => {
    // Check for Unified Result structure
    const data = response.data
    // Check if data has code (number) and message
    if (data && typeof data === 'object' && 'code' in data && typeof data.code === 'number') {
      if (data.code === 200) {
        // Unwrap success data, making it transparent to the caller
        // If data.data is undefined (e.g. void return), response.data becomes undefined, which is fine
        response.data = data.data
        return response
      }

      // Handle business error from Unified Result (HTTP 200 but code != 200)
      const errorCode = data.code
      const errorMessage = data.message || 'Unknown error'

      // Check for session errors
      // Code 404: Session not found (from our new backend logic)
      // Code 500: Connection lost (SSHChannelOpenError/SocketException)
      const isSessionError =
        (errorCode === 500 && (errorMessage.includes('SSHChannelOpenError') || errorMessage.includes('SocketException')))

      if (isSessionError) {
        handleSessionError()
      }

      // Create AxiosError to propagate to catch blocks
      const error = new AxiosError(
        errorMessage,
        String(errorCode),
        response.config,
        response.request,
        response
      )
      return Promise.reject(error)
    }

    // For non-unified results (e.g. blobs, streams, or legacy responses), return as is
    return response
  },
  async (error: AxiosError<ApiError | string>) => {
    // Handle standard HTTP errors (non-2xx status)
    // This is still needed for stream endpoints (readFile/batchDownload) which return 500 on error
    if (error.response) {
      const { status, data, config } = error.response
      const url = config?.url

      if (url && url.includes('/api/')) {
        let errorCode: string | number = ''
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

        // Check for session errors (Legacy/Stream logic)
        const isSessionError =
          (status === 500 && (errorMessage.includes('SSHChannelOpenError') || errorMessage.includes('SocketException')))

        if (isSessionError) {
          handleSessionError()
        }
      }
    }
    return Promise.reject(error)
  }
)
