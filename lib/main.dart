import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'engine/scene_override.dart';
import 'engine/store.dart';
import 'platform/scene_env.dart';
import 'ui/stage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
      ['Roboto Flex'],
      await rootBundle.loadString('assets/licenses/RobotoFlex-OFL.txt'),
    );
  });
  final (store, program) = await (
    Store.open(),
    ui.FragmentProgram.fromAsset('shaders/world.frag'),
  ).wait;
  // QA deep links only exist in debug builds or builds made with --dart-define=QA=true.
  if (kDebugMode || const bool.fromEnvironment('QA')) {
    final scene = parseScene(sceneOverride(), DateTime.now().millisecondsSinceEpoch);
    if (scene != null) store.session = scene;
  }
  runApp(TimerApp(store: store, program: program));
}

class TimerApp extends StatelessWidget {
  const TimerApp({super.key, required this.store, required this.program});

  final Store store;
  final ui.FragmentProgram program;

  @override
  Widget build(BuildContext context) {
    return WidgetsApp(
      title: 'Timer',
      color: const Color(0xFF0B0A09),
      debugShowCheckedModeBanner: false,
      builder: (context, _) => Stage(store: store, program: program),
    );
  }
}
