import 'dart:convert';

import '../platform/denial_bridge.dart';
import 'shell_settings.dart';

abstract interface class SettingsStore {
  Future<ShellSettings?> read();

  Future<void> write(ShellSettings settings);
}

abstract interface class SettingsDocumentTransport {
  Future<DenialSettingsDocument> read();

  Future<DenialSettingsDocument> write({
    required int expectedRevision,
    required String document,
  });
}

abstract interface class SettingsDocumentUpdateSource {
  /// Emits the complete authoritative document immediately on subscription,
  /// then emits a complete document for every later revision.
  Stream<DenialSettingsDocument> get settingsDocumentUpdates;
}

class DenialSettingsDocumentTransport
    implements SettingsDocumentTransport, SettingsDocumentUpdateSource {
  const DenialSettingsDocumentTransport(this._bridge);

  final DenialBridge _bridge;

  @override
  Stream<DenialSettingsDocument> get settingsDocumentUpdates =>
      _bridge.settingsDocuments;

  @override
  Future<DenialSettingsDocument> read() => _bridge.readSettingsDocument();

  @override
  Future<DenialSettingsDocument> write({
    required int expectedRevision,
    required String document,
  }) => _bridge.writeSettingsDocument(
    expectedRevision: expectedRevision,
    document: document,
  );
}

/// Shell-facing projection of deniald's shared settings document.
///
/// The compositor is the only process that opens `settings.json`. This class
/// retains a revision token, sends typed bridge requests, and retries once
/// after a concurrent native keyboard update advances the shared document.
class NativeSettingsStore
    implements SettingsStore, SettingsDocumentUpdateSource {
  NativeSettingsStore(this._transport);

  final SettingsDocumentTransport _transport;
  Future<void> _writeQueue = Future<void>.value();
  int _revision = 0;
  int? _documentVersion;

  @override
  Stream<DenialSettingsDocument> get settingsDocumentUpdates =>
      _transport is SettingsDocumentUpdateSource
      ? (_transport as SettingsDocumentUpdateSource).settingsDocumentUpdates
            .map(_rememberDocument)
      : const Stream<DenialSettingsDocument>.empty();

  @override
  Future<ShellSettings?> read() async => _decode(await _readDocument());

  @override
  Future<void> write(ShellSettings settings) {
    final write = _writeQueue.then((_) => _write(settings));
    _writeQueue = write.catchError((_) {});
    return write;
  }

  Future<void> _write(ShellSettings settings) async {
    if (_revision <= 0) {
      await _readDocument();
    }
    try {
      final response = await _transport.write(
        expectedRevision: _revision,
        document: _encodeShellDocument(settings),
      );
      _revision = response.revision;
    } on StateError {
      // A keyboard update and a shell preference can be committed in either
      // order. Refresh the token and replay the shell projection once; Rust
      // preserves the native-owned keyboard section during this write. The
      // payload is re-encoded so a schema version learned from the refreshed
      // document reaches the retried write.
      await _readDocument();
      final response = await _transport.write(
        expectedRevision: _revision,
        document: _encodeShellDocument(settings),
      );
      _revision = response.revision;
    }
  }

  /// Encodes the shell projection for `settings.document.apply`.
  ///
  /// The compositor validates and owns the shared document, including its
  /// schema version. Shell-written payloads echo the version of the last
  /// authoritative document instead of [ShellSettings.schemaVersion], so a
  /// compositor built at a different schema revision still accepts the write.
  /// Without a remembered document the shell's own version is emitted.
  String _encodeShellDocument(ShellSettings settings) {
    final json = settings.toJson();
    final documentVersion = _documentVersion;
    if (documentVersion != null) {
      json['version'] = documentVersion;
    }
    return '${const JsonEncoder.withIndent('  ').convert(json)}\n';
  }

  Future<DenialSettingsDocument> _readDocument() async {
    return _rememberDocument(await _transport.read());
  }

  DenialSettingsDocument _rememberDocument(DenialSettingsDocument document) {
    if (document.revision <= 0) {
      throw StateError('Denial returned an invalid settings revision');
    }
    if (document.revision > _revision) {
      _revision = document.revision;
    }
    final version = _documentVersionOf(document.json);
    if (version != null) {
      _documentVersion = version;
    }
    return document;
  }

  static int? _documentVersionOf(String json) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is Map<String, dynamic>) {
        final version = decoded['version'];
        if (version is int && version > 0) {
          return version;
        }
      }
    } on Object {
      // Malformed documents are surfaced by read() and the update stream;
      // the version probe stays best effort.
    }
    return null;
  }

  ShellSettings _decode(DenialSettingsDocument document) {
    final decoded = jsonDecode(document.json);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Denial settings root is not an object');
    }
    return ShellSettings.fromJson(decoded);
  }
}
