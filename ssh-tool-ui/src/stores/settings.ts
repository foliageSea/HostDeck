import { defineStore } from 'pinia';
import { ref, watch } from 'vue';

export const useSettingsStore = defineStore('settings', () => {
    // Default values
    const defaultFontSize = 14;
    const defaultFontFamily = '"Maple Mono NF CN",Menlo, Monaco, "Courier New", monospace';

    // State
    const terminalFontSize = ref<number>(parseInt(localStorage.getItem('terminalFontSize') || String(defaultFontSize)));
    const terminalFontFamily = ref<string>(localStorage.getItem('terminalFontFamily') || defaultFontFamily);

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

    function resetTerminalSettings() {
        terminalFontSize.value = defaultFontSize;
        terminalFontFamily.value = defaultFontFamily;
    }

    return {
        terminalFontSize,
        terminalFontFamily,
        setTerminalFontSize,
        setTerminalFontFamily,
        resetTerminalSettings
    };
});
