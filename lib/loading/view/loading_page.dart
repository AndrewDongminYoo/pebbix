// 🎯 Dart imports:
import 'dart:async';

// 🐦 Flutter imports:
import 'package:flutter/material.dart';

// 📦 Package imports:
import 'package:flutter_bloc/flutter_bloc.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/game/session/session.dart';
import 'package:bubble_shooter/l10n/l10n.dart';
import 'package:bubble_shooter/loading/loading.dart';
import 'package:bubble_shooter/title/title.dart';

class LoadingPage extends StatefulWidget {
  const new({super.key});

  @override
  State<LoadingPage> createState() => _LoadingPageState();
}

class _LoadingPageState extends State<LoadingPage> {
  @override
  void initState() {
    super.initState();
    // Spec §2 package G: resolve consent before anything can ask for an ad.
    // Deliberately not awaited anywhere on the way to the title — consent
    // gates ads, not play, so a slow or dead network must not hold the
    // player on this screen. Navigation stays gated on the preload alone.
    unawaited(
      _prepareAds(context.read<ConsentGateway>(), context.read<AdsGateway>()),
    );
    // The store has no consent to wait for, and it wants its purchase stream
    // subscribed as early as possible: a transaction the last launch left
    // unfinished is re-delivered only once something is listening. Not
    // awaited, for the same reason consent is not.
    if (context.read<EntitlementRepository>() case final PurchaseGateway purchases) {
      unawaited(purchases.start());
    }
  }

  /// The ad SDK comes up only once consent actually allows a request, and the
  /// first ads start loading here rather than at the game page so the first
  /// game over already has one to offer.
  Future<void> _prepareAds(ConsentGateway consent, AdsGateway ads) async {
    await consent.gather();
    if (consent.canRequestAds) await ads.start();
  }

  Future<void> onPreloadComplete(NavigatorState navigator) async {
    await Future<void>.delayed(AnimatedProgressBar.intrinsicAnimationDuration);
    if (!mounted) return;
    await navigator.pushReplacement<void, void>(TitlePage.route());
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<PreloadCubit, PreloadState>(
      listenWhen: (prevState, state) => !prevState.isComplete && state.isComplete,
      listener: (context, state) => onPreloadComplete(Navigator.of(context)),
      child: const Scaffold(body: Center(child: _LoadingInternal())),
    );
  }
}

class _LoadingInternal extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final primaryTextTheme = Theme.of(context).primaryTextTheme;
    final l10n = context.l10n;

    return BlocBuilder<PreloadCubit, PreloadState>(
      builder: (context, state) {
        final loadingLabel = l10n.loadingPhaseLabel(state.currentLabel);
        final loadingMessage = l10n.loading(loadingLabel);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: AnimatedProgressBar(
                progress: state.progress,
                backgroundColor: const Color(0xFF2A48DF),
                foregroundColor: const Color(0xFFFFFFFF),
              ),
            ),
            Text(
              loadingMessage,
              style: primaryTextTheme.bodySmall!.copyWith(
                color: const Color(0xFF2A48DF),
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        );
      },
    );
  }
}
