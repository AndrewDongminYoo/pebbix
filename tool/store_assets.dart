import 'dart:io';

import 'store_assets/store_assets.dart';

Future<void> main(List<String> arguments) async {
  try {
    await runStoreAssetsCommand(
      arguments: arguments,
      repositoryRoot: Directory.current.absolute.path,
    );
  } on StoreAssetException catch (error) {
    stderr.writeln(error.message);
    exitCode = 1;
  } on Object catch (error) {
    final command = arguments.isEmpty ? '<none>' : arguments.join(' ');
    stderr.writeln('Unexpected store-assets failure for command "$command" (${error.runtimeType}): $error');
    exitCode = 1;
  }
}
