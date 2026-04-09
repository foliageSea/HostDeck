import type { DialogApi, LoadingBarApi, MessageApi, NotificationApi } from 'naive-ui'

interface UiApi {
  dialog: DialogApi
  loadingBar: LoadingBarApi
  message: MessageApi
  notification: NotificationApi
}

let uiApi: UiApi | null = null

export function installUiApi(api: UiApi) {
  uiApi = api
}

export function getUiApi(): UiApi {
  if (!uiApi) {
    throw new Error('UI API has not been installed yet.')
  }

  return uiApi
}
