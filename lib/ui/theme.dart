import 'package:material_ui/material_ui.dart';

/// OpenDash's own palette: cool black, bone text, one mint accent.
abstract final class Palette {
  static const ink = Color(0xFF05070A);
  static const panel = Color(0xFF0D1117);
  static const raised = Color(0xFF151B23);
  static const slate = Color(0xFF232932);
  static const bone = Color(0xFFECEEF1);
  static const ash = Color(0xFF8A919C);
  static const mint = Color(0xFF35D39E);
  static const mintDeep = Color(0xFF0B8F66);
  static const critical = Color(0xFFFF3B4E);
  static const warning = Color(0xFFFFC53D);
  static const paper = Color(0xFFF4F6F8);
}

ThemeData _base(ColorScheme scheme) {
  final text = Typography.material2021(platform: TargetPlatform.android)
      .englishLike
      .merge(scheme.brightness == Brightness.dark ? Typography.material2021().white : Typography.material2021().black)
      .apply(fontFamily: 'Archivo', bodyColor: scheme.onSurface, displayColor: scheme.onSurface);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    fontFamily: 'Archivo',
    textTheme: text,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2),
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainer,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: scheme.outlineVariant)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontFamily: 'Archivo', fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        side: BorderSide(color: scheme.outline),
        textStyle: const TextStyle(fontFamily: 'Archivo', fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHigh,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 16)),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
  );
}

final darkTheme = _base(const ColorScheme(
  brightness: Brightness.dark,
  primary: Palette.mint,
  onPrimary: Palette.ink,
  secondary: Palette.mint,
  onSecondary: Palette.ink,
  error: Palette.critical,
  onError: Palette.ink,
  tertiary: Palette.warning,
  onTertiary: Palette.ink,
  surface: Palette.ink,
  onSurface: Palette.bone,
  onSurfaceVariant: Palette.ash,
  surfaceContainer: Palette.panel,
  surfaceContainerHigh: Palette.raised,
  outline: Palette.slate,
  outlineVariant: Color(0xFF1A2029),
));

final lightTheme = _base(const ColorScheme(
  brightness: Brightness.light,
  primary: Palette.mintDeep,
  onPrimary: Colors.white,
  secondary: Palette.mintDeep,
  onSecondary: Colors.white,
  error: Color(0xFFD0142A),
  onError: Colors.white,
  tertiary: Color(0xFF9A6A00),
  onTertiary: Colors.white,
  surface: Palette.paper,
  onSurface: Palette.ink,
  onSurfaceVariant: Color(0xFF5B636E),
  surfaceContainer: Colors.white,
  surfaceContainerHigh: Color(0xFFE9ECF0),
  outline: Color(0xFFC9CED6),
  outlineVariant: Color(0xFFE1E5EA),
));
