// 🎯 Dart imports:
import 'dart:developer';

// 📦 Package imports:
import 'package:bloc/bloc.dart';

class AppBlocObserver extends BlocObserver {
  new({this.reportNonFatal});

  void Function(Object, StackTrace)? reportNonFatal;

  @override
  void onChange(BlocBase<dynamic> bloc, Change<dynamic> change) {
    super.onChange(bloc, change);
    log('onChange(${bloc.runtimeType}, $change)');
  }

  @override
  void onError(BlocBase<dynamic> bloc, Object error, StackTrace stackTrace) {
    log('onError(${bloc.runtimeType}, $error, $stackTrace)');
    reportNonFatal?.call(error, stackTrace);
    super.onError(bloc, error, stackTrace);
  }
}
