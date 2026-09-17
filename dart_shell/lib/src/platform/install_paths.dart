import 'dart:io';

import 'package:path/path.dart' as p;

import '../config/startup_environment.dart';

/// Resolves Denial's installed executables and default search directories.
///
/// Denial ships prebuilt Flutter bundles, and compiled Dart cannot be
/// relocated after the fact, so a compiled-in `/usr` default would tie every
/// installation to one filesystem layout. Resolution therefore happens at
/// runtime, in this order:
///
/// 1. the caller's explicit environment override,
/// 2. [prefixVariable], so one variable relocates every compiled default,
/// 3. the directory holding the running executable,
/// 4. the conventional `/usr` location,
/// 5. `PATH`.
///
/// Every candidate except an absolute override must exist and be executable,
/// so an entry which is absent for the current layout yields the next one.
class InstallPaths {
  InstallPaths({
    required Map<String, String> environment,
    String resolvedExecutable = '',
  }) : environment = Map<String, String>.unmodifiable(environment),
       _resolvedExecutable = resolvedExecutable.trim();

  factory InstallPaths.fromStartup(StartupEnvironment startup) {
    return InstallPaths(
      environment: startup.values,
      resolvedExecutable: startup.resolvedExecutable,
    );
  }

  /// Relocates every compiled default, for example to a Nix store path.
  static const String prefixVariable = 'DENIAL_PREFIX';

  /// Prefix assumed when [prefixVariable] is unset or not absolute.
  static const String defaultPrefix = '/usr';

  /// Names whose owning process is a shell or a toolchain launcher rather than
  /// a Denial program. Their directory says nothing about the installation: a
  /// wrapper script reports its interpreter through `/proc/self/exe`.
  static const Set<String> _launcherNames = <String>{
    'bash',
    'dart',
    'dash',
    'env',
    'flutter',
    'ksh',
    'sh',
    'zsh',
  };

  final Map<String, String> environment;
  final String _resolvedExecutable;

  /// Installation prefix. A relative override is ignored rather than resolved
  /// against an arbitrary working directory.
  String get prefix {
    final configured = denialEnvironmentValue(
      environment,
      prefixVariable,
    )?.trim();
    if (configured == null || configured.isEmpty || !p.isAbsolute(configured)) {
      return defaultPrefix;
    }
    return p.normalize(configured);
  }

  /// Directory holding the Denial program which loaded this process, or `null`
  /// when it cannot identify an installation.
  String? get executableDirectory {
    if (_resolvedExecutable.isEmpty || !p.isAbsolute(_resolvedExecutable)) {
      return null;
    }
    final name = p.basename(_resolvedExecutable);
    if (name.isEmpty || _launcherNames.contains(name)) {
      return null;
    }
    final directory = p.dirname(_resolvedExecutable);
    if (directory.isEmpty || directory == p.rootPrefix(directory)) {
      return null;
    }
    return p.normalize(directory);
  }

  /// Search order for an executable name.
  List<String> get binaryDirectories {
    final sibling = executableDirectory;
    return uniquePaths(<String>[
      p.join(prefix, 'bin'),
      if (sibling != null) sibling,
      '/usr/bin',
      ...pathDirs,
    ]);
  }

  /// Resolves [name] to an absolute path, or `null` when no candidate exists.
  String? findExecutable(
    String name, {
    List<String> overrides = const <String>[],
  }) {
    if (name.isEmpty) {
      return null;
    }
    for (final variable in overrides) {
      final configured = denialEnvironmentValue(environment, variable)?.trim();
      if (configured == null || configured.isEmpty) {
        continue;
      }
      if (p.isAbsolute(configured)) {
        if (_isExecutableFile(configured)) {
          return configured;
        }
        continue;
      }
      final found = _searchBinary(configured);
      if (found != null) {
        return found;
      }
    }
    return _searchBinary(name);
  }

  /// Resolves [name] like [findExecutable], falling back to the configured or
  /// compiled default so a caller keeps reporting the same missing
  /// installation it reported before.
  String executable(
    String name, {
    List<String> overrides = const <String>[],
    required String fallback,
  }) {
    final found = findExecutable(name, overrides: overrides);
    if (found != null) {
      return found;
    }
    for (final variable in overrides) {
      final configured = denialEnvironmentValue(environment, variable)?.trim();
      if (configured != null &&
          configured.isNotEmpty &&
          p.isAbsolute(configured)) {
        return configured;
      }
    }
    return fallback;
  }

  /// `XDG_DATA_DIRS`, or the prefix-relative default when it is unset.
  ///
  /// An explicitly empty value stays "no directories", which is how Denial has
  /// always read the variable.
  List<String> get dataDirs {
    final configured = environment['XDG_DATA_DIRS'];
    if (configured != null) {
      return splitPaths(configured);
    }
    return uniquePaths(<String>[
      p.join(prefix, 'local/share'),
      p.join(prefix, 'share'),
      '/usr/local/share',
      '/usr/share',
    ]);
  }

  /// `PATH`, or the prefix-relative default when it is unset.
  List<String> get pathDirs {
    final configured = environment['PATH'];
    if (configured != null) {
      return splitPaths(configured);
    }
    return uniquePaths(<String>[
      p.join(prefix, 'local/sbin'),
      p.join(prefix, 'local/bin'),
      p.join(prefix, 'bin'),
      '/bin',
      '/usr/bin',
    ]);
  }

  String? _searchBinary(String name) {
    for (final directory in binaryDirectories) {
      final candidate = p.join(directory, name);
      if (_isExecutableFile(candidate)) {
        return candidate;
      }
    }
    return null;
  }

  /// A regular file carrying at least one execute bit. Links are followed, so
  /// a profile symlink or a `security.wrappers` entry qualifies.
  static bool _isExecutableFile(String path) {
    final stat = FileStat.statSync(path);
    if (stat.type != FileSystemEntityType.file) {
      return false;
    }
    return stat.mode & 0x49 != 0;
  }

  static List<String> splitPaths(String value) {
    return value
        .split(':')
        .where((path) => path.isNotEmpty)
        .toList(growable: false);
  }

  /// Drops empty and repeated entries while preserving order.
  static List<String> uniquePaths(Iterable<String> paths) {
    final seen = <String>{};
    final unique = <String>[];
    for (final path in paths) {
      if (path.isEmpty || !seen.add(path)) {
        continue;
      }
      unique.add(path);
    }
    return unique;
  }
}
