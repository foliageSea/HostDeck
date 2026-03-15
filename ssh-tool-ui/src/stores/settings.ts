import { defineStore } from 'pinia';
import { ref, watch, computed } from 'vue';
import { useStorage, usePreferredDark } from '@vueuse/core';
import { db } from '@/utils/db';

export const useSettingsStore = defineStore('settings', () => {
    // Default values
    const defaultFontSize = 14;
    const defaultFontFamily = '"Maple Mono NF CN",Menlo, Monaco, "Courier New", monospace';
    const defaultBackgroundQuality = 1.0;

    // State
    const terminalFontSize = ref<number>(parseInt(localStorage.getItem('terminalFontSize') || String(defaultFontSize)));
    const terminalFontFamily = ref<string>(localStorage.getItem('terminalFontFamily') || defaultFontFamily);

    // Theme settings
    const themeMode = useStorage<'auto' | 'light' | 'dark'>('theme-mode', 'auto');
    const preferredDark = usePreferredDark();

    const isDark = computed(() => {
        if (themeMode.value === 'auto') {
            return preferredDark.value;
        }
        return themeMode.value === 'dark';
    });

    // Watch for theme changes and apply to document
    watch(isDark, (val) => {
        if (val) {
            document.documentElement.classList.add('dark');
        } else {
            document.documentElement.classList.remove('dark');
        }
    }, { immediate: true });

    // Background image and quality
    const customBackground = useStorage<string>('customBackground', '');
    const backgroundQuality = useStorage<number>('backgroundQuality', defaultBackgroundQuality);
    const backgroundType = useStorage<'image' | 'video'>('backgroundType', 'image');
    const backgroundVideoTimestamp = ref(Date.now());

    // Watch and save to localStorage
    watch(terminalFontSize, (newVal) => {
        localStorage.setItem('terminalFontSize', String(newVal));
    });

    watch(terminalFontFamily, (newVal) => {
        localStorage.setItem('terminalFontFamily', newVal);
    });

    // Actions
    function setTerminalFontSize(size: number) {
        terminalFontSize.value = size;
    }

    function setTerminalFontFamily(family: string) {
        terminalFontFamily.value = family;
    }

    function setThemeMode(mode: 'auto' | 'light' | 'dark') {
        themeMode.value = mode;
    }

    function setCustomBackground(dataUrl: string) {
        customBackground.value = dataUrl;
        backgroundType.value = 'image';
    }

    async function setVideoBackground(file: Blob) {
        await db.saveVideo(file);
        backgroundType.value = 'video';
        customBackground.value = ''; // Clear image to save space
        backgroundVideoTimestamp.value = Date.now();
    }

    function setBackgroundQuality(quality: number) {
        backgroundQuality.value = quality;
    }

    async function resetCustomBackground() {
        customBackground.value = '';
        backgroundQuality.value = defaultBackgroundQuality;
        backgroundType.value = 'image';
        await db.deleteVideo();
    }

    function resetTerminalSettings() {
        terminalFontSize.value = defaultFontSize;
        terminalFontFamily.value = defaultFontFamily;
    }

    return {
        terminalFontSize,
        terminalFontFamily,
        themeMode,
        isDark,
        customBackground,
        backgroundQuality,
        backgroundType,
        backgroundVideoTimestamp,
        setTerminalFontSize,
        setTerminalFontFamily,
        setThemeMode,
        setCustomBackground,
        setVideoBackground,
        setBackgroundQuality,
        resetCustomBackground,
        resetTerminalSettings
    };
});

