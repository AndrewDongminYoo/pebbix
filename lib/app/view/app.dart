// 🎯 Dart imports:
import 'dart:async';

// 🐦 Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// 📦 Package imports:
import 'package:audioplayers/audioplayers.dart';
import 'package:flame/cache.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/game/session/session.dart';
import 'package:bubble_shooter/l10n/l10n.dart';
import 'package:bubble_shooter/loading/loading.dart';

class App extends StatelessWidget {
  const new({
    required this.settings,
    required this.consent,
    required this.ads,
    required this.entitlements,
    required this.analytics,
    super.key,
  });

  /// Loaded before runApp so every reader gets synchronous access.
  final SettingsRepository settings;

  /// Resolved at [LoadingPage], not here — this only publishes it.
  final ConsentGateway consent;

  /// App-scoped so an ad is loaded well before the first game over asks for
  /// one; the game page only reads it.
  final AdsGateway ads;

  /// App-scoped so every game route reads the same purchase state, and so a
  /// purchase settled on one route is already in force on the next.
  ///
  /// Typed as the read surface on purpose: spec 0003's Application Injection
  /// Contract fixes this seam and lets issue #36 change only what the
  /// entrypoints pass through it. They pass a `PurchaseGateway`, which is one
  /// of these; a capture test passes a plain fake, and the routes that want
  /// to buy ask whether what they were given can.
  final EntitlementRepository entitlements;

  /// App-scoped so one sink records the complete session lifecycle.
  final AnalyticsSink analytics;

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<SettingsRepository>.value(value: settings),
        RepositoryProvider<ConsentGateway>.value(value: consent),
        RepositoryProvider<AdsGateway>.value(value: ads),
        RepositoryProvider<EntitlementRepository>.value(value: entitlements),
        RepositoryProvider<AnalyticsSink>.value(value: analytics),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (_) {
              final cubit = PreloadCubit(
                Images(prefix: ''),
                AudioCache(prefix: ''),
              );
              unawaited(cubit.loadSequentially());
              return cubit;
            },
          ),
          BlocProvider(
            // Above the game route, so the interstitial cadence and the run
            // count survive a Home round trip (AND-117). The game page lends
            // it a game with attach and takes it back with detach.
            create: (_) => GameSessionController(
              ads: ads,
              entitlements: entitlements,
              analytics: analytics,
              settings: settings,
            ),
          ),
        ],
        child: const AppView(),
      ),
    );
  }
}

class AppView extends StatelessWidget {
  const new({super.key});

  /// The bundled family, declared in `pubspec.yaml` under `assets/fonts/`.
  ///
  /// Bundled rather than fetched: Poppins carried no Hangul, so Korean fell
  /// through to whatever the platform substituted, and it arrived over the
  /// network — a font request the privacy disclosures would have to account
  /// for and an offline first launch would have to survive. One variable
  /// file serves the regular, bold and black the UI asks for.
  static const _fontFamily = 'Pretendard';

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (context) {
        final flavorTag = const {'development': '[DEV] ', 'staging': '[STG] '}[appFlavor] ?? '';
        return '$flavorTag${context.l10n.titleAppBarTitle}';
      },
      theme: ThemeData(
        primaryColor: const Color(0xFF2A48DF),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF2A48DF),
          foregroundColor: Color(0xFFFFFFFF),
        ),
        colorScheme: ColorScheme.fromSwatch(
          accentColor: const Color(0xFF2A48DF),
        ),
        scaffoldBackgroundColor: const Color(0xFFFFFFFF),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.all(const Color(0xFF2A48DF)),
            foregroundColor: WidgetStateProperty.all(Colors.white),
          ),
        ),
        fontFamily: _fontFamily,
      ),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const LoadingPage(),
    );
  }
}
