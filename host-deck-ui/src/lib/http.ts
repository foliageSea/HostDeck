import { useSshStore } from '@/stores/ssh'
import axios, { AxiosError } from 'axios'
import { getUiApi } from './ui'

interface ApiError {
  code?: number | string
  message?: string
}

export const http = axios.create({
  baseURL: '/',
})

let isHandlingSessionError = false

function handleSessionError(message = 'SSH 会话已失效，请重新连接。') {
  if (isHandlingSessionError) {
    return
  }

  const sshStore = useSshStore()
  if (!sshStore.isConnected) {
    return
  }

  isHandlingSessionError = true
  getUiApi().message.error(message)
  sshStore.clearSession()

  window.setTimeout(() => {
    isHandlingSessionError = false
  }, 2000)
}

http.interceptors.response.use(
  (response) => {
    const data = response.data

    if (data && typeof data === 'object' && 'code' in data && typeof data.code === 'number') {
      if (data.code === 200) {
        response.data = data.data
        return response
      }

      const errorCode = data.code
      const errorMessage = data.message || 'Unknown error'
      const isSessionError =
        errorCode === 500 &&
        (errorMessage.includes('SSHChannelOpenError') || errorMessage.includes('SocketException'))

      if (isSessionError) {
        handleSessionError()
      }

      const error = new AxiosError(
        errorMessage,
        String(errorCode),
        response.config,
        response.request,
        response,
      )

      return Promise.reject(error)
    }

    return response
  },
  async (error: AxiosError<ApiError | string>) => {
    if (error.response) {
      const { status, data, config } = error.response
      const url = config?.url

      if (url && url.includes('/api/')) {
        let errorMessage = ''

        if (typeof data === 'string') {
          errorMessage = data

          try {
            const parsed = JSON.parse(data)
            if (parsed.message) {
              errorMessage = parsed.message
            }
          } catch {
            // Keep original text.
          }
        } else if (typeof data === 'object' && data !== null) {
          errorMessage = data.message || JSON.stringify(data)
        }

        const isSessionError =
          status === 500 &&
          (errorMessage.includes('SSHChannelOpenError') || errorMessage.includes('SocketException'))

        if (isSessionError) {
          handleSessionError()
        }
      }
    }

    return Promise.reject(error)
  },
)
