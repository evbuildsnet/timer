import 'dart:io';

/// QA hook: a one-shot scene file in the app's temp dir (`tmp/timer_scene`),
/// written by tooling before launch and consumed on read.
String? sceneOverride() {
  final file = File('${Directory.systemTemp.path}/timer_scene');
  if (!file.existsSync()) return null;
  final spec = file.readAsStringSync().trim();
  file.deleteSync();
  return spec;
}
