// 🎯 Dart imports:
import 'dart:async';
import 'dart:math' as math;

// 🐦 Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// 📦 Package imports:
import 'package:flame/game.dart' hide Route;
import 'package:flame_audio/bgm.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/app/settings_route.dart';
import 'package:bubble_shooter/game/game.dart';
import 'package:bubble_shooter/gen/assets.gen.dart';
import 'package:bubble_shooter/l10n/l10n.dart';
import 'package:bubble_shooter/loading/cubit/cubit.dart';
import 'package:bubble_shooter/title/title.dart';

class GamePage extends StatelessWidget {
  const new({this.game, super.key});

  final FlameGame? game;

  static Route<void> route() {
    return MaterialPageRoute<void>(builder: (_) => const GamePage());
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) {
        final audioCache = context.read<PreloadCubit>().state.audio;
        return AudioCubit(
          audioCache: audioCache,
          backgroundMusic: Bgm(audioCache: audioCache),
          settings: context.read<SettingsRepository>().settings,
        );
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarBrightness: Brightness.dark,
          statusBarIconBrightness: Brightness.light,
        ),
        child: Scaffold(
          // A fixed-resolution camera letterboxes on any aspect but the one it
          // was cut for, and the theme's white would frame the nebula in white
          // bands. This is the darkest stop of the background's own gradient,
          // so the system insets and camera bars read as more sky.
          backgroundColor: const Color(0xFF0B1226),
          body: GameView(game: game),
        ),
      ),
    );
  }
}

class GameView extends StatefulWidget {
  const new({super.key, this.game});

  final FlameGame? game;

  @override
  State<GameView> createState() => _GameViewState();
}

class _GameViewState extends State<GameView> {
  FlameGame? _game;
  GameSessionController? _controller;

  /// This page's claim on the app-scoped session, surrendered in [dispose].
  Object? _binding;
  StreamSubscription<GameSessionState>? _adAudio;
  bool _adPaused = false;
  bool _wasPlaying = true;

  late final AudioCubit _audio;

  /// Reads the live settings on every cue, so a toggle flipped in Settings
  /// takes effect from the next shot without a rebuild.
  late final HapticsGateway _haptics;

  /// Spec §6: the loop stops on background or an audio interruption and
  /// restores per setting on foreground. `Bgm` only does this for itself
  /// once `initialize()` has registered it as an observer, which this app
  /// never calls.
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _audio = context.read<AudioCubit>();
    _haptics = HapticsGateway(context.read<SettingsRepository>());
    _lifecycle = AppLifecycleListener(
      // A phone call or another app taking audio focus only moves iOS to
      // inactive — it never reaches paused — so hanging the pause off
      // onPause would let the loop play through the call. Every path to
      // the background passes through inactive, so this covers both.
      onInactive: () {
        // Leaving the app is the exit dispose cannot see: TitlePage enters
        // with pushReplacement, so GamePage is the only route and Android's
        // root-level Back hands the pop to the system instead of tearing the
        // page down. Every way out of the foreground passes through here.
        _controller?.preserveRecord();
        unawaited(_audio.pauseBackgroundMusic(AudioPauseReason.lifecycle));
      },
      onResume: () => unawaited(
        _audio.resumeBackgroundMusic(AudioPauseReason.lifecycle),
      ),
    );
    unawaited(
      _audio.start(
        Assets.audio.background,
        // Every generated cue but the loop, so a cue added later is warmed
        // without anyone remembering to list it here.
        effects: Assets.audio.values.where((asset) => asset != Assets.audio.background).toList(),
      ),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    unawaited(_adAudio?.cancel());
    unawaited(_audio.pauseBackgroundMusic(AudioPauseReason.lifecycle));
    // Every way out of the game lands here — Home, Android Back, a route
    // replaced from elsewhere — so settling the run is done once here
    // rather than at each exit, where the next new exit would miss it.
    // A loss left on the continue offer would otherwise lose its run_end,
    // its high score, and its place in the interstitial cadence.
    //
    // Detached, not closed: the session outlives this page, and only its
    // binding to this game ends here. The token is what makes that safe —
    // `pushReplacement` disposes this page after the next one has already
    // attached, and settling then would be settling someone else's run.
    if (_binding case final binding?) {
      _controller?.detach(binding).ignore();
    }
    super.dispose();
  }

  /// Mirrors the engine's paused state for the Flutter layer, which sits
  /// above the Flame overlays. While paused the complete gameplay HUD is
  /// hidden so it doesn't sit on top of the pause panel.
  bool _paused = false;

  void _pause() {
    setState(() => _paused = true);
    _game!
      ..pauseEngine()
      ..overlays.add(BubbleShooter.pauseOverlayKey);
  }

  void _resume() {
    setState(() => _paused = false);
    _game!
      ..overlays.remove(BubbleShooter.pauseOverlayKey)
      ..resumeEngine();
  }

  /// Spec §6: the loop stops while a rewarded or interstitial ad shows and
  /// restores per setting afterward. Nothing else observes these phases,
  /// so the audio side has to be driven from them explicitly.
  void _syncAdAudio(GameSessionState session) {
    if (session.adShowing == _adPaused) return;
    _adPaused = session.adShowing;
    unawaited(
      _adPaused ? _audio.pauseBackgroundMusic(AudioPauseReason.ad) : _audio.resumeBackgroundMusic(AudioPauseReason.ad),
    );
  }

  /// The game-over cue is 1-2 s long, but the state it announces can end
  /// sooner: Restart and a granted Continue both hand play back. Left
  /// running it rings over the new run and collides with its first shot.
  /// Driven from the session rather than the game so [BubbleShooter] keeps
  /// knowing nothing about the audio stack.
  void _syncGameOverCue(GameSessionState session) {
    final resumed = session.phase == SessionPhase.playing;
    if (resumed == _wasPlaying) return;
    _wasPlaying = resumed;
    if (resumed) unawaited(_audio.stopEffect(Assets.audio.gameover));
  }

  /// Settling a pending loss is [dispose]'s job, so Home only navigates.
  void _goHome() {
    Navigator.of(context).pushReplacement<void, void>(TitlePage.route());
  }

  /// Settles the live run, then hands the engine a fresh one.
  ///
  /// The pause panel's Restart never tears the page down, so [dispose] cannot
  /// settle it, and [BubbleShooter.startGame] zeroes `scoreNotifier` before it
  /// emits `RunStarted` — by the time the session hears about the new run the
  /// score it had to preserve is gone. This is the last point where it still
  /// exists.
  ///
  /// The game-over panel's Restart calls `startGame` directly and needs no
  /// settling: its Play Again button sits in the branch that runs only when
  /// the continue offer is absent, so the run it replaces has already been
  /// finalized.
  void _restart(BubbleShooter shooter) {
    _controller?.abandonRun();
    shooter.startGame();
  }

  /// Both entry points route through [openSettings]; this one additionally
  /// pushes the change into the [AudioCubit] the title route cannot see,
  /// because that cubit is provided inside `GamePage`.
  Future<void> _openSettings() => openSettings(
    context,
    onAlsoChanged: (settings) => unawaited(_audio.applySettings(settings)),
  );

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(
      context,
    ).textTheme.bodySmall!.copyWith(color: Colors.white, fontSize: 4);

    if (_game == null) {
      _game =
          widget.game ??
          BubbleShooter(
            l10n: context.l10n,
            playSfx: _haptics.pairedWith(_audio.playEffect),
            textStyle: textStyle,
            images: context.read<PreloadCubit>().state.images,
          );
      if (_game case final BubbleShooter shooter) {
        // App-scoped, so the interstitial cadence and the run count carry
        // across a Home round trip (AND-117). This page only lends it a game.
        _controller = context.read<GameSessionController>();
        _binding = _controller!.attach(
          events: shooter.events,
          revive: shooter.revive,
          score: () => shooter.score,
        );
        _adAudio = _controller!.stream.listen((session) {
          _syncAdAudio(session);
          _syncGameOverCue(session);
        });
        // A cubit stream replays nothing, so a listener only ever hears about
        // changes made after it subscribed. This page can open onto a session
        // that is already mid-ad — Home during an interstitial, then Start —
        // and its AudioCubit is brand new, so without seeding the loop would
        // come up playing under that ad (spec §6).
        _syncAdAudio(_controller!.state);
      }
    }
    final bubbleGame = _game is BubbleShooter ? _game! as BubbleShooter : null;
    if (bubbleGame != null) {
      bubbleGame.defenderMotion.reducedMotion = MediaQuery.disableAnimationsOf(context);
    }
    // A Flame overlay is not a route, so Android's Back would reach the
    // Navigator and leave the game while the pause panel looks modal.
    return PopScope<Object?>(
      canPop: !_paused,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _resume();
      },
      child: Stack(
        children: [
          Positioned.fill(
            child: SafeArea(
              bottom: false,
              child: GameWidget(
                game: _game!,
                overlayBuilderMap: {
                  BubbleShooter.gameOverOverlayKey: (context, FlameGame game) {
                    final shooter = game as BubbleShooter;
                    final controller = _controller!;
                    return BlocProvider.value(
                      value: controller,
                      child: BlocBuilder<GameSessionController, GameSessionState>(
                        builder: (context, session) {
                          // While an ad future is in flight a restart would
                          // let its stale callback corrupt the new run
                          // (spec §4).
                          return GameOverOverlay(
                            isVictory: shooter.status == GameStatus.victory,
                            score: shooter.score,
                            // The run only reaches the store once it is
                            // finalized, so during the offer the stored best
                            // would read lower than the score beside it.
                            bestScore: math.max(shooter.score, session.highScore),
                            onRestart: session.adShowing ? null : shooter.startGame,
                            onHome: _goHome,
                            showContinue: session.phase == SessionPhase.continueOffer,
                            onContinue: controller.requestContinue,
                            onDecline: controller.declineContinue,
                            // Only on a finalized run: the continue offer is
                            // a decision with a deadline, and these numbers
                            // are the retrospective it has not earned yet.
                            summary: switch (session) {
                              GameSessionState(
                                phase: SessionPhase.results,
                                lastGameOver: final stats?,
                              ) =>
                                (
                                  shotCount: stats.shotCount,
                                  ceilingDepth: stats.ceilingDepth,
                                  continued: stats.continued,
                                ),
                              _ => null,
                            },
                          );
                        },
                      ),
                    );
                  },
                  // No ad guard here: the pause button is only offered while
                  // the session is playing, so no ad can be in flight when the
                  // panel is open.
                  BubbleShooter.pauseOverlayKey: (context, FlameGame game) {
                    final shooter = game as BubbleShooter;
                    return SizedBox.expand(
                      child: PauseOverlay(
                        onResume: _resume,
                        onHowToPlay: () => unawaited(HowToPlayPage.open(context)),
                        onSettings: _openSettings,
                        onRestart: () {
                          _resume();
                          _restart(shooter);
                        },
                      ),
                    );
                  },
                },
              ),
            ),
          ),
          // The background remains full-bleed while the readouts and pause
          // button also clear the home indicator.
          Positioned.fill(child: SafeArea(child: _hud(bubbleGame))),
        ],
      ),
    );
  }

  /// The Flutter layer above the game surface. Extracted so it keeps its own
  /// indentation budget: inlined under the inset it nests eight deep and the
  /// comments start wrapping to fit the accident rather than the sentence.
  Widget _hud(BubbleShooter? bubbleGame) {
    return Stack(
      children: [
        if (bubbleGame != null) ...[
          if (_controller case final controller?) ...[
            Align(
              alignment: Alignment.topLeft,
              child: BlocProvider.value(
                value: controller,
                child: BlocBuilder<GameSessionController, GameSessionState>(
                  builder: (context, session) {
                    if (_paused || session.phase != SessionPhase.playing) {
                      return const SizedBox.shrink();
                    }
                    return IgnorePointer(
                      child: ScoreHud(
                        score: bubbleGame.scoreNotifier,
                        pressure: bubbleGame.pressureNotifier,
                      ),
                    );
                  },
                ),
              ),
            ),
            Align(
              alignment: Alignment.topRight,
              child: BlocProvider.value(
                value: controller,
                child: BlocBuilder<GameSessionController, GameSessionState>(
                  builder: (context, session) {
                    // Pause is a gameplay-only affordance. Left up during
                    // the continue offer or the results screen it would
                    // offer a second Restart that skips finalization, so
                    // the lost run would never reach run_end, the high
                    // score, or the interstitial cadence.
                    if (_paused || session.phase != SessionPhase.playing) {
                      return const SizedBox.shrink();
                    }
                    return IconButton(
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black54,
                        foregroundColor: Colors.white,
                      ),
                      tooltip: context.l10n.pauseButtonLabel,
                      icon: const Icon(Icons.pause),
                      onPressed: _pause,
                    );
                  },
                ),
              ),
            ),
            Align(
              alignment: const Alignment(0, 0.45),
              child: BlocProvider.value(
                value: controller,
                child: BlocBuilder<GameSessionController, GameSessionState>(
                  builder: (context, session) =>
                      session.tutorialSeen || _paused || session.phase != SessionPhase.playing
                      ? const SizedBox.shrink()
                      : const TutorialHint(),
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }
}
