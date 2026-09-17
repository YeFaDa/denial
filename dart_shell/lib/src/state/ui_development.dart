import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/startup_environment.dart';
import '../models/ui_development.dart';
import '../platform/denial_bridge.dart';
import '../platform/install_paths.dart';
import 'shell_controller.dart';

final uiDevelopmentProvider =
    NotifierProvider<UiDevelopmentController, DenialUiDevelopmentState>(
      UiDevelopmentController.new,
    );

final uiWorkspaceSetupProvider = Provider<UiWorkspaceSetupService>((ref) {
  final startup = ref.watch(startupEnvironmentProvider);
  return SystemUiWorkspaceSetupService(
    environment: startup.values,
    resolvedExecutable: startup.resolvedExecutable,
  );
});

abstract interface class UiWorkspaceSetupService {
  bool get available;

  Future<void> setup();
}

class SystemUiWorkspaceSetupService implements UiWorkspaceSetupService {
  SystemUiWorkspaceSetupService({
    Map<String, String> environment = const <String, String>{},
    String resolvedExecutable = '',
  }) : _environment = environment,
       _paths = InstallPaths(
         environment: environment,
         resolvedExecutable: resolvedExecutable,
       );

  final Map<String, String> _environment;
  final InstallPaths _paths;

  String get _controlTool => _paths.executable(
    'denialctl',
    overrides: const <String>['DENIAL_CONTROL_TOOL'],
    fallback: '/usr/bin/denialctl',
  );

  String get _developmentTool => _paths.executable(
    'denial-ui',
    overrides: const <String>['DENIAL_DEVELOPMENT_TOOL'],
    fallback: '/usr/bin/denial-ui',
  );

  @override
  bool get available =>
      _resolvesTool('denialctl', 'DENIAL_CONTROL_TOOL') &&
      _resolvesTool('denial-ui', 'DENIAL_DEVELOPMENT_TOOL');

  bool _resolvesTool(String name, String variable) =>
      _paths.findExecutable(name, overrides: <String>[variable]) != null;

  @override
  Future<void> setup() async {
    if (!available) {
      throw const UiWorkspaceSetupException(
        'Install denial-ui-development before creating an editable UI.',
      );
    }
    final result = await Process.run(_controlTool, const <String>[
      '--json',
      'ui',
      'setup',
    ], environment: _environment);
    if (result.exitCode == 0) {
      return;
    }
    final stderr = result.stderr.toString().trim();
    final stdout = result.stdout.toString().trim();
    throw UiWorkspaceSetupException(
      stderr.isNotEmpty
          ? stderr
          : stdout.isNotEmpty
          ? stdout
          : 'denialctl exited with status ${result.exitCode}.',
    );
  }
}

class UiWorkspaceSetupException implements Exception {
  const UiWorkspaceSetupException(this.message);

  final String message;

  @override
  String toString() => message;
}

class UiDevelopmentController extends Notifier<DenialUiDevelopmentState> {
  StreamSubscription<DenialUiDevelopmentState>? _subscription;
  late DenialBridge _bridge;

  @override
  DenialUiDevelopmentState build() {
    _bridge = ref.watch(denialBridgeProvider);
    unawaited(_subscription?.cancel());
    _subscription = _bridge.uiDevelopmentStates.listen((next) {
      state = next;
    });
    ref.onDispose(() {
      unawaited(_subscription?.cancel());
      _subscription = null;
    });
    scheduleMicrotask(() {
      _bridge.queryUiDevelopmentState();
    });
    return DenialUiDevelopmentState.connecting();
  }

  void refresh() {
    _bridge.queryUiDevelopmentState();
  }

  void setLiveDevelopmentEnabled(bool enabled) {
    if (enabled) {
      _bridge.enableLiveUiDevelopment();
    } else {
      _bridge.disableLiveUiDevelopment();
    }
  }

  bool setWorkspace(String path) {
    final normalized = path.trim();
    if (normalized.isEmpty) {
      return false;
    }
    return _bridge.setUiDevelopmentWorkspace(normalized) != 0;
  }

  void setAutoReload(bool enabled) {
    _bridge.setUiDevelopmentAutoReload(enabled);
  }

  void hotReload() {
    _bridge.hotReloadUi();
  }

  void hotRestart() {
    _bridge.hotRestartUi();
  }

  void buildAndActivateOptimized() {
    _bridge.buildAndActivateOptimizedUi();
  }

  void revertLastWorking() {
    _bridge.revertLastWorkingUi();
  }

  void restoreOfficial() {
    _bridge.restoreOfficialUi();
  }
}
