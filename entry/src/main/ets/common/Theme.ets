/**
 * Material 3 风格色板（以 Google Blue #0B57D0 为种子色生成 tonal 色板）。
 * 组件通过 @StorageProp(Theme.KEY_DARK) 感知系统深浅色，
 * 再用 Theme.palette(dark) 取得当前色板。
 */
export class Theme {
  static readonly KEY_DARK_MODE: string = 'isDark';

  static palette(dark: boolean): Palette {
    return dark ? Theme.DARK : Theme.LIGHT;
  }

  /** 头像圆环的 Material 调色盘（按名称哈希取色，保证同账户颜色稳定） */
  static avatarColors(dark: boolean): string[] {
    return dark
      ? ['#8AB4F8', '#F28B82', '#FDD663', '#81C995', '#78D9EC', '#C58AF9', '#FCAD70', '#A8DADC']
      : ['#1A73E8', '#D93025', '#F9AB00', '#188038', '#12A4AF', '#A142F4', '#E8710A', '#3F51B5'];
  }

  static avatarColor(seed: string, dark: boolean): string {
    const colors = Theme.avatarColors(dark);
    let hash = 0;
    for (let i = 0; i < seed.length; i++) {
      hash = (hash * 31 + seed.charCodeAt(i)) >>> 0;
    }
    return colors[hash % colors.length];
  }

  private static readonly LIGHT: Palette = {
    dark: false,
    primary: '#0B57D0',
    onPrimary: '#FFFFFF',
    primaryContainer: '#D3E3FD',
    onPrimaryContainer: '#041E49',
    secondary: '#565E71',
    onSecondary: '#FFFFFF',
    secondaryContainer: '#DAE2F9',
    onSecondaryContainer: '#131C2B',
    tertiary: '#6B5778',
    surface: '#F9F9FF',
    onSurface: '#191C20',
    surfaceVariant: '#E0E2EC',
    onSurfaceVariant: '#44474E',
    surfaceContainer: '#EEF0F7',
    surfaceContainerHigh: '#E8EAF2',
    surfaceContainerHighest: '#E2E4EC',
    outline: '#74777F',
    outlineVariant: '#C4C6D0',
    error: '#B3261E',
    onError: '#FFFFFF',
    errorContainer: '#F9DEDC',
    onErrorContainer: '#410E0B',
    scrim: '#000000',
    shadow: '#1C1B1F'
  };

  private static readonly DARK: Palette = {
    dark: true,
    primary: '#A8C7FA',
    onPrimary: '#062E6F',
    primaryContainer: '#0842A0',
    onPrimaryContainer: '#D3E3FD',
    secondary: '#BEC6DC',
    onSecondary: '#283141',
    secondaryContainer: '#3E4759',
    onSecondaryContainer: '#DAE2F9',
    tertiary: '#D7BDE4',
    surface: '#111318',
    onSurface: '#E2E2E9',
    surfaceVariant: '#44474E',
    onSurfaceVariant: '#C4C6D0',
    surfaceContainer: '#1D2024',
    surfaceContainerHigh: '#282A2F',
    surfaceContainerHighest: '#33353A',
    outline: '#8E9199',
    outlineVariant: '#44474E',
    error: '#F2B8B5',
    onError: '#601410',
    errorContainer: '#8C1D18',
    onErrorContainer: '#F9DEDC',
    scrim: '#000000',
    shadow: '#000000'
  };
}

/** Material 3 色彩令牌 */
export interface Palette {
  dark: boolean;
  primary: string;
  onPrimary: string;
  primaryContainer: string;
  onPrimaryContainer: string;
  secondary: string;
  onSecondary: string;
  secondaryContainer: string;
  onSecondaryContainer: string;
  tertiary: string;
  surface: string;
  onSurface: string;
  surfaceVariant: string;
  onSurfaceVariant: string;
  surfaceContainer: string;
  surfaceContainerHigh: string;
  surfaceContainerHighest: string;
  outline: string;
  outlineVariant: string;
  error: string;
  onError: string;
  errorContainer: string;
  onErrorContainer: string;
  scrim: string;
  shadow: string;
}
