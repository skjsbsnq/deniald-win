import 'dart:convert';

import 'package:flutter/widgets.dart';

/// Shell-facing input-engine contract (protocol/input-engine-v1.md).
///
/// `ImeFrame` is an authoritative snapshot of what the candidate panel shows
/// right now — never a delta. Rust validates the untrusted engine payload,
/// republishes it over `denial/wire/to_flutter`, and the codec revalidates
/// every bound before these models are built.

/// Which editor endpoint the engine currently talks to.
enum DenialImeEndpointKind { none, waylandTextInput, flutter, legacy }

/// Engine lifecycle reported through `ImeState`.
enum DenialImeEngineStatus { offline, starting, ready, error }

/// Engine input mode reported through `ImeState`.
enum DenialImeInputMode { latin, chinese }

/// Display hint carried by one preedit segment.
///
/// [correction] maps to the wire `ImePreeditStyle.Correction` value and is
/// rendered with a deletion line: corrected or replaced text keeps a
/// strikethrough instead of vanishing silently.
enum DenialImePreeditStyle {
  plain,
  underline,
  highlight,
  prediction,
  correction,
}

/// One preedit segment: bounded text plus a display hint.
@immutable
class DenialImePreeditSpan {
  const DenialImePreeditSpan({
    required this.text,
    this.style = DenialImePreeditStyle.plain,
  });

  final String text;
  final DenialImePreeditStyle style;

  @override
  bool operator ==(Object other) {
    return other is DenialImePreeditSpan &&
        other.text == text &&
        other.style == style;
  }

  @override
  int get hashCode => Object.hash(text, style);
}

/// One candidate row. Its position inside [DenialImeFrame.candidates] is its
/// selection index.
@immutable
class DenialImeCandidate {
  const DenialImeCandidate({
    required this.text,
    this.annotation,
    this.fromCloud = false,
    this.toneMark = false,
  });

  final String text;
  final String? annotation;

  /// Pure display hints: the panel may badge cloud-sourced candidates and
  /// tone-marked readings. They never change commit semantics.
  final bool fromCloud;
  final bool toneMark;

  @override
  bool operator ==(Object other) {
    return other is DenialImeCandidate &&
        other.text == text &&
        other.annotation == annotation &&
        other.fromCloud == fromCloud &&
        other.toneMark == toneMark;
  }

  @override
  int get hashCode => Object.hash(text, annotation, fromCloud, toneMark);
}

/// Authoritative snapshot of what the candidate panel should show right now.
///
/// A frame with no preedit, candidates, completion or notice collapses the
/// panel — see [isEmpty].
@immutable
class DenialImeFrame {
  const DenialImeFrame({
    required this.serial,
    this.preedit = const <DenialImePreeditSpan>[],
    this.preeditCursor = -1,
    this.candidates = const <DenialImeCandidate>[],
    this.highlighted = -1,
    this.pageIndex = 0,
    this.pageCount = 0,
    this.completion,
    this.notice,
    this.caret,
  });

  /// Activation serial this frame renders; receivers drop stale serials.
  final int serial;

  final List<DenialImePreeditSpan> preedit;

  /// UTF-8 byte offset of the caret inside the concatenated preedit text;
  /// `-1` when the engine reports no explicit caret.
  final int preeditCursor;

  final List<DenialImeCandidate> candidates;

  /// Index into [candidates]; `-1` when nothing is highlighted.
  final int highlighted;

  final int pageIndex;
  final int pageCount;

  /// Whole-sentence completion preview, painted to the right of the preedit.
  final String? completion;

  /// Transient engine message, painted below the preedit.
  final String? notice;

  /// Caret rectangle in global scene coordinates.
  ///
  /// The wire `ImeFrame` carries no caret field yet — T03 delivers it with
  /// the frame or an endpoint event — so the decoder leaves this null and
  /// the panel layer falls back to pointer/window geometry. Tests inject it
  /// directly to exercise caret-anchored placement.
  final Rect? caret;

  /// Empty frames hide the panel.
  bool get isEmpty =>
      preedit.every((span) => span.text.isEmpty) &&
      candidates.isEmpty &&
      (completion == null || completion!.isEmpty) &&
      (notice == null || notice!.isEmpty);

  /// Concatenated preedit text the [preeditCursor] byte offset indexes into.
  String get preeditText => preedit.map((span) => span.text).join();

  /// Code-unit index of the preedit caret inside [preeditText], or null when
  /// the engine reported no explicit caret.
  ///
  /// [preeditCursor] is a UTF-8 byte offset; a mid-sequence offset snaps back
  /// to the previous code-point boundary so a caret never splits a
  /// multi-byte character (or a surrogate pair).
  int? get preeditCaretCodeUnitIndex =>
      imePreeditCaretCodeUnitIndex(preedit, preeditCursor);

  /// Candidate the panel treats as highlighted, or null.
  DenialImeCandidate? get highlightedCandidate =>
      highlighted >= 0 && highlighted < candidates.length
      ? candidates[highlighted]
      : null;
}

/// Converts a UTF-8 byte offset into the concatenated [spans] text into a
/// Dart code-unit index snapped to a code-point boundary.
///
/// Returns null when [byteOffset] is negative (the contract's `-1` "no
/// explicit caret" value) and clamps it into `[0, byteLength]` otherwise.
int? imePreeditCaretCodeUnitIndex(
  List<DenialImePreeditSpan> spans,
  int byteOffset,
) {
  if (byteOffset < 0) {
    return null;
  }
  final text = spans.map((span) => span.text).join();
  final bytes = utf8.encode(text);
  var offset = byteOffset.clamp(0, bytes.length);
  // A UTF-8 continuation byte (10xxxxxx) means the offset splits a
  // multi-byte sequence; walk back to the sequence's lead byte.
  while (offset > 0 &&
      offset < bytes.length &&
      (bytes[offset] & 0xC0) == 0x80) {
    offset -= 1;
  }
  return utf8.decode(bytes.sublist(0, offset)).length;
}

/// Authoritative engine/session state for the shell indicator.
///
/// [serial] is the current activation serial; zero means no engine is
/// active.
@immutable
class DenialImeState {
  const DenialImeState({
    this.serial = 0,
    this.engine = DenialImeEngineStatus.offline,
    this.endpoint = DenialImeEndpointKind.none,
    this.mode = DenialImeInputMode.latin,
    this.cloudEnabled = false,
    this.error,
  });

  final int serial;
  final DenialImeEngineStatus engine;
  final DenialImeEndpointKind endpoint;
  final DenialImeInputMode mode;
  final bool cloudEnabled;
  final String? error;

  @override
  bool operator ==(Object other) {
    return other is DenialImeState &&
        other.serial == serial &&
        other.engine == engine &&
        other.endpoint == endpoint &&
        other.mode == mode &&
        other.cloudEnabled == cloudEnabled &&
        other.error == error;
  }

  @override
  int get hashCode =>
      Object.hash(serial, engine, endpoint, mode, cloudEnabled, error);
}
