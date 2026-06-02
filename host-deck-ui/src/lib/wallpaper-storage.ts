import type { WallpaperTarget } from '@/lib/wallpapers'

const DB_NAME = 'host-deck-ui'
const STORE_NAME = 'wallpapers'
const DB_VERSION = 1

function openWallpaperDatabase(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const request = window.indexedDB.open(DB_NAME, DB_VERSION)

    request.onerror = () => {
      reject(request.error ?? new Error('Failed to open wallpaper database.'))
    }

    request.onupgradeneeded = () => {
      const database = request.result
      if (!database.objectStoreNames.contains(STORE_NAME)) {
        database.createObjectStore(STORE_NAME)
      }
    }

    request.onsuccess = () => {
      resolve(request.result)
    }
  })
}

function runTransaction<T>(
  mode: IDBTransactionMode,
  runner: (store: IDBObjectStore) => IDBRequest<T>,
): Promise<T> {
  return openWallpaperDatabase().then((database) => new Promise<T>((resolve, reject) => {
    const transaction = database.transaction(STORE_NAME, mode)
    const store = transaction.objectStore(STORE_NAME)
    const request = runner(store)

    request.onerror = () => {
      reject(request.error ?? new Error('Wallpaper storage request failed.'))
    }

    request.onsuccess = () => {
      resolve(request.result)
    }

    transaction.oncomplete = () => {
      database.close()
    }

    transaction.onerror = () => {
      reject(transaction.error ?? new Error('Wallpaper storage transaction failed.'))
      database.close()
    }

    transaction.onabort = () => {
      reject(transaction.error ?? new Error('Wallpaper storage transaction aborted.'))
      database.close()
    }
  }))
}

export function getStoredWallpaperDataUrl(target: WallpaperTarget): Promise<string | null> {
  return runTransaction('readonly', (store) => store.get(target)).then((result) =>
    typeof result === 'string' && result.trim() ? result : null,
  )
}

export function setStoredWallpaperDataUrl(target: WallpaperTarget, dataUrl: string): Promise<void> {
  return runTransaction('readwrite', (store) => store.put(dataUrl, target)).then(() => undefined)
}

export function deleteStoredWallpaperDataUrl(target: WallpaperTarget): Promise<void> {
  return runTransaction('readwrite', (store) => store.delete(target)).then(() => undefined)
}
