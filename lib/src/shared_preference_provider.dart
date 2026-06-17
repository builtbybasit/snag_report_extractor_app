import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Provides the app-wide [SharedPreferences] instance. Overridden in `main()`
/// with the instance loaded before the first frame, so consumers can read it
/// synchronously without an extra async hop.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in main',
  ),
);