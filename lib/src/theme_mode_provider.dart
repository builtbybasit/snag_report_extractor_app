import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Seeds [ThemeModeNotifier]'s initial state. `main()` overrides this with the
/// value loaded from SharedPreferences before the first frame, so the app
/// starts directly in the saved theme with no light->dark flash.
final initialThemeModeProvider = Provider<ThemeMode>(
  (ref) => ThemeMode.light,
);

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  static const String _prefsKey = 'theme_mode_dark';

  /// Reads the persisted theme synchronously from an already-loaded [prefs].
  /// Call this in `main()` to build the [initialThemeModeProvider] override.
  static ThemeMode readPersisted(SharedPreferences prefs) =>
      (prefs.getBool(_prefsKey) ?? false) ? ThemeMode.dark : ThemeMode.light;

  @override
  ThemeMode build() => ref.read(initialThemeModeProvider);

  Future<void> toggleTheme() async {
    final next = state == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    state = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, next == ThemeMode.dark);
  }
}
