// dart format width=80

/// GENERATED CODE - DO NOT MODIFY BY HAND
/// *****************************************************
///  FlutterGen
/// *****************************************************

// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: deprecated_member_use,directives_ordering,implicit_dynamic_list_literal,unnecessary_import

import 'package:flutter/widgets.dart';

class $AssetsAudioGen {
  const $AssetsAudioGen();

  /// File path: assets/audio/background.mp3
  String get background => 'assets/audio/background.mp3';

  /// File path: assets/audio/bomb.mp3
  String get bomb => 'assets/audio/bomb.mp3';

  /// File path: assets/audio/descent.mp3
  String get descent => 'assets/audio/descent.mp3';

  /// File path: assets/audio/gameover.mp3
  String get gameover => 'assets/audio/gameover.mp3';

  /// File path: assets/audio/pop.mp3
  String get pop => 'assets/audio/pop.mp3';

  /// File path: assets/audio/rainbow.mp3
  String get rainbow => 'assets/audio/rainbow.mp3';

  /// File path: assets/audio/shoot.mp3
  String get shoot => 'assets/audio/shoot.mp3';

  /// List of all assets
  List<String> get values => [
    background,
    bomb,
    descent,
    gameover,
    pop,
    rainbow,
    shoot,
  ];
}

class $AssetsImagesGen {
  const $AssetsImagesGen();

  /// File path: assets/images/background.png
  AssetGenImage get background =>
      const AssetGenImage('assets/images/background.png');

  /// File path: assets/images/bubble_blue.png
  AssetGenImage get bubbleBlue =>
      const AssetGenImage('assets/images/bubble_blue.png');

  /// File path: assets/images/bubble_green.png
  AssetGenImage get bubbleGreen =>
      const AssetGenImage('assets/images/bubble_green.png');

  /// File path: assets/images/bubble_orange.png
  AssetGenImage get bubbleOrange =>
      const AssetGenImage('assets/images/bubble_orange.png');

  /// File path: assets/images/bubble_purple.png
  AssetGenImage get bubblePurple =>
      const AssetGenImage('assets/images/bubble_purple.png');

  /// File path: assets/images/bubble_red.png
  AssetGenImage get bubbleRed =>
      const AssetGenImage('assets/images/bubble_red.png');

  /// File path: assets/images/bubble_yellow.png
  AssetGenImage get bubbleYellow =>
      const AssetGenImage('assets/images/bubble_yellow.png');

  /// File path: assets/images/defender_squad.png
  AssetGenImage get defenderSquad =>
      const AssetGenImage('assets/images/defender_squad.png');

  /// File path: assets/images/shooter_arm.png
  AssetGenImage get shooterArm =>
      const AssetGenImage('assets/images/shooter_arm.png');

  /// File path: assets/images/shooter_body_idle.png
  AssetGenImage get shooterBodyIdle =>
      const AssetGenImage('assets/images/shooter_body_idle.png');

  /// File path: assets/images/shooter_body_shooting.png
  AssetGenImage get shooterBodyShooting =>
      const AssetGenImage('assets/images/shooter_body_shooting.png');

  /// List of all assets
  List<AssetGenImage> get values => [
    background,
    bubbleBlue,
    bubbleGreen,
    bubbleOrange,
    bubblePurple,
    bubbleRed,
    bubbleYellow,
    defenderSquad,
    shooterArm,
    shooterBodyIdle,
    shooterBodyShooting,
  ];
}

class $AssetsLicensesGen {
  const $AssetsLicensesGen();

  /// Directory path: assets/licenses/audio
  $AssetsLicensesAudioGen get audio => const $AssetsLicensesAudioGen();

  /// Directory path: assets/licenses/pretendard
  $AssetsLicensesPretendardGen get pretendard =>
      const $AssetsLicensesPretendardGen();
}

class $AssetsLicensesAudioGen {
  const $AssetsLicensesAudioGen();

  /// File path: assets/licenses/audio/MANIFEST.md
  String get manifest => 'assets/licenses/audio/MANIFEST.md';

  /// List of all assets
  List<String> get values => [manifest];
}

class $AssetsLicensesPretendardGen {
  const $AssetsLicensesPretendardGen();

  /// File path: assets/licenses/pretendard/MANIFEST.md
  String get manifest => 'assets/licenses/pretendard/MANIFEST.md';

  /// File path: assets/licenses/pretendard/OFL.txt
  String get ofl => 'assets/licenses/pretendard/OFL.txt';

  /// List of all assets
  List<String> get values => [manifest, ofl];
}

abstract final class Assets {
  static const $AssetsAudioGen audio = $AssetsAudioGen();
  static const $AssetsImagesGen images = $AssetsImagesGen();
  static const $AssetsLicensesGen licenses = $AssetsLicensesGen();
}

class AssetGenImage {
  const AssetGenImage(
    this._assetName, {
    this.size,
    this.flavors = const {},
    this.animation,
  });

  final String _assetName;

  final Size? size;
  final Set<String> flavors;
  final AssetGenImageAnimation? animation;

  Image image({
    Key? key,
    AssetBundle? bundle,
    ImageFrameBuilder? frameBuilder,
    ImageErrorWidgetBuilder? errorBuilder,
    String? semanticLabel,
    bool excludeFromSemantics = false,
    double? scale,
    double? width,
    double? height,
    Color? color,
    Animation<double>? opacity,
    BlendMode? colorBlendMode,
    BoxFit? fit,
    AlignmentGeometry alignment = Alignment.center,
    ImageRepeat repeat = ImageRepeat.noRepeat,
    Rect? centerSlice,
    bool matchTextDirection = false,
    bool gaplessPlayback = true,
    bool isAntiAlias = false,
    String? package,
    FilterQuality filterQuality = FilterQuality.medium,
    int? cacheWidth,
    int? cacheHeight,
  }) {
    return Image.asset(
      _assetName,
      key: key,
      bundle: bundle,
      frameBuilder: frameBuilder,
      errorBuilder: errorBuilder,
      semanticLabel: semanticLabel,
      excludeFromSemantics: excludeFromSemantics,
      scale: scale,
      width: width,
      height: height,
      color: color,
      opacity: opacity,
      colorBlendMode: colorBlendMode,
      fit: fit,
      alignment: alignment,
      repeat: repeat,
      centerSlice: centerSlice,
      matchTextDirection: matchTextDirection,
      gaplessPlayback: gaplessPlayback,
      isAntiAlias: isAntiAlias,
      package: package,
      filterQuality: filterQuality,
      cacheWidth: cacheWidth,
      cacheHeight: cacheHeight,
    );
  }

  ImageProvider provider({AssetBundle? bundle, String? package}) {
    return AssetImage(_assetName, bundle: bundle, package: package);
  }

  String get path => _assetName;

  String get keyName => _assetName;
}

class AssetGenImageAnimation {
  const AssetGenImageAnimation({
    required this.isAnimation,
    required this.duration,
    required this.frames,
  });

  final bool isAnimation;
  final Duration duration;
  final int frames;
}
