import { defineConfig, presetUno, transformerDirectives, transformerVariantGroup } from 'unocss'

export default defineConfig({
  presets: [presetUno()],
  shortcuts: {
    'btn-reset': 'border-0 bg-transparent p-0 text-inherit cursor-pointer',
    'glass-panel-dark':
      'border border-[rgba(148,163,184,0.18)] bg-[rgba(15,23,42,0.58)] backdrop-blur-[18px] shadow-[0_24px_70px_rgba(15,23,42,0.35)]',
    'glass-panel-light':
      'border border-[rgba(148,163,184,0.22)] bg-[rgba(255,255,255,0.72)] shadow-[0_24px_70px_rgba(148,163,184,0.2)]',
    'glass-surface-dark':
      'border border-[rgba(148,163,184,0.16)] bg-[rgba(15,23,42,0.56)] backdrop-blur-[16px]',
    'glass-surface-light': 'border border-[rgba(148,163,184,0.22)] bg-[rgba(255,255,255,0.66)]',
    'mono-ui': "[font-family:Consolas,'Cascadia_Mono','Courier_New',monospace]",
    'scrollbar-none': '[scrollbar-width:none] [-ms-overflow-style:none]',
    'text-muted-dark': 'text-[rgba(226,232,240,0.72)]',
    'text-muted-light': 'text-[rgba(51,65,85,0.8)]',
    'truncate-line': 'min-w-0 overflow-hidden text-ellipsis whitespace-nowrap',
  },
  transformers: [transformerDirectives(), transformerVariantGroup()],
})
