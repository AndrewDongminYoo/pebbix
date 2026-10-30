// 🎯 Dart imports:
import 'dart:async';
import 'dart:developer';

// 🐦 Flutter imports:
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

// 📦 Package imports:
import 'package:bloc/bloc.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/app/app_bloc_observer.dart';
import 'package:bubble_shooter/gen/assets.gen.dart';

Future<void> bootstrap(FutureOr<Widget> Function() builder) async {
  // The builder loads SharedPreferences before runApp, so the platform
  // channels must be live first.
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    log(details.exceptionAsString(), stackTrace: details.stack);
  };

  Bloc.observer = AppBlocObserver();

  LicenseRegistry.addLicense(() async* {
    final pretendard = await rootBundle.loadString(Assets.licenses.pretendard.ofl);
    yield LicenseEntryWithLineBreaks(['pretendard'], pretendard);
  });

  // Add cross-flavor configuration here

  runApp(await builder());
}
