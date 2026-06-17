// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snag_report_extractor_app/src/app.dart';
import 'package:snag_report_extractor_app/src/logging/talker.dart';
import 'package:snag_report_extractor_app/src/shared_preference_provider.dart';
import 'package:snag_report_extractor_app/src/theme_mode_provider.dart';


void main() async {
  // * For more info on error handling, see:
  // * https://docs.flutter.dev/testing/errors
  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // * Register error handlers BEFORE runApp so errors during init / the
      // * first frame are captured. Forward to talker so they are logged in
      // * all build modes (debugPrint is stripped in release).
      FlutterError.onError = (FlutterErrorDetails details) {
        talker.handle(details.exception, details.stack);
        FlutterError.presentError(details);
      };
      ErrorWidget.builder = (FlutterErrorDetails details) {
        return Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.red,
            title: const Text(
              "An error occurred",
              style: TextStyle(color: Colors.white),
            ),
          ),
          body: Center(child: Text(details.toString())),
        );
      };

      // turn off the # in the URLs on the web
      usePathUrlStrategy();
      // Load the persisted theme before the first frame so the app starts in
      // the saved mode with no light->dark flash.
      final prefs = await SharedPreferences.getInstance();
      final initialTheme = ThemeModeNotifier.readPersisted(prefs);
      // * Entry point for the app
      runApp(
        ProviderScope(
          overrides: [
            initialThemeModeProvider.overrideWithValue(initialTheme),
            sharedPreferencesProvider.overrideWithValue(prefs),
          ],
          // Riverpod 3 enables automatic retry-on-error by default. Our
          // FutureProviders intentionally throw on missing files/dirs, so we
          // opt out of retries to surface those errors immediately instead of
          // looping. Re-enable per-provider where a retry is actually wanted.
          retry: (retryCount, error) => null,
          child: const MyApp(),
        ),
      );
    },
    (Object error, StackTrace stack) {
      // Log the error in all build modes (debugPrint is stripped in release).
      talker.handle(error, stack);
    },
  );
}
