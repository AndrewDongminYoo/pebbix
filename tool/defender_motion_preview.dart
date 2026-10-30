// Local visual QA entrypoint; release builds use lib/main_*.dart.
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui' as ui;

import 'package:flame/cache.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:bubble_shooter/game/game.dart';
import 'package:bubble_shooter/gen/assets.gen.dart';
import 'package:bubble_shooter/l10n/l10n.dart';

@JS('defenderPreview')
external set preview(JSObject value);

class _MeasuredGame extends BubbleShooter {
  new({required super.l10n, required super.images})
    : super(
        playSfx: (_) {},
        textStyle: const TextStyle(fontFamily: 'Pretendard', color: Colors.white),
        seed: 105,
      );

  final intervals = <double>[];
  final updateMicros = <int>[];
  final renderMicros = <int>[];
  final _watch = Stopwatch();

  @override
  void update(double dt) {
    _watch
      ..reset()
      ..start();
    super.update(dt);
    _watch.stop();
    if (dt > 0 && intervals.length < 1200) {
      intervals.add(dt * 1000);
      updateMicros.add(_watch.elapsedMicroseconds);
    }
  }

  @override
  void render(Canvas canvas) {
    _watch
      ..reset()
      ..start();
    super.render(canvas);
    _watch.stop();
    if (renderMicros.length < 1200) renderMicros.add(_watch.elapsedMicroseconds);
  }
}

@JSExport()
class _DefenderPreview {
  new(this._game, this._decodeMicros, this._rgbaBytes);
  final _MeasuredGame _game;
  final int _decodeMicros;
  final int _rgbaBytes;
  Timer? _freeze;

  void prepare(String scenario) {
    _freeze?.cancel();
    _game
      ..resumeEngine()
      ..startGame();
    final board = BubbleBoard(columns: 8);
    HexCell cell(int row, int col) => HexCell.fromRowCol(row: row, col: col);
    final rows = scenario == 'short' ? 14 : 5;
    for (var row = 0; row <= rows; row++) {
      board.place(cell(row, 3), BubbleColor.red);
    }
    board.place(cell(0, 0), BubbleColor.blue);
    if (scenario == 'drop') {
      board
        ..place(cell(4, 2), BubbleColor.yellow)
        ..place(cell(5, 2), BubbleColor.green)
        ..place(cell(6, 2), BubbleColor.purple)
        ..place(cell(7, 1), BubbleColor.orange);
    }
    _game
      ..board = board
      ..boardComponent.syncBoard()
      ..currentColor = scenario == 'miss' || scenario == 'short' ? BubbleColor.blue : BubbleColor.red
      ..nextShot = (color: BubbleColor.purple, kind: ShotKind.rainbow);
  }

  void aim(double x) => _game.aimAt(Vector2(x, 0));
  void fire() => _game.fire();
  void freezeAfter(double milliseconds) {
    _freeze?.cancel();
    _freeze = Timer(Duration(microseconds: (milliseconds * 1000).round()), _game.pauseEngine);
  }

  void resume() => _game.resumeEngine();
  void pause() => _game.pauseEngine();
  // JS controls call methods with positional arguments.
  // ignore: avoid_positional_boolean_parameters, use_setters_to_change_properties
  void reduceMotion(bool value) => _game.defenderMotion.reducedMotion = value;

  void measure() {
    _game.intervals.clear();
    _game.updateMicros.clear();
    _game.renderMicros.clear();
  }

  String status() => jsonEncode({
    'phase': _game.status.name,
    'shots': _game.shotCount,
    'score': _game.score,
    'paused': _game.paused,
    'angle': _game.aimAngle,
    'loader': _game.defenderMotion.loaderPosition,
    'bubble': _game.defenderMotion.bubblePosition,
    'cheerLift': _game.defenderMotion.cheerLift(),
    'currentKind': _game.currentShot.kind.name,
    'nextKind': _game.nextShot.kind.name,
    'decodeMicros': _decodeMicros,
    'decodedRgbaBytes': _rgbaBytes,
    'frameIntervalsMs': _game.intervals,
    'updateMicros': _game.updateMicros,
    'renderMicros': _game.renderMicros,
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final images = Images(prefix: '');
  final bytes = await rootBundle.load(Assets.images.defenderSquad.path);
  final decode = Stopwatch()..start();
  final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes));
  final frame = await codec.getNextFrame();
  decode.stop();
  codec.dispose();
  images.add(Assets.images.defenderSquad.path, frame.image);
  await images.loadAll(
    Assets.images.values
        .where((asset) => asset.path != Assets.images.defenderSquad.path)
        .map((asset) => asset.path)
        .toList(),
  );
  final game = _MeasuredGame(l10n: await AppLocalizations.delegate.load(const Locale('en')), images: images);
  preview = createJSInteropWrapper(
    _DefenderPreview(game, decode.elapsedMicroseconds, frame.image.width * frame.image.height * 4),
  );
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
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
