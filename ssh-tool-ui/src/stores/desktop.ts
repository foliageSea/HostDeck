import { defineStore } from 'pinia';
import { markRaw, type Component } from 'vue';
import Terminal from '../views/Terminal.vue';
import Files from '../views/Files.vue';
import Dashboard from '../views/Dashboard.vue';
import TextEditor from '../views/TextEditor.vue';
import MediaViewer from '../views/MediaViewer.vue';
import Docker from '../views/Docker.vue';
import { useSshStore } from './ssh';

export interface AppConfig {
  id: string;
  title: string;
  icon: string;
  component: Component;
  width?: number;
  height?: number;
  hide?: boolean;
}

export interface WindowState {
  id: string;
  appId: string;
  title: string;
  component: Component;
  icon: string;
  x: number;
  y: number;
  width: number;
  height: number;
  isMinimized: boolean;
  isMaximized: boolean;
  zIndex: number;
  props?: Record<string, any>;
}

export const useDesktopStore = defineStore('desktop', {
  state: () => ({
    windows: [] as WindowState[],
    activeWindowId: null as string | null,
    nextZIndex: 100,
    apps: {
      'terminal': {
        id: 'terminal',
        title: '终端',
        icon: 'terminal',
        component: markRaw(Terminal),
        width: 800,
        height: 500
      },
      'files': {
        id: 'files',
        title: '文件管理',
        icon: 'folder',
        component: markRaw(Files),
        width: 1000,
        height: 700
      },
      'editor': {
        id: 'editor',
        title: '文本编辑',
        icon: 'file-text',
        component: markRaw(TextEditor),
        width: 800,
        height: 600,
        hide: true
      },
      'media-viewer': {
        id: 'media-viewer',
        title: '媒体预览',
        icon: 'image',
        component: markRaw(MediaViewer),
        width: 1000,
        height: 700,
        hide: true
      },
      'dashboard': {
        id: 'dashboard',
        title: '系统监控',
        icon: 'activity',
        component: markRaw(Dashboard),
        width: 400,
        height: 600,
        hide: true
      },
      'docker': {
        id: 'docker',
        title: 'Docker 管理',
        icon: 'container',
        component: markRaw(Docker),
        width: 1600,
        height: 700
      },
      'logout': {
        id: 'logout',
        title: '断开连接',
        icon: 'lock',
        component: markRaw({ render: () => null }), // Dummy component
        width: 0,
        height: 0
      }
    } as Record<string, AppConfig>,
  }),

  actions: {
    openWindow(appId: string, props?: Record<string, any>) {
      if (appId === 'logout') {
        const sshStore = useSshStore();
        sshStore.clearSession();
        // Clear all windows on logout
        this.windows = [];
        return;
      }

      const app = this.apps[appId];
      if (!app) {
        console.error(`App ${appId} not found`);
        return;
      }

      const id = `${appId}-${Date.now()}`;
      const newWindow: WindowState = {
        id,
        appId,
        title: props?.title || app.title,
        component: app.component,
        icon: app.icon,
        x: 100 + (this.windows.length * 30),
        y: 100 + (this.windows.length * 30),
        width: app.width || 800,
        height: app.height || 600,
        isMinimized: false,
        isMaximized: false,
        zIndex: this.nextZIndex++,
        props
      };

      this.windows.push(newWindow);
      this.focusWindow(id);
    },

    closeWindow(id: string) {
      const index = this.windows.findIndex(w => w.id === id);
      if (index !== -1) {
        this.windows.splice(index, 1);
        if (this.activeWindowId === id) {
          this.activeWindowId = null;
          if (this.windows.length > 0) {
            const topWindow = this.windows.reduce((prev, current) =>
              (prev.zIndex > current.zIndex) ? prev : current
            );
            this.focusWindow(topWindow.id);
          }
        }
      }
    },

    minimizeWindow(id: string) {
      const window = this.windows.find(w => w.id === id);
      if (window) {
        window.isMinimized = true;
        this.activeWindowId = null;
      }
    },

    restoreWindow(id: string) {
      const window = this.windows.find(w => w.id === id);
      if (window) {
        window.isMinimized = false;
        this.focusWindow(id);
      }
    },

    maximizeWindow(id: string) {
      const window = this.windows.find(w => w.id === id);
      if (window) {
        window.isMaximized = !window.isMaximized;
        this.focusWindow(id);
      }
    },

    focusWindow(id: string) {
      const window = this.windows.find(w => w.id === id);
      if (window) {
        if (window.isMinimized) {
          window.isMinimized = false;
        }
        window.zIndex = this.nextZIndex++;
        this.activeWindowId = id;
      }
    },

    updateWindowPosition(id: string, x: number, y: number) {
      const window = this.windows.find(w => w.id === id);
      if (window) {
        window.x = x;
        window.y = y;
      }
    },

    updateWindowSize(id: string, width: number, height: number) {
      const window = this.windows.find(w => w.id === id);
      if (window) {
        window.width = width;
        window.height = height;
      }
    }
  }
});
