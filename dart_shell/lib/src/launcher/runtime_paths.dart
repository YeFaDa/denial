import 'dart:io';

import 'package:path/path.dart' as p;

import '../config/startup_environment.dart';
import '../platform/install_paths.dart';

class RuntimePaths {
  RuntimePaths({
    required Map<String, String> environment,
    String resolvedExecutable = '',
  }) : environment = Map.unmodifiable(environment),
       _install = InstallPaths(
         environment: environment,
         resolvedExecutable: resolvedExecutable,
       );

  final Map<String, String> environment;
  final InstallPaths _install;

  String get homeDir {
    final home = environment['HOME'];
    if (home == null || home.isEmpty) {
      // Fail closed instead of reading or writing another user's home.
      return '/nonexistent';
    }
    return home;
  }

  String get configHome =>
      environment['XDG_CONFIG_HOME'] ?? p.join(homeDir, '.config');

  String get dataHome =>
      environment['XDG_DATA_HOME'] ?? p.join(homeDir, '.local', 'share');

  String get stateHome =>
      environment['XDG_STATE_HOME'] ?? p.join(homeDir, '.local', 'state');

  String get cacheHome =>
      environment['XDG_CACHE_HOME'] ?? p.join(homeDir, '.cache');

  String get wallpaperDirectory =>
      denialEnvironmentValue(environment, 'DENIAL_WALLPAPER_DIR') ??
      p.join(homeDir, 'Pictures', 'Wallpapers');

  List<String> get dataDirs => _install.dataDirs;

  /// `PATH`, or the prefix-relative default when it is unset.
  List<String> get pathDirs => _install.pathDirs;

  String get powerdControlSocketPath =>
      denialEnvironmentValue(environment, 'DENIAL_POWERD_CONTROL_SOCKET') ??
      '/run/denia-powerd/control.sock';

  Future<File> layoutFile() async {
    final dir = Directory(p.join(configHome, 'denia-home'));
    await dir.create(recursive: true);
    return File(p.join(dir.path, 'layout.json'));
  }

  Future<File> wallpaperStateFile() async {
    final dir = Directory(p.join(stateHome, 'denial'));
    await dir.create(recursive: true);
    return File(p.join(dir.path, 'wallpaper'));
  }

  Future<File> notificationPolicyFile() async {
    final dir = Directory(p.join(stateHome, 'denial'));
    await dir.create(recursive: true);
    return File(p.join(dir.path, 'notifications.json'));
  }

  Future<File> applicationRecentsFile() async {
    final dir = Directory(p.join(stateHome, 'denial'));
    await dir.create(recursive: true);
    return File(p.join(dir.path, 'application-recents.json'));
  }

  List<Directory> desktopApplicationDirs() {
    final paths = <String>[
      p.join(dataHome, 'applications'),
      for (final dir in dataDirs) p.join(dir, 'applications'),
      p.join(
        homeDir,
        '.local',
        'share',
        'flatpak',
        'exports',
        'share',
        'applications',
      ),
      '/var/lib/flatpak/exports/share/applications',
    ];

    return uniquePaths(paths).map(Directory.new).toList(growable: false);
  }

  List<String> iconRoots() {
    return uniquePaths([
      dataHome,
      ...dataDirs,
      p.join(homeDir, '.local', 'share', 'flatpak', 'exports', 'share'),
      '/var/lib/flatpak/exports/share',
    ]);
  }

  static List<String> uniquePaths(Iterable<String> paths) {
    return InstallPaths.uniquePaths(paths);
  }
}
