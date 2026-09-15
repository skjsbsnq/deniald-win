# Denial input-engine protocol v1

`input-engine-v1` is the private contract between `deniald` and one
session-scoped input engine — the process that turns physical keys into
composed text and candidates (for example a pinyin engine). It exists beside,
not instead of, `zwp_input_method_v2`: an engine that cannot speak this
protocol can still integrate through Wayland.

This document is the single artifact shared with engine implementations.
Denial ships its own FlatBuffers schema (`protocol/ime.fbs`); engines
implement the same semantics with their own types. No generated code, paths,
file descriptors, or credentials cross this boundary.

FlatBuffers was chosen over a hand-rolled packet for three reasons: the
schema gives both sides an explicit, evolvable contract (tail-appended
fields, explicit defaults, unions); the generated code flows through the
same pinned `flatc` toolchain as the `DENW` bridge
(`tools/generate-denial-wire`), so versioning and `--check` stay uniform;
and the FlatBuffers verifier gives `deniald` bounded parsing of untrusted
engine frames for free, which is the security posture this channel requires.

## Transport and handshake

`deniald` listens on a `SOCK_SEQPACKET` Unix socket at:

```text
$XDG_RUNTIME_DIR/denial/ime.sock
```

The directory is mode `0700` and the socket mode `0600`; only same-user
peers can connect, matching `control.sock` and `portal.sock` policy. Denial
accepts at most one engine connection at a time; a new connection replaces
the previous one after the old peer is drained.

Every packet is exactly one FlatBuffers `Denial.Ime.ImeEnvelope` with file
identifier `IEMG`, protocol version `1`, and a per-direction monotonic
`sequence` starting at 1. `sequence` exists for logging and loss detection
only; ordering authority comes from serials (below). Receivers must size
their `SOCK_SEQPACKET` buffer to the full 1 MiB bound or detect truncation
with `MSG_TRUNC`; a truncated packet is a protocol error and closes the
socket.

The engine's first packet must be `ImeHello` with
`client_version` equal to the envelope `protocol_version`. A version
mismatch, a missing hello, or a malformed packet closes the socket. Denial
sends no payload of any kind until it has received a valid `ImeHello`.

## Activation model and serials

Activation mirrors `input-method-v2` semantics with Denial as the only
timing authority:

- `ImeActivate` opens an activation and carries a fresh compositor-owned
  `serial`: a `uint64` generation that starts at 1, never repeats within a
  connection, and is never 0 — zero is the "no engine active" sentinel used
  by the shell-facing `ImeState`.
- `ImeEditorUpdate` replaces the mutable editor state wholesale inside an
  activation. It is never a patch: every field restates its current value,
  and an absent `surrounding_text` or `cursor_rectangle` means the endpoint
  does not provide one. The internal `change_cause` of an editor update is
  deliberately not forwarded: engine input is always a full-state snapshot,
  so the cause carries no information the engine could act on.
- `ImeDeactivate` ends the activation. The engine must emit nothing further
  for that serial and must clear panel state.
- `ImeDone` closes a state batch and is mandatory: `ImeActivate` and every
  maximal run of consecutive `ImeEditorUpdate` messages each form a group
  that is illegal until its `ImeDone` arrives. `ImeKeyEvent` and the reverse
  commands below are standalone and never part of a group. `ImeDeactivate`
  is self-contained, implicitly discards any open group, and needs no
  `ImeDone`. The engine must apply a group atomically when its `ImeDone`
  lands and must not expose half-applied editor state to its own UI.

Every activation-scoped payload in both directions carries the activation
`serial` it belongs to (`ImeHello` and `ImeStatus` are connection-scoped and
do not). Both sides drop payloads whose serial is not the current one, which
makes stale frames, stale commits, and stale panel commands harmless by
construction. The serial is an activation generation, not a frame counter:
commands that refer to "the frame" mean the most recent `ImeFrame` the
engine published for that serial.

Whenever the focused editor's endpoint kind changes, Denial closes the
current activation and opens a new one with a fresh serial; an
`ImeEditorUpdate` never changes `endpoint` in place.

## Endpoint kinds

`ImeEndpointKind` tells the engine what the focused editor can do:

| Endpoint | Surrounding text | Cursor rect | Inline preedit | Delete-surrounding | Commit delivery |
| --- | --- | --- | --- | --- | --- |
| `WaylandTextInput` | yes (≤4000 B) | yes | yes | yes | `commit_string`/`done` |
| `Flutter` | yes (≤4000 B) | yes | yes | yes | Flutter text-input channel |
| `Legacy` | never | never | panel-only | never | synthesized keysym path |
| `None` | n/a | n/a | n/a | n/a | n/a |

`Legacy` covers X11 clients and Wayland clients without text-input that are
reached through Denial's focused-seat fallback. On a legacy endpoint the
engine must assume: no surrounding text, no caret geometry (Denial places
the panel from window geometry instead), no `ImeDeleteSurrounding`, and any
`ImeInlinePreedit` is shown only inside the candidate panel, never echoed
into the application. Commits still work: Denial converts them into
synthesized key events the legacy client can consume.

`None` means no editor currently holds text focus. `ImeActivate` is never
sent with `None`; the value exists so the shell-facing `ImeState` can report
"no endpoint" and so both schemas share one numbering.

X11 limitation: the fallback cannot obtain `content_purpose` from an X11
client, so password/PIN detection — which normally suppresses the engine —
does not fire on legacy endpoints. Session policy (the engine-enable switch)
is the only guard there; engines must not infer sensitivity from `app_id`.

## deniald → engine messages

| Payload | Fields | Meaning |
| --- | --- | --- |
| `ImeActivate` | `serial`, `endpoint`, `app_id`, `content_hint`, `content_purpose`, `cursor_rectangle`, `surrounding_text`, `surrounding_cursor`, `surrounding_anchor`, `config` | Begin activation with a full snapshot. `app_id` is the focused client's Wayland app-id, empty when unknown. `content_hint`/`content_purpose` are text-input-v3 numeric values passed through verbatim. `surrounding_text` is ≤4000 bytes with cursor/anchor as UTF-8 byte offsets. `config` is the resolved engine configuration snapshot. |
| `ImeEditorUpdate` | `serial`, `app_id`, `content_hint`, `content_purpose`, `cursor_rectangle`, `surrounding_text`, `surrounding_cursor`, `surrounding_anchor` | Full replacement of mutable editor state. |
| `ImeDeactivate` | `serial` | End the activation. |
| `ImeDone` | `serial` | Close the current state batch (mandatory; see grouping rules). |
| `ImeKeyEvent` | `serial`, `keycode`, `modifiers`, `pressed`, `key_id` | One raw physical key event. `keycode` is the evdev/Linux input-event code; `key_id` is a per-activation counter starting at 1 that stays unique under autorepeat; `pressed` distinguishes press from release. See "Forwarded keys" below. |
| `ImeSelectCandidate` | `serial`, `index` | Panel point-select: commit the candidate at `index` of the latest frame for this activation. |
| `ImePageCandidates` | `serial`, `delta` | Page the candidate list; only the sign of `delta` is meaningful. |
| `ImeSetInputMode` | `serial`, `mode`, `cloud` | Shell-requested mode change; `cloud` is a tri-state override. |
| `ImeReloadConfiguration` | `serial`, `config` | Drop in-memory state and apply the attached new snapshot atomically. |

### Forwarded keys

While the engine owns composing input, Denial forwards physical keys as
`ImeKeyEvent` instead of delivering them to the endpoint. The engine must
answer every forwarded key with `ImeKeyResult` echoing the same `key_id`:

- `handled=true`: the engine consumed the key; Denial drops the original
  event. Any commits or frames the key produced arrive as their own
  payloads.
- `handled=false`: Denial reinjects the event to the focused endpoint
  through the normal seat path, preserving ordering with subsequent seat
  events as if the detour never happened.
- No answer within 100 ms: Denial treats the key exactly as if
  `handled=false` had arrived. Timeouts reinject rather than drop because a
  lost keypress is worse than an uncomposed one; a late `ImeKeyResult` for
  an already-reinjected `key_id` is ignored. Results for `key_id`s not
  currently in flight are likewise ignored.
- Residual race: if the engine consumed a timed-out key anyway, commits it
  produced may still arrive, and Denial cannot attribute them to the
  reinjected event — the endpoint can observe both the reinjected raw key
  and the commit text. Engines should answer within the timeout to stay
  on the safe side of this race.

Denial may pipeline: it does not wait for one `ImeKeyResult` before sending
the next `ImeKeyEvent`, and the engine may answer in any order. `key_id`
(not `keycode`) is the match key precisely because autorepeat makes
`keycode`+`pressed` ambiguous. Engines that reorder must not let a
late-committed string overtake an earlier reinjected key's text effect on
the same endpoint.

`modifiers` deliberately carries only Shift, Ctrl, Alt, and Super — the
modifiers meaningful to composing input. Lock state (Caps Lock, Num Lock)
is not a held modifier: the engine observes the keys that toggle locks as
ordinary `ImeKeyEvent`s. Reserved modifier bits are always sent as zero; an
engine receiving nonzero reserved bits may treat the event as a protocol
error.

## engine → deniald messages

| Payload | Fields | Meaning |
| --- | --- | --- |
| `ImeHello` | `client_version`, `name`, `version` | First packet; optional human-readable identity for diagnostics. |
| `ImeKeyResult` | `serial`, `key_id`, `handled` | Per-key verdict for a forwarded `ImeKeyEvent`; see above. |
| `ImeFrame` | `serial`, `preedit`, `preedit_cursor`, `candidates`, `highlighted`, `page_index`, `page_count`, `completion`, `notice` | Panel snapshot (below). |
| `ImeCommitText` | `serial`, `text` | Commit text into the active endpoint; maps to `commit_string`/`done` for Wayland editors, the Flutter text-input channel for shell editors, and the synthesized keysym path on legacy endpoints. |
| `ImeInlinePreedit` | `serial`, `text`, `cursor_begin`, `cursor_end` | Inline composing text for capable endpoints; a null `text` clears it. Cursor offsets are UTF-8 byte offsets, `-1` for no caret. |
| `ImeDeleteSurrounding` | `serial`, `before_bytes`, `after_bytes` | Delete UTF-8 bytes around the caret. Refused on `Legacy` endpoints; Denial may refuse generally. |
| `ImeModeState` | `serial`, `mode`, `cloud_enabled` | Engine-originated mode/cloud state, republished to the shell. |
| `ImeStatus` | `status`, `error` | `Starting`/`Ready`/`Error` lifecycle plus a bounded diagnostic string. `Offline` is reserved and must never be sent by an engine. |

### Frame semantics

`ImeFrame` is a snapshot — *what the panel should look like right now* — not
a stream of deltas:

- `preedit` is an ordered list of `{text, style}` spans; `preedit_cursor` is
  a UTF-8 byte offset into their concatenation (`-1` = no explicit caret).
  `style` is a display hint: `Plain`, `Underline`, `Highlight`,
  `Prediction`, `Correction` (a strikethrough for deleted/replaced text).
- `candidates` rows carry `{text, annotation, from_cloud, tone_mark}`.
  Position in the vector is the selection index. `from_cloud`/`tone_mark`
  badge the row only; they never alter commit behavior.
- `highlighted` is the active candidate index, `-1` for none;
  `page_index`/`page_count` describe the current page (0-based). A
  `page_count` of 0 means "no candidate state" and requires an empty
  `candidates` vector and `highlighted = -1`.
- `completion` is a whole-sentence completion preview; `notice` is a
  transient engine message.
- An empty frame — no preedit, no candidates, no completion, no notice —
  collapses the candidate panel.

## Shell bridge

The candidate panel and mode indicator are ordinary shell UI. Rust
validates each engine payload, then republishes it to the embedded shell as
`Denial.Wire` envelopes — never forwarding engine bytes verbatim:

- `ImeFrame` (native → Dart): the validated panel snapshot.
- `ImeState` (native → Dart): `serial`, `engine` (`Offline`/`Starting`/
  `Ready`/`Error`), `endpoint`, `mode`, `cloud_enabled`, `error`.
  `serial` 0 means no active engine.
- `ImeCommand` (Dart → native): `kind` (`SelectCandidate`, `PagePrevious`,
  `PageNext`, `SetInputMode`, `ReloadConfiguration`), the `serial` of the
  activation whose latest frame was acted on, `index`, `mode`, `cloud`.
  Native drops commands whose serial is stale and validates kind-specific
  fields before translating: `SelectCandidate` requires `index` inside the
  latest frame's candidate range; `SetInputMode` requires `mode` and `cloud`
  in enum range; `PagePrevious`/`PageNext`/`ReloadConfiguration` take no
  fields. A command failing validation is rejected, not forwarded.

## Bounds

Every limit is enforced before a field is read. Violations close the
engine socket or drop the shell payload.

| Item | Limit |
| --- | --- |
| Envelope (one packet) | ≤ 1 MiB |
| String field | ≤ 4096 bytes, valid UTF-8, no NUL |
| `surrounding_text` | ≤ 4000 bytes (text-input-v3 bound) |
| `candidates` per frame | ≤ 64 |
| `preedit` spans per frame | ≤ 64 |
| `config` entries | ≤ 64; key ≤ 128 bytes, value ≤ 1024 bytes |
| `commit`/`preedit` text | ≤ 4096 bytes |
| `delete_surrounding` counts | ≤ 4000 bytes each |
| `keycode` | ≤ `KEY_MAX` (767) |
| `key_id` | ≥ 1 within its activation |

Cross-field invariants are part of the contract: `highlighted` is `-1` or
strictly below `len(candidates)`; `page_index` is strictly below
`page_count` whenever `page_count > 0`; `page_count = 0` requires
`page_index = 0`, empty `candidates`, and `highlighted = -1`;
`cursor_begin ≤ cursor_end`, both `-1` or within their text's length on
code-point boundaries; `preedit_cursor` is `-1` or within the concatenated
preedit length on a code-point boundary; `surrounding_cursor` and
`surrounding_anchor` are within `surrounding_text`'s byte length on
code-point boundaries; `ImeSelectCandidate.index` is below the latest
frame's candidate count.

Denial validates magic, version, schema, **direction** (an engine sending a
deniald→engine payload type — `ImeActivate`, `ImeEditorUpdate`,
`ImeDeactivate`, `ImeDone`, `ImeKeyEvent`, `ImeSelectCandidate`,
`ImePageCandidates`, `ImeSetInputMode`, `ImeReloadConfiguration` — is a
protocol error), enum ranges, serials, counts, string bounds, UTF-8,
reserved bits, and the invariants above before use. The engine is
untrusted: a crash or disconnect retires the activation, clears the panel,
and publishes `Offline`; the session supervisor owns any restart policy
and its backoff.
