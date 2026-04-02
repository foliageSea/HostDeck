export type ThemePreset = 'ocean' | 'emerald' | 'sunset';

type ThemeTokens = {
  primary: string;
  primaryForeground: string;
  accent: string;
  accentForeground: string;
  ring: string;
};

type ThemePalette = {
  label: string;
  light: ThemeTokens;
  dark: ThemeTokens;
};

export const DEFAULT_THEME_PRESET: ThemePreset = 'ocean';

export const themePresets: Record<ThemePreset, ThemePalette> = {
  ocean: {
    label: '海洋蓝',
    light: {
      primary: '221.2 83.2% 53.3%',
      primaryForeground: '210 40% 98%',
      accent: '210 40% 96.1%',
      accentForeground: '222.2 47.4% 11.2%',
      ring: '221.2 83.2% 53.3%',
    },
    dark: {
      primary: '217.2 91.2% 59.8%',
      primaryForeground: '222.2 47.4% 11.2%',
      accent: '217.2 32.6% 17.5%',
      accentForeground: '210 40% 98%',
      ring: '224.3 76.3% 48%',
    },
  },
  emerald: {
    label: '翡翠绿',
    light: {
      primary: '160 84% 39%',
      primaryForeground: '0 0% 100%',
      accent: '151 40% 96%',
      accentForeground: '158 64% 18%',
      ring: '160 84% 39%',
    },
    dark: {
      primary: '160 84% 45%',
      primaryForeground: '155 36% 12%',
      accent: '158 32% 18%',
      accentForeground: '156 73% 90%',
      ring: '160 84% 45%',
    },
  },
  sunset: {
    label: '日落橙',
    light: {
      primary: '24 95% 53%',
      primaryForeground: '30 60% 98%',
      accent: '33 100% 96%',
      accentForeground: '20 72% 24%',
      ring: '24 95% 53%',
    },
    dark: {
      primary: '24 94% 58%',
      primaryForeground: '18 38% 12%',
      accent: '22 34% 18%',
      accentForeground: '30 88% 92%',
      ring: '24 94% 58%',
    },
  },
};

export const themePresetOptions = (Object.keys(themePresets) as ThemePreset[]).map((preset) => ({
  value: preset,
  label: themePresets[preset].label,
}));

export function resolveThemePreset(value: string | undefined): ThemePreset {
  if (value && value in themePresets) {
    return value as ThemePreset;
  }
  return DEFAULT_THEME_PRESET;
}

export function applyThemePreset(preset: string | undefined, isDark: boolean): void {
  const resolvedPreset = resolveThemePreset(preset);
  const palette = themePresets[resolvedPreset][isDark ? 'dark' : 'light'];
  const rootStyle = document.documentElement.style;

  rootStyle.setProperty('--primary', palette.primary);
  rootStyle.setProperty('--primary-foreground', palette.primaryForeground);
  rootStyle.setProperty('--accent', palette.accent);
  rootStyle.setProperty('--accent-foreground', palette.accentForeground);
  rootStyle.setProperty('--ring', palette.ring);
}
