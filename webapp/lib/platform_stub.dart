import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

/// Stub implementations of `dart:io` types for web platform.
/// Used via conditional import:
/// `import 'platform_stub.dart' if (dart.library.io) 'dart:io';`

class Platform {
  static bool get isWindows => false;
  static bool get isLinux => false;
  static bool get isMacOS => false;
  static String get resolvedExecutable => '';
  static Map<String, String> get environment => {};
}

class File {
  final String path;
  File(this.path);
  bool existsSync() => false;
  Future<bool> exists() async => false;
  Future<String> readAsString() async => '';
  String readAsStringSync() => '';
  Future<void> writeAsString(String contents) async {}
  Future<void> delete() async {}
  Future<File> copy(String destination) async => File(destination);
  void copySync(String destination) {
    throw UnsupportedError('File.copySync not supported on web');
  }

  Future<File> rename(String newPath) async => File(newPath);
  Uint8List readAsBytesSync() => Uint8List(0);
  Future<Uint8List> readAsBytes() async => Uint8List(0);

  Directory get parent => Directory('');
}

class Directory {
  final String path;
  Directory(this.path);
  Future<Directory> create({bool recursive = false}) async => this;
  bool existsSync() => false;
  static Directory get current => Directory('');
  Directory get parent => Directory('');
}

/// Stub WebSocket — minimal implementation to avoid compilation errors on web.
/// Real-time notification features will be gracefully disabled on web.
class WebSocket {
  dynamic _closeCode;
  dynamic _closeReason;
  StreamController? _controller;
  Stream? _stream;
  bool _isConnected = false;

  WebSocket._();

  static Future<WebSocket> connect(
    String url, {
    Iterable<String>? protocols,
  }) async {
    // On web, WebSocket from dart:html would be used.
    // This stub returns a disconnected socket.
    final ws = WebSocket._();
    ws._isConnected = false;
    debugPrint('[WebSocket Stub] Connection to $url skipped (web stub).');
    return ws;
  }

  Stream get stream => _stream ?? const Stream.empty();
  void close([int? code, String? reason]) {
    _isConnected = false;
  }

  Stream listen(
    void Function(dynamic event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return const Stream.empty();
  }
}

/// Stub ProcessResult — minimal implementation to avoid compilation errors on web.
class ProcessResult {
  final int exitCode;
  final String stdout;
  final String stderr;
  ProcessResult(this.exitCode, this.stdout, this.stderr);
}

/// Stub Process — provides a minimal interface that always returns empty results.
class Process {
  static Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
  }) async {
    return ProcessResult(-1, '', 'Process.run not supported on web');
  }
}
