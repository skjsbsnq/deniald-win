import 'package:flutter/material.dart';

import '../../models/ime_frame.dart';
import '../../theme/shell_color_scheme.dart';
import '../../theme/shell_text_theme.dart';
import '../../theme/shell_theme.dart';
import '../../theme/tokens.dart';
import '../shell_backdrop_blur.dart';

/// How the candidate block lays rows out.
///
/// The wire contract does not carry a layout flag; the desktop layer picks
/// [ImePanelLayout.vertical] until a settings or engine hint selects
/// otherwise.
enum ImePanelLayout { vertical, horizontal }

const imeCandidatePanelKey = ValueKey<String>('ime-candidate-panel');
const imePreeditKey = ValueKey<String>('ime-preedit');
const imePreeditCaretKey = ValueKey<String>('ime-preedit-caret');
const imeCompletionKey = ValueKey<String>('ime-completion');
const imeNoticeKey = ValueKey<String>('ime-notice');
const imePageIndicatorKey = ValueKey<String>('ime-page-indicator');
const imeHighlightedAnnotationKey = ValueKey<String>(
  'ime-highlighted-annotation',
);

ValueKey<String> imeCandidateRowKey(int index) =>
    ValueKey<String>('ime-candidate-$index');
ValueKey<String> imeToneMarkKey(int index) =>
    ValueKey<String>('ime-tone-mark-$index');
ValueKey<String> imeCloudBadgeKey(int index) =>
    ValueKey<String>('ime-cloud-badge-$index');

/// Fixed teaching color for `tone_mark` (fresh / new-word) candidates.
///
/// This orange is deliberately NOT theme-derived: the input-engine spec
/// defines it as a semantic "new word" signal that must stay recognizable
/// under every accent palette, brightness, and contrast level.
const Color imeFreshToneColor = Color(0xffff9046);

/// MD3E candidate panel driven by a validated [DenialImeFrame].
///
/// Renders the composing preedit (styled spans plus a UTF-8-byte-offset
/// caret), the candidate list with highlight/annotation/cloud/tone-mark
/// affordances, a whole-sentence completion preview, a transient notice, and
/// a page indicator. An empty frame collapses to nothing.
class ImeCandidatePanel extends StatelessWidget {
  const ImeCandidatePanel({
    required this.frame,
    this.layout = ImePanelLayout.vertical,
    this.onCandidateSelected,
    super.key,
  });

  final DenialImeFrame frame;
  final ImePanelLayout layout;

  /// Called with the selection index when a candidate row is tapped. The
  /// desktop layer wires this to `ImeCommand` once command routing lands.
  final ValueChanged<int>? onCandidateSelected;

  @override
  Widget build(BuildContext context) {
    if (frame.isEmpty) {
      return const SizedBox.shrink();
    }
    final theme = context.shellTheme;
    final colors = context.shellColors;
    final radius = theme.borderRadius(ShellRadii.notification);
    return Semantics(
      container: true,
      child: RepaintBoundary(
        child: ShellBackdropBlur(
          blur: theme.effectivePanelOpacity < 1.0,
          borderRadius: radius,
          child: DecoratedBox(
            decoration: BoxDecoration(
              // Tonal elevation only — panels never paint cast shadows.
              gradient: theme.panelGradient(
                colors.surfaceContainerHigh,
                colors.surfaceContainer,
              ),
              borderRadius: radius,
              border: Border.all(color: colors.hairlineSoft),
            ),
            // ClipRect is the belt to the scrollable candidate list's
            // suspenders: even a layout regression cannot paint rows past
            // the panel's bounds-clamped edge.
            child: ClipRect(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: ShellSpacing.sm,
                  vertical: ShellSpacing.xs,
                ),
                child: switch (layout) {
                  ImePanelLayout.vertical => _ImeVerticalBody(
                    frame: frame,
                    onCandidateSelected: onCandidateSelected,
                  ),
                  ImePanelLayout.horizontal => _ImeHorizontalBody(
                    frame: frame,
                    onCandidateSelected: onCandidateSelected,
                  ),
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Preedit line: styled segments, the byte-offset caret, and the
/// whole-sentence completion ghost to its right.
class _ImePreeditRow extends StatelessWidget {
  const _ImePreeditRow({required this.frame});

  final DenialImeFrame frame;

  TextStyle _spanStyle(
    DenialImePreeditStyle style,
    ShellTextTheme text,
    ShellColorScheme colors,
    ShellAccentPalette accent,
  ) {
    final base = text.titleMedium;
    return switch (style) {
      DenialImePreeditStyle.plain => base,
      DenialImePreeditStyle.underline => base.copyWith(
        decoration: TextDecoration.underline,
        decorationColor: accent.primary,
      ),
      DenialImePreeditStyle.highlight => base.copyWith(
        color: accent.primary,
        backgroundColor: accent.subtle,
      ),
      DenialImePreeditStyle.prediction => base.copyWith(
        color: colors.textTertiary,
      ),
      DenialImePreeditStyle.correction => base.copyWith(
        color: colors.textSecondary,
        decoration: TextDecoration.lineThrough,
        decorationColor: colors.textTertiary,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = context.shellColors;
    final accent = theme.accentPalette;
    final text = theme.text;
    final caretIndex = frame.preeditCaretCodeUnitIndex;
    final baseStyle = text.titleMedium.copyWith(color: colors.textPrimary);

    final spans = <InlineSpan>[];
    var consumed = 0;
    var caretPlaced = false;
    for (final span in frame.preedit) {
      final spanText = span.text;
      final style = _spanStyle(span.style, text, colors, accent);
      final local = caretIndex == null ? -1 : caretIndex - consumed;
      if (!caretPlaced && local >= 0 && local <= spanText.length) {
        // `caretIndex` is always on a code-point boundary (the byte offset
        // is snapped when decoded), so substring never splits a surrogate
        // pair.
        if (local > 0) {
          spans.add(TextSpan(text: spanText.substring(0, local), style: style));
        }
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: _ImePreeditCaret(color: accent.primary, style: baseStyle),
          ),
        );
        caretPlaced = true;
        if (local < spanText.length) {
          spans.add(TextSpan(text: spanText.substring(local), style: style));
        }
      } else if (spanText.isNotEmpty) {
        spans.add(TextSpan(text: spanText, style: style));
      }
      consumed += spanText.length;
    }

    final completion = frame.completion;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: <Widget>[
        Flexible(
          child: Text.rich(
            key: imePreeditKey,
            TextSpan(style: baseStyle, children: spans),
          ),
        ),
        if (completion != null && completion.isNotEmpty) ...<Widget>[
          const SizedBox(width: ShellSpacing.sm),
          Flexible(
            child: Text(
              completion,
              key: imeCompletionKey,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.bodyMedium.copyWith(color: colors.textTertiary),
            ),
          ),
        ],
      ],
    );
  }
}

class _ImePreeditCaret extends StatelessWidget {
  const _ImePreeditCaret({required this.color, required this.style});

  final Color color;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: imePreeditCaretKey,
      // A caret is a one-device-pixel-class accent line: half the smallest
      // spacing step, capped by the preedit line height.
      width: ShellSpacing.xs / 2,
      height: style.fontSize ?? ShellSpacing.lg,
      color: color,
    );
  }
}

/// Shared row/chip content: selection number, tone dot, word, annotation,
/// cloud badge.
class _ImeCandidateContent extends StatelessWidget {
  const _ImeCandidateContent({
    required this.index,
    required this.candidate,
    required this.highlighted,
    required this.showAnnotation,
  });

  final int index;
  final DenialImeCandidate candidate;
  final bool highlighted;
  final bool showAnnotation;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = context.shellColors;
    final text = theme.text;
    final annotation = candidate.annotation;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          width: ShellSpacing.xl,
          child: Text(
            '${index + 1}',
            style: text.labelSmall.copyWith(color: colors.textSecondary),
          ),
        ),
        if (candidate.toneMark)
          Padding(
            padding: const EdgeInsets.only(right: ShellSpacing.xs),
            child: _ImeToneDot(index: index),
          ),
        Flexible(
          child: Text(
            candidate.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: (highlighted ? text.titleMediumEmphasized : text.titleMedium)
                .copyWith(color: colors.textPrimary),
          ),
        ),
        if (showAnnotation &&
            annotation != null &&
            annotation.isNotEmpty) ...<Widget>[
          const SizedBox(width: ShellSpacing.sm),
          Flexible(
            child: Text(
              annotation,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall.copyWith(color: colors.textSecondary),
            ),
          ),
        ],
        if (candidate.fromCloud)
          Padding(
            padding: const EdgeInsets.only(left: ShellSpacing.xs),
            child: Icon(
              Icons.cloud_outlined,
              key: imeCloudBadgeKey(index),
              size: ShellSpacing.lg,
              color: colors.textSecondary,
            ),
          ),
      ],
    );
  }
}

/// The fixed orange dot marking a `tone_mark` candidate as a fresh word.
class _ImeToneDot extends StatelessWidget {
  const _ImeToneDot({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: imeToneMarkKey(index),
      width: ShellSpacing.sm,
      height: ShellSpacing.sm,
      decoration: const BoxDecoration(
        color: imeFreshToneColor,
        shape: BoxShape.circle,
      ),
    );
  }
}

/// Transient engine notice, painted below the preedit.
class _ImeNoticeRow extends StatelessWidget {
  const _ImeNoticeRow({required this.notice});

  final String notice;

  @override
  Widget build(BuildContext context) {
    final colors = context.shellColors;
    final text = context.shellTheme.text;
    return Padding(
      padding: const EdgeInsets.only(top: ShellSpacing.xs),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.info_outline_rounded,
            size: ShellSpacing.lg,
            color: colors.textSecondary,
          ),
          const SizedBox(width: ShellSpacing.xs),
          Flexible(
            child: Text(
              notice,
              key: imeNoticeKey,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall.copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// `pageIndex + 1 / pageCount` indicator.
class _ImePageIndicator extends StatelessWidget {
  const _ImePageIndicator({required this.frame});

  final DenialImeFrame frame;

  @override
  Widget build(BuildContext context) {
    final colors = context.shellColors;
    final text = context.shellTheme.text;
    return Text(
      '${frame.pageIndex + 1}/${frame.pageCount}',
      key: imePageIndicatorKey,
      style: text.labelSmall.copyWith(color: colors.textSecondary),
    );
  }
}

class _ImeVerticalBody extends StatelessWidget {
  const _ImeVerticalBody({
    required this.frame,
    required this.onCandidateSelected,
  });

  final DenialImeFrame frame;
  final ValueChanged<int>? onCandidateSelected;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final accent = theme.accentPalette;
    final showPageIndicator = frame.pageCount > 1;
    final notice = frame.notice;
    // IntrinsicWidth sizes the panel to the widest row (clamped by the
    // layer's output bound) while `stretch` keeps every tile — including its
    // highlight pill — at that shared width.
    return IntrinsicWidth(
      child: Column(
        key: imeCandidatePanelKey,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (frame.preedit.isNotEmpty ||
              (frame.completion?.isNotEmpty ?? false))
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: ShellSpacing.sm,
                vertical: ShellSpacing.xs,
              ),
              child: _ImePreeditRow(frame: frame),
            ),
          if (notice != null && notice.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: ShellSpacing.sm),
              child: _ImeNoticeRow(notice: notice),
            ),
          // A frame may carry up to 64 candidate rows — far taller than a
          // short output's bounds-clamped panel. The list takes whatever
          // the preedit, notice and page indicator leave behind and scrolls,
          // so nothing ever paints outside the panel.
          if (frame.candidates.isNotEmpty)
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (
                      var index = 0;
                      index < frame.candidates.length;
                      index += 1
                    )
                      _ImeCandidateTile(
                        index: index,
                        candidate: frame.candidates[index],
                        highlighted: index == frame.highlighted,
                        highlightColor: accent.subtle,
                        highlightRadius: theme.borderRadius(
                          ShellShapeScale.small,
                        ),
                        onSelected: onCandidateSelected,
                      ),
                  ],
                ),
              ),
            ),
          if (showPageIndicator)
            Padding(
              padding: const EdgeInsets.only(
                top: ShellSpacing.xs,
                right: ShellSpacing.sm,
              ),
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: _ImePageIndicator(frame: frame),
              ),
            ),
        ],
      ),
    );
  }
}

class _ImeCandidateTile extends StatelessWidget {
  const _ImeCandidateTile({
    required this.index,
    required this.candidate,
    required this.highlighted,
    required this.highlightColor,
    required this.highlightRadius,
    required this.onSelected,
  });

  final int index;
  final DenialImeCandidate candidate;
  final bool highlighted;
  final Color highlightColor;
  final BorderRadius highlightRadius;
  final ValueChanged<int>? onSelected;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: highlighted,
      child: GestureDetector(
        key: imeCandidateRowKey(index),
        behavior: HitTestBehavior.opaque,
        onTap: onSelected == null ? null : () => onSelected!(index),
        child: MouseRegion(
          cursor: onSelected == null
              ? MouseCursor.defer
              : SystemMouseCursors.click,
          child: Container(
            decoration: highlighted
                ? BoxDecoration(
                    color: highlightColor,
                    borderRadius: highlightRadius,
                  )
                : null,
            padding: const EdgeInsets.symmetric(
              horizontal: ShellSpacing.sm,
              vertical: ShellSpacing.xs,
            ),
            child: _ImeCandidateContent(
              index: index,
              candidate: candidate,
              highlighted: highlighted,
              showAnnotation: true,
            ),
          ),
        ),
      ),
    );
  }
}

class _ImeHorizontalBody extends StatelessWidget {
  const _ImeHorizontalBody({
    required this.frame,
    required this.onCandidateSelected,
  });

  final DenialImeFrame frame;
  final ValueChanged<int>? onCandidateSelected;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = context.shellColors;
    final text = theme.text;
    final highlightedAnnotation = frame.highlightedCandidate?.annotation;
    final notice = frame.notice;
    return Column(
      key: imeCandidatePanelKey,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (frame.preedit.isNotEmpty || (frame.completion?.isNotEmpty ?? false))
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: ShellSpacing.sm,
              vertical: ShellSpacing.xs,
            ),
            child: _ImePreeditRow(frame: frame),
          ),
        if (notice != null && notice.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: ShellSpacing.sm),
            child: _ImeNoticeRow(notice: notice),
          ),
        Padding(
          padding: const EdgeInsets.all(ShellSpacing.xs),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (var index = 0; index < frame.candidates.length; index += 1)
                // A bounded flex share keeps each chip's inner Flexible
                // working (a non-flex chip would receive unbounded width and
                // the row would overflow on long words) and divides the row
                // evenly, ellipsizing words instead of spilling.
                Flexible(
                  fit: FlexFit.loose,
                  child: _ImeCandidateChip(
                    index: index,
                    candidate: frame.candidates[index],
                    highlighted: index == frame.highlighted,
                    onSelected: onCandidateSelected,
                  ),
                ),
              if (frame.pageCount > 1) ...<Widget>[
                const SizedBox(width: ShellSpacing.sm),
                _ImePageIndicator(frame: frame),
              ],
            ],
          ),
        ),
        if (highlightedAnnotation != null && highlightedAnnotation.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(
              left: ShellSpacing.sm,
              right: ShellSpacing.sm,
              bottom: ShellSpacing.xs,
            ),
            child: Text(
              highlightedAnnotation,
              key: imeHighlightedAnnotationKey,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall.copyWith(color: colors.textSecondary),
            ),
          ),
      ],
    );
  }
}

class _ImeCandidateChip extends StatelessWidget {
  const _ImeCandidateChip({
    required this.index,
    required this.candidate,
    required this.highlighted,
    required this.onSelected,
  });

  final int index;
  final DenialImeCandidate candidate;
  final bool highlighted;
  final ValueChanged<int>? onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final accent = theme.accentPalette;
    return Semantics(
      button: true,
      selected: highlighted,
      child: GestureDetector(
        key: imeCandidateRowKey(index),
        behavior: HitTestBehavior.opaque,
        onTap: onSelected == null ? null : () => onSelected!(index),
        child: MouseRegion(
          cursor: onSelected == null
              ? MouseCursor.defer
              : SystemMouseCursors.click,
          child: Container(
            decoration: BoxDecoration(
              color: highlighted ? accent.subtle : null,
              borderRadius: theme.borderRadius(ShellShapeScale.full),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: ShellSpacing.sm,
              vertical: ShellSpacing.xs,
            ),
            child: _ImeCandidateContent(
              index: index,
              candidate: candidate,
              highlighted: highlighted,
              // Horizontal layout paints the highlighted item's annotation
              // on its own line instead of inside the chip row.
              showAnnotation: false,
            ),
          ),
        ),
      ),
    );
  }
}
