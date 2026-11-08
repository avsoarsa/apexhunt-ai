import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

/// Offline-first JSON document store in the app's private documents directory.
/// Career data never leaves the device except when the user runs an AI step.
class LocalStore {
  LocalStore._(this._root);
  final Directory? _root;
  final Map<String, Object?> _memory = {};

  static Future<LocalStore> open() async {
    if (kIsWeb) return LocalStore._(null);
    final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/apexhunt');
    await dir.create(recursive: true);
    return LocalStore._(dir);
  }

  /// In-memory store for tests and web previews.
  factory LocalStore.memory() => LocalStore._(null);

  File _file(String name) => File('${_root!.path}/$name');

  Future<Object?> readJson(String name) async {
    if (_root == null) return _memory[name];
    final f = _file(name);
    if (!await f.exists()) return null;
    try {
      return jsonDecode(await f.readAsString());
    } catch (_) {
      return null;
    }
  }

  Future<void> writeJson(String name, Object? value) async {
    if (_root == null) {
      _memory[name] = jsonDecode(jsonEncode(value));
      return;
    }
    final f = _file(name);
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(value), flush: true);
    await tmp.rename(f.path);
  }

  Future<void> delete(String name) async {
    if (_root == null) {
      _memory.remove(name);
      return;
    }
    final f = _file(name);
    if (await f.exists()) await f.delete();
  }

  Future<String> writeBytes(String name, Uint8List bytes) async {
    if (_root == null) {
      _memory[name] = bytes;
      return name;
    }
    final f = _file(name);
    await f.parent.create(recursive: true);
    await f.writeAsBytes(bytes, flush: true);
    return f.path;
  }

  Future<Uint8List?> readBytes(String name) async {
    if (_root == null) return _memory[name] as Uint8List?;
    final f = _file(name);
    return await f.exists() ? f.readAsBytes() : null;
  }

  String? pathOf(String name) => _root == null ? null : _file(name).path;

  Future<void> wipe() async {
    _memory.clear();
    if (_root != null && await _root.exists()) {
      await _root.delete(recursive: true);
      await _root.create(recursive: true);
    }
  }
}

/// BYOK API keys live only in Android Keystore-backed encrypted storage.
class SecureVault {
  SecureVault([FlutterSecureStorage? storage]) : _s = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _s;
  final Map<String, String> _webFallback = {};

  static const _byokKey = 'byok_api_key';

  Future<String?> readByokKey() async {
    if (kIsWeb) return _webFallback[_byokKey];
    try {
      return await _s.read(key: _byokKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> writeByokKey(String? value) async {
    if (kIsWeb) {
      value == null ? _webFallback.remove(_byokKey) : _webFallback[_byokKey] = value;
      return;
    }
    if (value == null || value.isEmpty) {
      await _s.delete(key: _byokKey);
    } else {
      await _s.write(key: _byokKey, value: value);
    }
  }

  Future<void> wipe() async {
    _webFallback.clear();
    if (!kIsWeb) await _s.deleteAll();
  }
}
