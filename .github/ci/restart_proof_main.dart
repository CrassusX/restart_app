// Entrypoint for the CI restart-proof smoke app. CI copies this file into a
// freshly created Flutter desktop app that depends on restart_app, runs it,
// and asserts that a second process instance writes the proof file.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:restart_app/restart_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // HOME/USERPROFILE stays stable across the relaunch on every desktop
  // platform, including macOS sandboxed apps (where HOME is the container).
  final home = Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      Directory.systemTemp.path;
  final dir = Directory('$home/restart_app_ci_proof');
  await dir.create(recursive: true);
  final marker = File('${dir.path}/first_launch.txt');
  final proof = File('${dir.path}/restart_proof.txt');
  final resultFile = File('${dir.path}/restart_result.txt');

  final firstLaunch = !marker.existsSync();

  runApp(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text(
            firstLaunch ? 'first launch pid=$pid' : 'relaunched pid=$pid',
          ),
        ),
      ),
    ),
  );

  if (firstLaunch) {
    marker.writeAsStringSync('first_pid=$pid');
    // Give the engine a moment to settle, then request the restart.
    await Future<void>.delayed(const Duration(seconds: 3));
    final capability = await Restart.restartCapability();
    final result = await Restart.restartApp();
    resultFile.writeAsStringSync(
      [
        'success=${result.success}',
        'mode=${result.mode.name}',
        'code=${result.code}',
        'message=${result.message}',
        'cap.fullProcessRestart=${capability.fullProcessRestart}',
        'cap.platformDefaultMode=${capability.platformDefaultMode.name}',
      ].join('\n'),
    );
  } else {
    proof.writeAsStringSync(
      'RESTARTED_OK second_pid=$pid ${marker.readAsStringSync()}',
    );
  }
}
