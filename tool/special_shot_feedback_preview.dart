// Local QA entrypoint: never used by a production release target.
import 'dart:async';
import 'dart:js_interop';

import 'package:audioplayers/audioplayers.dart';
import 'package:flame/cache.dart';
import 'package:flame/game.dart';
import 'package:flame_audio/bgm.dart';
import 'package:flutter/material.dart';

import 'package:bubble_shooter/game/game.dart';
import 'package:bubble_shooter/gen/assets.gen.dart';
import 'package:bubble_shooter/l10n/l10n.dart';

@JS('pebbixPreview')
external set preview(JSObject value);

@JSExport()
class PreviewControls {
  new(this._game, this._audio);
  final BubbleShooter _game;
  final AudioCubit _audio;
  Timer? _freeze;

  void prepare(String kind) {
    _freeze?.cancel();
    _game
      ..resumeEngine()
      ..startGame();
    final board = BubbleBoard(columns: BubbleShooter.columns);
    HexCell cell(int row, int col) => HexCell.fromRowCol(row: row, col: col);
    for (var row = 0; row <= 5; row++) {
      board.place(cell(row, 3), BubbleColor.red);
    }
    board
      ..place(cell(0, 0), BubbleColor.blue)
      ..place(cell(4, 2), BubbleColor.yellow)
      ..place(cell(5, 2), BubbleColor.green)
      ..place(cell(6, 2), BubbleColor.purple)
      ..place(cell(7, 1), BubbleColor.orange);
    _game
      ..board = kind == 'ceiling' ? (BubbleBoard(columns: 8)..place(cell(0, 0), BubbleColor.blue)) : board
      ..boardComponent.syncBoard()
      ..currentShot = (
        color: BubbleColor.green,
        kind: kind == 'bomb' ? ShotKind.bomb : ShotKind.rainbow,
      );
  }

  // Uses the real aim solver and projectile; no fabricated landing result.
  void fire(String captureMode) {
    _game
      ..aimAt(Vector2(240, 30))
      ..fire();
    if (captureMode == 'still') {
      _freeze = Timer.periodic(const Duration(milliseconds: 10), (timer) {
        if (_game.shotCount > 0) {
          timer.cancel();
          _freeze = Timer(const Duration(milliseconds: 120), _game.pauseEngine);
        }
      });
    }
  }

  void pause() => _game.pauseEngine();
  void resume() => _game.resumeEngine();
  String status() => '${_game.status.name}; shots=${_game.shotCount}; score=${_game.score}; paused=${_game.paused}';
  void setSound(String setting) =>
      unawaited(_audio.applySettings(GameSettings(musicEnabled: false, sfxEnabled: setting == 'on')));
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final images = Images(prefix: '');
  await images.loadAll(Assets.images.values.map((asset) => asset.path).toList());
  final cache = AudioCache(prefix: '');
  final audio = AudioCubit(
    audioCache: cache,
    backgroundMusic: Bgm(audioCache: cache),
    settings: const GameSettings(musicEnabled: false),
  );
  final game = BubbleShooter(
    l10n: await AppLocalizations.delegate.load(const Locale('en')),
    playSfx: (asset) => unawaited(audio.playEffect(asset)),
    textStyle: const TextStyle(fontFamily: 'Pretendard', color: Colors.white),
    images: images,
    seed: 105,
  );
  final controls = PreviewControls(game, audio);
  preview = createJSInteropWrapper(controls);
  runApp(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        backgroundColor: const Color(0xFF0B1226),
        body: Stack(
          children: [
            GameWidget(game: game, overlayBuilderMap: {BubbleShooter.gameOverOverlayKey: (_, _) => const SizedBox()}),
            Align(
              alignment: Alignment.topLeft,
              child: ScoreHud(score: game.scoreNotifier, pressure: game.pressureNotifier),
            ),
          ],
        ),
      ),
    ),
  );
}
