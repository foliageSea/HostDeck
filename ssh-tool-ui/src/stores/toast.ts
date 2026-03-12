import { defineStore } from 'pinia'
import { toast } from '@/components/ui/toast/use-toast'

export const useToastStore = defineStore('toast', () => {
  const success = (message: string) => {
    toast({
      title: 'Success',
      description: message,
      class: 'bg-green-500 text-white border-none'
    })
  }

  const error = (message: string) => {
    toast({
      title: 'Error',
      description: message,
      variant: 'destructive',
    })
  }

  const info = (message: string) => {
    toast({
      title: 'Info',
      description: message,
    })
  }

  const warning = (message: string) => {
    toast({
      title: 'Warning',
      description: message,
      class: 'bg-yellow-500 text-white border-none'
    })
  }

  return { success, error, info, warning }
})
