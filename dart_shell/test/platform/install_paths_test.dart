import 'dart:io';

import 'package:denial_dart_shell/src/platform/install_paths.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temporary;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('denial-install-paths-');
  });

  tearDown(() async {
    await temporary.delete(recursive: true);
  });

  Future<String> writeExecutable(String path) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString('#!/bin/sh\nexit 0\n');
    final chmod = await Process.run('chmod', <String>['700', file.path]);
    expect(chmod.exitCode, 0, reason: chmod.stderr.toString());
    return file.path;
  }

  InstallPaths paths({
    Map<String, String> environment = const <String, String>{},
    String resolvedExecutable = '',
  }) {
    return InstallPaths(
      environment: environment,
      resolvedExecutable: resolvedExecutable,
    );
  }

  test('compiled defaults stay byte-identical without DENIAL_PREFIX', () {
    final defaults = paths();
    expect(defaults.prefix, '/usr');
    expect(defaults.dataDirs.join(':'), '/usr/local/share:/usr/share');
    expect(
      defaults.pathDirs.join(':'),
      '/usr/local/sbin:/usr/local/bin:/usr/bin:/bin',
    );
  });

  test('an explicitly empty search variable stays empty', () {
    final empty = paths(
      environment: const <String, String>{'XDG_DATA_DIRS': '', 'PATH': ''},
    );
    expect(empty.dataDirs, isEmpty);
    expect(empty.pathDirs, isEmpty);
  });

  test('DENIAL_PREFIX relocates the search directories', () async {
    final prefix = p.join(temporary.path, 'nix-store');
    final relocated = paths(
      environment: <String, String>{'DENIAL_PREFIX': prefix},
    );
    expect(relocated.prefix, prefix);
    expect(relocated.dataDirs, <String>[
      p.join(prefix, 'local/share'),
      p.join(prefix, 'share'),
      '/usr/local/share',
      '/usr/share',
    ]);
    expect(relocated.pathDirs, <String>[
      p.join(prefix, 'local/sbin'),
      p.join(prefix, 'local/bin'),
      p.join(prefix, 'bin'),
      '/bin',
      '/usr/bin',
    ]);
  });

  test('a relative or empty DENIAL_PREFIX is ignored', () {
    expect(
      paths(environment: const <String, String>{'DENIAL_PREFIX': 'opt/denial'})
          .prefix,
      '/usr',
    );
    expect(
      paths(environment: const <String, String>{'DENIAL_PREFIX': '  '}).prefix,
      '/usr',
    );
  });

  test('the legacy DENIA_PREFIX spelling still relocates', () {
    final relocated = paths(
      environment: <String, String>{'DENIA_PREFIX': temporary.path},
    );
    expect(relocated.prefix, temporary.path);
  });

  test('DENIAL_PREFIX bin directory resolves a tool', () async {
    final prefix = p.join(temporary.path, 'prefix');
    final tool = await writeExecutable(p.join(prefix, 'bin/denialctl'));
    expect(
      paths(
        environment: <String, String>{'DENIAL_PREFIX': prefix},
      ).findExecutable('denialctl'),
      tool,
    );
  });

  test(
    'the directory holding the running compositor resolves a tool',
    () async {
    final bin = p.join(temporary.path, 'bundle/bin');
    final tool = await writeExecutable(p.join(bin, 'denial-settings'));
    final resolved = paths(
      environment: <String, String>{
        'DENIAL_PREFIX': p.join(temporary.path, 'prefix'),
      },
      resolvedExecutable: p.join(bin, 'deniald'),
    ).findExecutable('denial-settings');
    expect(resolved, tool);
    expect(
      paths(resolvedExecutable: p.join(bin, 'deniald')).executableDirectory,
      bin,
    );
  });

  test('a missing override falls through to the sibling tier', () async {
    final bin = p.join(temporary.path, 'bundle/bin');
    final tool = await writeExecutable(p.join(bin, 'denial-settings'));
    expect(
      paths(
        environment: <String, String>{
          'DENIAL_PREFIX': p.join(temporary.path, 'prefix'),
          'DENIAL_SETTINGS_BINARY': p.join(temporary.path, 'missing'),
        },
        resolvedExecutable: p.join(bin, 'deniald'),
      ).findExecutable(
        'denial-settings',
        overrides: const <String>['DENIAL_SETTINGS_BINARY'],
      ),
      tool,
    );
  });

  test(
    'a configured override wins over the prefix and sibling tiers',
    () async {
    final prefix = p.join(temporary.path, 'prefix');
    await writeExecutable(p.join(prefix, 'bin/denial-settings'));
    final bin = p.join(temporary.path, 'bundle/bin');
    await writeExecutable(p.join(bin, 'denial-settings'));
    final override = await writeExecutable(
      p.join(temporary.path, 'override/denial-settings'),
    );
    expect(
      paths(
        environment: <String, String>{
          'DENIAL_PREFIX': prefix,
          'DENIAL_SETTINGS_BINARY': override,
        },
        resolvedExecutable: p.join(bin, 'deniald'),
      ).findExecutable(
        'denial-settings',
        overrides: const <String>['DENIAL_SETTINGS_BINARY'],
      ),
      override,
    );
  });

  test('a launcher process never contributes its own directory', () async {
    final bin = p.join(temporary.path, 'wrapper/bin');
    await writeExecutable(p.join(bin, 'denial-sibling-probe'));
    expect(
      paths(resolvedExecutable: p.join(bin, 'bash')).executableDirectory,
      isNull,
    );
    expect(
      paths(
        resolvedExecutable: p.join(bin, 'bash'),
      ).findExecutable('denial-sibling-probe'),
      isNull,
    );
  });

  test('PATH resolves a tool when no installation tier matches', () async {
    final bin = p.join(temporary.path, 'host/bin');
    final tool = await writeExecutable(p.join(bin, 'denial-path-probe'));
    expect(
      paths(
        environment: <String, String>{'PATH': bin},
      ).findExecutable('denial-path-probe'),
      tool,
    );
  });

  test('a file without an execute bit is not a tool', () async {
    final bin = p.join(temporary.path, 'plain/bin');
    final file = File(p.join(bin, 'denial-plain-probe'));
    await file.parent.create(recursive: true);
    await file.writeAsString('#!/bin/sh\nexit 0\n');
    final chmod = await Process.run('chmod', <String>['600', file.path]);
    expect(chmod.exitCode, 0, reason: chmod.stderr.toString());
    expect(
      paths(
        environment: <String, String>{'PATH': bin},
      ).findExecutable('denial-plain-probe'),
      isNull,
    );
  });

  test('executable() keeps reporting the compiled default when absent', () {
    final unresolved = paths(
      environment: <String, String>{'PATH': temporary.path},
    );
    expect(
      unresolved.executable(
        'denial-absent-probe',
        overrides: const <String>['DENIAL_ABSENT_PROBE'],
        fallback: '/usr/bin/denial-absent-probe',
      ),
      '/usr/bin/denial-absent-probe',
    );
  });

  test('executable() reports a configured override which is missing', () {
    final configured = p.join(temporary.path, 'configured/denialctl');
    expect(
      paths(
        environment: <String, String>{'DENIAL_CONTROL_TOOL': configured},
      ).executable(
        'denialctl',
        overrides: const <String>['DENIAL_CONTROL_TOOL'],
        fallback: '/usr/bin/denialctl',
      ),
      configured,
    );
  });
}
