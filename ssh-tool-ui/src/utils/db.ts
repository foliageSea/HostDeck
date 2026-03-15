
const DB_NAME = 'ssh-tool-db';
const STORE_NAME = 'background-store';
const VIDEO_KEY = 'custom-bg-video';

interface VideoRecord {
  id: string;
  blob: Blob;
}

export const db = {
  async open(): Promise<IDBDatabase> {
    return new Promise((resolve, reject) => {
      const request = indexedDB.open(DB_NAME, 1);

      request.onerror = () => reject(request.error);
      request.onsuccess = () => resolve(request.result);

      request.onupgradeneeded = (event) => {
        const db = (event.target as IDBOpenDBRequest).result;
        if (!db.objectStoreNames.contains(STORE_NAME)) {
          db.createObjectStore(STORE_NAME, { keyPath: 'id' });
        }
      };
    });
  },

  async saveVideo(blob: Blob): Promise<void> {
    const database = await this.open();
    return new Promise((resolve, reject) => {
      const transaction = database.transaction([STORE_NAME], 'readwrite');
      const store = transaction.objectStore(STORE_NAME);
      
      const record: VideoRecord = {
        id: VIDEO_KEY,
        blob
      };

      const request = store.put(record);
      
      request.onerror = () => reject(request.error);
      request.onsuccess = () => resolve();
    });
  },

  async getVideo(): Promise<Blob | null> {
    const database = await this.open();
    return new Promise((resolve, reject) => {
      const transaction = database.transaction([STORE_NAME], 'readonly');
      const store = transaction.objectStore(STORE_NAME);
      const request = store.get(VIDEO_KEY);

      request.onerror = () => reject(request.error);
      request.onsuccess = () => {
        const result = request.result as VideoRecord | undefined;
        resolve(result ? result.blob : null);
      };
    });
  },

  async deleteVideo(): Promise<void> {
    const database = await this.open();
    return new Promise((resolve, reject) => {
      const transaction = database.transaction([STORE_NAME], 'readwrite');
      const store = transaction.objectStore(STORE_NAME);
      const request = store.delete(VIDEO_KEY);

      request.onerror = () => reject(request.error);
      request.onsuccess = () => resolve();
    });
  }
};
