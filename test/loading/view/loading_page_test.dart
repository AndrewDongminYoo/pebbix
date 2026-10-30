// Not needed for test files
// ignore_for_file: prefer_const_constructors

// 🎯 Dart imports:
import 'dart:async';
import 'dart:ui';

// 🐦 Flutter imports:
import 'package:flutter/widgets.dart' hide Image;

// 📦 Package imports:
import 'package:audioplayers/audioplayers.dart';
import 'package:flame/cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/game/session/session.dart';
import 'package:bubble_shooter/loading/loading.dart';

import '../../helpers/helpers.dart';

class _MockImages extends Mock implements Images;

class _MockAudioCache extends Mock implements AudioCache;

/// A consent call that never returns, standing in for a dead network.
class _HangingConsentGateway implements ConsentGateway {
  @override
  bool get canRequestAds => false;

  @override
  final ValueNotifier<bool> privacyOptionsRequired = ValueNotifier(false);

  @override
  Future<void> gather() => Completer<void>().future;

  @override
  Future<void> showPrivacyOptions() async {}
}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeRoute());
  });

  group('LoadingPage', () {
    late PreloadCubit preloadCubit;
    late _MockImages images;
    late _MockAudioCache audio;

    setUp(() {
      preloadCubit = PreloadCubit(
        images = _MockImages(),
        audio = _MockAudioCache(),
      );

      when(() => images.loadAll(any())).thenAnswer((_) async => <Image>[]);
      // The title it redirects to looks up the bubble sprites; nothing is
      // cached here, so it draws the procedural fallback.
      when(() => images.containsKey(any())).thenReturn(false);

      // Which cues load is preload_cubit_test's business, not this page's.
      when(() => audio.loadAll(any())).thenAnswer((_) async => <Uri>[]);
    });

    testWidgets('basic layout', (tester) async {
      await tester.pumpApp(LoadingPage(), preloadCubit: preloadCubit);

      expect(find.byType(AnimatedProgressBar), findsOneWidget);
      expect(find.textContaining('Loading'), findsOneWidget);

      await tester.pumpAndSettle(Duration(seconds: 1));
    });

    testWidgets('loading text', (tester) async {
      Text textWidgetFinder() {
        return find.textContaining('Loading').evaluate().first.widget as Text;
      }

      await tester.pumpApp(LoadingPage(), preloadCubit: preloadCubit);

      expect(textWidgetFinder().data, 'Loading  ...');

      unawaited(preloadCubit.loadSequentially());

      await tester.pump();

      expect(textWidgetFinder().data, 'Loading Delightful music...');
      await tester.pump(const Duration(milliseconds: 200));

      expect(textWidgetFinder().data, 'Loading Beautiful scenery...');
      await tester.pump(const Duration(milliseconds: 200));

      /// flush animation timers
      await tester.pumpAndSettle();
    });

    testWidgets('gathers consent once while loading', (tester) async {
      final consent = FakeConsentGateway();

      await tester.pumpApp(
        LoadingPage(),
        preloadCubit: preloadCubit,
        consentGateway: consent,
      );
      await tester.pump();

      // Spec §Privacy: ads are not requested until consent permits it, so
      // the state has to be resolved before anything can ask for one.
      expect(consent.gatherCount, 1);
    });

    testWidgets('starts the ad SDK once consent allows it', (tester) async {
      final ads = FakeAdsGateway();

      await tester.pumpApp(
        LoadingPage(),
        preloadCubit: preloadCubit,
        consentGateway: FakeConsentGateway(),
        adsGateway: ads,
      );
      await tester.pump();

      // Preloading starts here, not at the game page: an ad requested at the
      // first game over would rarely have arrived in time to offer Continue.
      expect(ads.startCount, 1);
    });

    testWidgets('a consent refusal never starts the ad SDK', (tester) async {
      final ads = FakeAdsGateway();

      await tester.pumpApp(
        LoadingPage(),
        preloadCubit: preloadCubit,
        consentGateway: FakeConsentGateway(gatherFails: true),
        adsGateway: ads,
      );
      await tester.pump();

      // Spec §Privacy: the SDK must not come up — and so must not request an
      // ad — while consent is unresolved or refused.
      expect(ads.startCount, 0);
    });

    testWidgets('a consent failure still reaches the title', (tester) async {
      final observer = MockNavigatorObserver();

      await tester.pumpApp(
        LoadingPage(),
        preloadCubit: preloadCubit,
        navigatorObserver: observer,
        consentGateway: FakeConsentGateway(gatherFails: true),
      );

      unawaited(preloadCubit.loadSequentially());
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();

      // Consent gates ads, never play.
      verify(
        () => observer.didReplace(
          newRoute: any(named: 'newRoute'),
          oldRoute: any(named: 'oldRoute'),
        ),
      ).called(1);
    });

    testWidgets('a hung consent call does not strand the player', (
      tester,
    ) async {
      final observer = MockNavigatorObserver();

      await tester.pumpApp(
        LoadingPage(),
        preloadCubit: preloadCubit,
        navigatorObserver: observer,
        consentGateway: _HangingConsentGateway(),
      );

      unawaited(preloadCubit.loadSequentially());
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();

      // Navigation is gated on the preload alone; a consent call that never
      // returns must not hold the loading screen open behind it.
      verify(
        () => observer.didReplace(
          newRoute: any(named: 'newRoute'),
          oldRoute: any(named: 'oldRoute'),
        ),
      ).called(1);
    });

    testWidgets('redirects after loading', (tester) async {
      final observer = MockNavigatorObserver();

      await tester.pumpApp(
        LoadingPage(),
        preloadCubit: preloadCubit,
        navigatorObserver: observer,
      );

      unawaited(preloadCubit.loadSequentially());

      await tester.pump(const Duration(milliseconds: 800));

      await tester.pumpAndSettle();

      verify(
        () => observer.didReplace(
          newRoute: any(named: 'newRoute'),
          oldRoute: any(named: 'oldRoute'),
        ),
      ).called(1);
    });
  });
}
