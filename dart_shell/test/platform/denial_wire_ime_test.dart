import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:denial_dart_shell/src/models/ime_frame.dart';
import 'package:denial_dart_shell/src/platform/denial_wire.dart';

Uint8List _frameEnvelope(ImeFrameObjectBuilder frame, {int sequence = 1}) {
  return EnvelopeObjectBuilder(
    protocolVersion: 1,
    sequence: sequence,
    requestId: 0,
    payloadType: PayloadTypeId.ImeFrame,
    payload: frame,
  ).toBytes('DENW');
}

void main() {
  test('ImeFrame decodes spans, candidates, paging, completion, notice', () {
    final codec = DenialWireCodec();
    final bytes = _frameEnvelope(
      ImeFrameObjectBuilder(
        serial: 7,
        preedit: <ImePreeditSpanObjectBuilder>[
          ImePreeditSpanObjectBuilder(
            text: 'ni',
            style: ImePreeditStyle.Underline,
          ),
          ImePreeditSpanObjectBuilder(
            text: 'hao',
            style: ImePreeditStyle.Prediction,
          ),
        ],
        preeditCursor: 2,
        candidates: <ImeCandidateObjectBuilder>[
          ImeCandidateObjectBuilder(
            text: '你好',
            annotation: 'hello',
            fromCloud: true,
            toneMark: true,
          ),
          ImeCandidateObjectBuilder(text: '尼号'),
        ],
        highlighted: 0,
        pageIndex: 0,
        pageCount: 2,
        completion: '你好世界',
        notice: 'engine warm',
      ),
    );

    final envelope = codec.decodeStructured(ByteData.sublistView(bytes));
    expect(envelope, isNotNull);
    expect(envelope!.payloadType, PayloadTypeId.ImeFrame);
    expect(envelope.payload, isA<ImeFrame>());

    final frame = codec.decodeImeFrame(envelope.payload as ImeFrame);
    expect(frame, isNotNull);
    expect(frame!.serial, 7);
    expect(frame.preedit, hasLength(2));
    expect(frame.preedit[0].style, DenialImePreeditStyle.underline);
    expect(frame.preedit[1].style, DenialImePreeditStyle.prediction);
    expect(frame.preeditCursor, 2);
    expect(frame.candidates, hasLength(2));
    expect(frame.candidates[0].annotation, 'hello');
    expect(frame.candidates[0].fromCloud, isTrue);
    expect(frame.candidates[0].toneMark, isTrue);
    expect(frame.candidates[1].annotation, isNull);
    expect(frame.highlighted, 0);
    expect(frame.pageIndex, 0);
    expect(frame.pageCount, 2);
    expect(frame.completion, '你好世界');
    expect(frame.notice, 'engine warm');
    expect(frame.caret, isNull);
    expect(frame.isEmpty, isFalse);
  });

  test('ImeFrame maps a Correction span to the strikethrough style', () {
    final codec = DenialWireCodec();
    final bytes = _frameEnvelope(
      ImeFrameObjectBuilder(
        serial: 4,
        preedit: <ImePreeditSpanObjectBuilder>[
          ImePreeditSpanObjectBuilder(
            text: 'shi',
            style: ImePreeditStyle.Underline,
          ),
          ImePreeditSpanObjectBuilder(
            text: 'de',
            style: ImePreeditStyle.Correction,
          ),
          ImePreeditSpanObjectBuilder(
            text: 'ji',
            style: ImePreeditStyle.Prediction,
          ),
        ],
        preeditCursor: 3,
      ),
    );

    final envelope = codec.decodeStructured(ByteData.sublistView(bytes));
    expect(envelope, isNotNull);
    final frame = codec.decodeImeFrame(envelope!.payload as ImeFrame);
    expect(frame, isNotNull);
    expect(frame!.preedit, hasLength(3));
    expect(frame.preedit[0].style, DenialImePreeditStyle.underline);
    expect(frame.preedit[1].style, DenialImePreeditStyle.correction);
    expect(frame.preedit[2].style, DenialImePreeditStyle.prediction);
  });

  test(
    'rejected ImeFrame/ImeState payloads bump rejectedStructuredMessages',
    () {
      final codec = DenialWireCodec();
      DenialImeFrame? decodeFrame(ImeFrameObjectBuilder frame) {
        final envelope = codec.decodeStructured(
          ByteData.sublistView(_frameEnvelope(frame)),
        );
        return envelope == null
            ? null
            : codec.decodeImeFrame(envelope.payload as ImeFrame);
      }

      var rejected = 0;
      // Over-limit candidate vector.
      expect(
        decodeFrame(
          ImeFrameObjectBuilder(
            serial: 1,
            candidates: List<ImeCandidateObjectBuilder>.generate(
              65,
              (index) => ImeCandidateObjectBuilder(text: 'c$index'),
            ),
            pageCount: 1,
          ),
        ),
        isNull,
      );
      expect(codec.rejectedStructuredMessages, rejected += 1);
      // Contract-invariant violation (highlighted out of range).
      expect(
        decodeFrame(
          ImeFrameObjectBuilder(
            serial: 1,
            candidates: <ImeCandidateObjectBuilder>[
              ImeCandidateObjectBuilder(text: 'a'),
            ],
            highlighted: 1,
            pageCount: 1,
          ),
        ),
        isNull,
      );
      expect(codec.rejectedStructuredMessages, rejected += 1);
      // A valid frame does not count.
      expect(decodeFrame(ImeFrameObjectBuilder(serial: 1)), isNotNull);
      expect(codec.rejectedStructuredMessages, rejected);

      // ImeState with an over-limit error string.
      final stateBytes = EnvelopeObjectBuilder(
        protocolVersion: 1,
        sequence: 9,
        requestId: 0,
        payloadType: PayloadTypeId.ImeState,
        payload: ImeStateObjectBuilder(serial: 1, error: 'e' * 4097),
      ).toBytes('DENW');
      final stateEnvelope = codec.decodeStructured(
        ByteData.sublistView(stateBytes),
      );
      expect(stateEnvelope, isNotNull);
      expect(codec.decodeImeState(stateEnvelope!.payload as ImeState), isNull);
      expect(codec.rejectedStructuredMessages, rejected += 1);
    },
  );

  test('ImeFrame rejects over-limit vectors and strings', () {
    final codec = DenialWireCodec();
    DenialImeFrame? decode(ImeFrameObjectBuilder frame) {
      final bytes = _frameEnvelope(frame);
      final envelope = codec.decodeStructured(ByteData.sublistView(bytes));
      expect(envelope, isNotNull);
      return codec.decodeImeFrame(envelope!.payload as ImeFrame);
    }

    expect(
      decode(
        ImeFrameObjectBuilder(
          serial: 1,
          candidates: List<ImeCandidateObjectBuilder>.generate(
            65,
            (index) => ImeCandidateObjectBuilder(text: 'c$index'),
          ),
          highlighted: -1,
          pageCount: 1,
        ),
      ),
      isNull,
    );
    expect(
      decode(
        ImeFrameObjectBuilder(
          serial: 1,
          preedit: List<ImePreeditSpanObjectBuilder>.generate(
            65,
            (index) => ImePreeditSpanObjectBuilder(text: 's$index'),
          ),
        ),
      ),
      isNull,
    );
    expect(
      decode(
        ImeFrameObjectBuilder(
          serial: 1,
          candidates: <ImeCandidateObjectBuilder>[
            ImeCandidateObjectBuilder(text: 'a' * 4097),
          ],
          pageCount: 1,
        ),
      ),
      isNull,
    );
    expect(
      decode(ImeFrameObjectBuilder(serial: 1, notice: 'n' * 4097)),
      isNull,
    );
  });

  test('ImeFrame enforces contract invariants', () {
    final codec = DenialWireCodec();
    DenialImeFrame? decode(ImeFrameObjectBuilder frame) {
      final bytes = _frameEnvelope(frame);
      final envelope = codec.decodeStructured(ByteData.sublistView(bytes));
      return envelope == null
          ? null
          : codec.decodeImeFrame(envelope.payload as ImeFrame);
    }

    // highlighted must be -1 or a valid index.
    expect(
      decode(
        ImeFrameObjectBuilder(
          serial: 1,
          candidates: <ImeCandidateObjectBuilder>[
            ImeCandidateObjectBuilder(text: 'a'),
          ],
          highlighted: 1,
          pageCount: 1,
        ),
      ),
      isNull,
    );
    // page_count 0 requires no candidate state.
    expect(
      decode(
        ImeFrameObjectBuilder(
          serial: 1,
          candidates: <ImeCandidateObjectBuilder>[
            ImeCandidateObjectBuilder(text: 'a'),
          ],
          pageCount: 0,
        ),
      ),
      isNull,
    );
    // page_index must stay below page_count.
    expect(
      decode(
        ImeFrameObjectBuilder(
          serial: 1,
          candidates: <ImeCandidateObjectBuilder>[
            ImeCandidateObjectBuilder(text: 'a'),
          ],
          highlighted: 0,
          pageIndex: 2,
          pageCount: 2,
        ),
      ),
      isNull,
    );
    // preedit_cursor must be -1 or inside the concatenated byte length.
    expect(
      decode(
        ImeFrameObjectBuilder(
          serial: 1,
          preedit: <ImePreeditSpanObjectBuilder>[
            ImePreeditSpanObjectBuilder(text: 'abc'),
          ],
          preeditCursor: 4,
        ),
      ),
      isNull,
    );
    // Candidate rows need text.
    expect(
      decode(
        ImeFrameObjectBuilder(
          serial: 1,
          candidates: <ImeCandidateObjectBuilder>[
            ImeCandidateObjectBuilder(text: ''),
          ],
          pageCount: 1,
        ),
      ),
      isNull,
    );
    // A fully empty frame is legal — the panel collapses on it.
    expect(decode(ImeFrameObjectBuilder(serial: 9))?.isEmpty, isTrue);
  });

  test('ImeState decodes engine, endpoint, mode, cloud, error', () {
    final codec = DenialWireCodec();
    final bytes = EnvelopeObjectBuilder(
      protocolVersion: 1,
      sequence: 2,
      requestId: 0,
      payloadType: PayloadTypeId.ImeState,
      payload: ImeStateObjectBuilder(
        serial: 7,
        engine: ImeEngineStatus.Ready,
        endpoint: ImeEndpointKind.Legacy,
        mode: ImeInputMode.Chinese,
        cloudEnabled: true,
        error: 'transient',
      ),
    ).toBytes('DENW');

    final envelope = codec.decodeStructured(ByteData.sublistView(bytes));
    expect(envelope, isNotNull);
    final state = codec.decodeImeState(envelope!.payload as ImeState);
    expect(state, isNotNull);
    expect(state!.serial, 7);
    expect(state.engine, DenialImeEngineStatus.ready);
    expect(state.endpoint, DenialImeEndpointKind.legacy);
    expect(state.mode, DenialImeInputMode.chinese);
    expect(state.cloudEnabled, isTrue);
    expect(state.error, 'transient');
  });

  test('ImeState rejects an over-limit error string', () {
    final codec = DenialWireCodec();
    final bytes = EnvelopeObjectBuilder(
      protocolVersion: 1,
      sequence: 3,
      requestId: 0,
      payloadType: PayloadTypeId.ImeState,
      payload: ImeStateObjectBuilder(serial: 1, error: 'e' * 4097),
    ).toBytes('DENW');

    final envelope = codec.decodeStructured(ByteData.sublistView(bytes));
    expect(envelope, isNotNull);
    expect(codec.decodeImeState(envelope!.payload as ImeState), isNull);
  });
}
