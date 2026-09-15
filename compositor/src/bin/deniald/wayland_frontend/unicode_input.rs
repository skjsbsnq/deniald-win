//! Unicode keysym synthesis for legacy editor endpoints.
//!
//! An input-method transaction that lands on a
//! [`SeatFallback`](super::input_method::EditorEndpoint::SeatFallback)
//! endpoint belongs to a client with no text-input object — an Xwayland
//! window, or a Wayland client that never enabled text-input-v3. The only
//! channel such a client understands is `wl_keyboard`, so this module types
//! the commit string as keystrokes:
//!
//! 1. Spare evdev keycodes ([`POOL_FIRST_EVDEV`]..=[`POOL_LAST_EVDEV`], the
//!    high media-key range a physical keyboard practically never reports)
//!    are assigned to the commit's distinct characters.
//! 2. The seat's current keymap text is augmented with
//!    `key <I###> { [ U<hex> ] };` statements inside its existing
//!    `xkb_symbols` section — XKB's `U<hex>` notation is the Unicode keysym
//!    `0x01000000 + codepoint`, which X11 clients translate through XKB into
//!    the intended character.
//! 3. The augmented keymap is sent *only to the focused client's*
//!    `wl_keyboard` resources (enumerated through
//!    `KeyboardHandle::client_keyboards`; Xwayland resolves through the
//!    associated `wl_surface` to the compositor-internal Xwayland client).
//!    Other clients never observe the temporary keymap.
//! 4. Press/release pairs are forwarded through
//!    `InputMethodKeyboardRoute::forward_virtual_key`, which calls
//!    `KeyboardHandle::input_forward`: the synthetic keys bypass the seat's
//!    XKB state machine and the input-method grab, so physical modifier
//!    state is never polluted by the synthesis.
//! 5. The client's original keymap is sent back, followed by a `modifiers`
//!    event — a keymap event resets the client's XKB state, and without
//!    this a physically held modifier would silently unlatch.
//!
//! `keymap` and `key` events travel on the same client connection, so they
//! are delivered in order and no sleep is needed between them. A commit with
//! more distinct characters than the pool holds is split into batches of at
//! most [`MAX_KEYS_PER_KEYMAP`], each batch running its own
//! augment/deliver/restore round — one keymap pair per batch, never one per
//! character.
//!
//! Restore is RAII-guarded: [`KeymapRestore`] resends the original keymap on
//! drop, so an unwind out of the forwarding loop still leaves the client
//! with its real keymap. The whole path is synchronous on the event loop, so
//! focus cannot change mid-batch; a client that dies mid-send fails its
//! `send` with an `io::Error` that is logged and skipped.

use std::collections::{HashMap, HashSet};
use std::fmt::Write as _;

use smithay::backend::input::{KeyState, Keycode};
use smithay::input::keyboard::{KeyboardHandle, KeymapFile, Keysym, xkb};
use smithay::reexports::wayland_server::Resource;
use smithay::reexports::wayland_server::protocol::wl_keyboard::WlKeyboard;
use smithay::wayland::seat::WaylandFocus;
use tracing::{debug, warn};

use super::RuntimeState;
use super::input_method::{InputMethodKeyboardRoute, InputMethodTransaction};

/// First evdev keycode in the synthesis pool: KEY_PLAYCD and friends, the
/// evdev 200..=239 range (XKB keycodes 208..=247, `<I208>`..`<I247>`).
const POOL_FIRST_EVDEV: u32 = 200;
/// Last evdev keycode in the synthesis pool.
const POOL_LAST_EVDEV: u32 = 239;
/// Distinct characters a single augmented keymap round may carry.
const MAX_KEYS_PER_KEYMAP: usize = 40;
/// Mirrors `MAX_INPUT_METHOD_TEXT_BYTES` in `input_method.rs`; enforced again
/// here so the legacy path keeps its own bound independently.
const MAX_COMMIT_TEXT_BYTES: usize = 4000;
const XKB_KEYCODE_OFFSET: u32 = 8;

/// One keymap round: which pool keycode produces which character, and the
/// order in which the codes are tapped.
#[derive(Debug, Default, PartialEq)]
struct SynthBatch {
    /// `(evdev keycode, character)` pairs, unique per character, in
    /// first-appearance order.
    mapping: Vec<(u32, char)>,
    /// Pool keycodes to press+release, in commit order (repeats allowed).
    sequence: Vec<u32>,
}

/// Deliver an input-method transaction to a legacy endpoint by typing it.
///
/// `preedit_string` has no keysym encoding (composition display stays on the
/// IM's own surface) and `delete_surrounding` cannot be expressed either —
/// legacy clients expose no surrounding-text protocol, so there is nothing
/// to delete from. Both are explicitly dropped with a debug log; only
/// `commit_string` reaches the client.
pub(super) fn deliver_legacy_commit(
    state: &mut RuntimeState,
    transaction: &InputMethodTransaction,
) {
    if let Some((before, after)) = transaction.delete_surrounding {
        debug!(
            before,
            after, "dropping delete-surrounding on legacy endpoint (no surrounding-text protocol)"
        );
    }
    if transaction.preedit_string.is_some() {
        debug!("dropping preedit on legacy endpoint (no keysym encoding)");
    }
    let Some(text) = transaction.commit_string.as_deref() else {
        return;
    };
    let text = truncate_commit(text);
    if text.is_empty() {
        return;
    }

    let Some(frontend) = state.wayland.as_ref() else {
        return;
    };
    let Some(keyboard) = frontend.seat.get_keyboard() else {
        warn!("seat has no keyboard; dropping legacy input-method commit");
        return;
    };
    let route = frontend.input_method.keyboard_route();
    // All synthetic events of one commit share a single timestamp: the
    // synthesis is synchronous, and wl_keyboard key times carry no ordering
    // contract clients depend on here.
    let time = frontend.start_time.elapsed().as_millis() as u32;

    // The focused client's wl_keyboard objects are exactly the resources the
    // synthetic key events will reach, so they are the only ones that receive
    // the augmented keymap (plan A; no seat-wide keymap swap and therefore no
    // window in which other clients could observe it).
    let Some(client) = keyboard
        .current_focus()
        .and_then(|focus| focus.wl_surface().map(|surface| surface.into_owned()))
        .and_then(|surface| surface.client())
    else {
        // An X11 focus whose wl_surface is not yet associated has no client
        // to target. Forwarding anyway would be worse than dropping: the key
        // codes would queue into X11Surface's pending_enter and, replayed
        // under the *original* keymap, produce real media keysyms.
        debug!("legacy commit with no focused client; dropping text");
        return;
    };
    let targets: Vec<WlKeyboard> = keyboard
        .client_keyboards(&client)
        .filter(Resource::is_alive)
        .collect();
    if targets.is_empty() {
        debug!("focused client holds no wl_keyboard; dropping legacy commit");
        return;
    }

    let (base_text, original) = keyboard.with_xkb_state(state, |context| {
        let xkb = context
            .xkb()
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        // SAFETY: the keymap is borrowed only while the XKB mutex is held.
        let keymap = unsafe { xkb.keymap() };
        (
            keymap.get_as_string(xkb::KEYMAP_FORMAT_TEXT_V1),
            KeymapFile::new(keymap),
        )
    });

    // Keycodes physically held right now must never be re-issued as a
    // synthetic tap: our release would also end the real keypress. (Virtual
    // keys forwarded earlier through `input_forward` are not covered by
    // `pressed_keys`; a pool-code collision with one would release it early —
    // accepted, since the IM pool range almost never overlaps forwarded
    // keys.)
    let occupied: HashSet<u32> = keyboard
        .pressed_keys()
        .into_iter()
        .map(|code| code.raw().saturating_sub(XKB_KEYCODE_OFFSET))
        .collect();

    let batches = plan_batches(text, &occupied);
    let deliverable: usize = batches.iter().map(|batch| batch.sequence.len()).sum();
    let wanted = text.chars().count();
    if deliverable < wanted {
        warn!(
            dropped = wanted - deliverable,
            "legacy commit partially undeliverable; keycode pool exhausted"
        );
    }

    let context = xkb::Context::new(xkb::CONTEXT_NO_FLAGS);
    for batch in &batches {
        deliver_batch(
            state, &keyboard, &route, &targets, &base_text, &original, &context, batch, time,
        );
    }
}

/// Split `text` into keymap rounds: each batch maps at most
/// [`MAX_KEYS_PER_KEYMAP`] distinct characters onto pool keycodes that are
/// not in `occupied`, preserving commit order in `sequence`.
fn plan_batches(text: &str, occupied: &HashSet<u32>) -> Vec<SynthBatch> {
    let mut batches = Vec::new();
    let mut batch = SynthBatch::default();
    let mut assigned: HashMap<char, u32> = HashMap::new();
    let mut cursor = POOL_FIRST_EVDEV;
    for ch in text.chars() {
        if let Some(&code) = assigned.get(&ch) {
            batch.sequence.push(code);
            continue;
        }
        let mut code = if batch.mapping.len() < MAX_KEYS_PER_KEYMAP {
            next_free_code(&mut cursor, occupied)
        } else {
            None
        };
        if code.is_none() {
            if batch.mapping.is_empty() {
                // Every pool keycode is occupied; nothing can be synthesized.
                break;
            }
            batches.push(std::mem::take(&mut batch));
            assigned.clear();
            cursor = POOL_FIRST_EVDEV;
            code = next_free_code(&mut cursor, occupied);
            if code.is_none() {
                break;
            }
        }
        let code = code.unwrap();
        batch.mapping.push((code, ch));
        assigned.insert(ch, code);
        batch.sequence.push(code);
    }
    if !batch.mapping.is_empty() {
        batches.push(batch);
    }
    batches
}

fn next_free_code(cursor: &mut u32, occupied: &HashSet<u32>) -> Option<u32> {
    while *cursor <= POOL_LAST_EVDEV {
        let code = *cursor;
        *cursor += 1;
        if !occupied.contains(&code) {
            return Some(code);
        }
    }
    None
}

/// Truncate an oversized commit at a char boundary.
fn truncate_commit(text: &str) -> &str {
    if text.len() <= MAX_COMMIT_TEXT_BYTES {
        return text;
    }
    let mut end = MAX_COMMIT_TEXT_BYTES;
    while !text.is_char_boundary(end) {
        end -= 1;
    }
    warn!(
        dropped = text.len() - end,
        "truncating oversized legacy commit"
    );
    &text[..end]
}

/// Splice `key <I###> { [ U<hex> ] };` statements into the existing
/// `xkb_symbols` section of a serialized keymap.
///
/// A compiled keymap dump contains exactly one `xkb_symbols` block, and
/// xkbcommon ignores additional top-level sections of the same type, so the
/// statements must go *inside* it. A repeated `key` statement overrides the
/// earlier definition silently, which is what lets pool keycodes shed their
/// default XF86 media-key symbols. Returns `None` when the base text has no
/// usable `xkb_symbols` block.
fn augment_keymap_text(base: &str, mapping: &[(u32, char)]) -> Option<String> {
    if mapping.is_empty() {
        return None;
    }
    let section = base.find("xkb_symbols")?;
    let open = base[section..].find('{').map(|offset| section + offset)?;
    let mut depth = 0usize;
    let mut close = None;
    for (offset, byte) in base.bytes().enumerate().skip(open) {
        match byte {
            b'{' => depth += 1,
            b'}' => {
                depth -= 1;
                if depth == 0 {
                    close = Some(offset);
                    break;
                }
            }
            _ => {}
        }
    }
    let close = close?;
    let mut injected = String::new();
    for (evdev, ch) in mapping {
        let _ = writeln!(
            injected,
            "\tkey <I{}> {{ [ U{:04X} ] }};",
            evdev + XKB_KEYCODE_OFFSET,
            *ch as u32
        );
    }
    let mut out = String::with_capacity(base.len() + injected.len());
    out.push_str(&base[..close]);
    out.push_str(&injected);
    out.push_str(&base[close..]);
    Some(out)
}

/// Pool keycodes whose Unicode keysym actually survived keymap compilation.
///
/// `<I###>` names outside the base keymap's keycode range are dropped by
/// xkbcommon without failing the build, so assignments are verified against
/// the compiled result rather than assumed.
///
/// The expected keysym is checked in both forms: `U<hex>` in keymap text is
/// stored verbatim as `0x01000000 + codepoint`, while `utf32_to_keysym`
/// returns the smaller *legacy* keysym for codepoints that have one
/// (Cyrillic, Greek, kana, `、。「」`, `€`, …). Either form in the compiled
/// output means the assignment took.
fn live_codes(keymap: &xkb::Keymap, mapping: &[(u32, char)]) -> HashSet<u32> {
    mapping
        .iter()
        .filter(|(evdev, ch)| {
            let codepoint = *ch as u32;
            let unicode_form = Keysym::from(0x0100_0000 + codepoint);
            let legacy_form = xkb::utf32_to_keysym(codepoint);
            let syms =
                keymap.key_get_syms_by_level(Keycode::new(evdev + XKB_KEYCODE_OFFSET), 0, 0);
            syms.contains(&unicode_form) || (legacy_form != Keysym::from(0) && syms.contains(&legacy_form))
        })
        .map(|(evdev, _)| *evdev)
        .collect()
}

fn deliver_batch(
    state: &mut RuntimeState,
    keyboard: &KeyboardHandle<RuntimeState>,
    route: &InputMethodKeyboardRoute,
    targets: &[WlKeyboard],
    base_text: &str,
    original: &KeymapFile,
    context: &xkb::Context,
    batch: &SynthBatch,
    time: u32,
) {
    let Some(augmented) = augment_keymap_text(base_text, &batch.mapping) else {
        warn!("seat keymap has no xkb_symbols section; skipping synthesis batch");
        return;
    };
    let Some(enhanced) = xkb::Keymap::new_from_string(
        context,
        augmented,
        xkb::KEYMAP_FORMAT_TEXT_V1,
        xkb::KEYMAP_COMPILE_NO_FLAGS,
    ) else {
        warn!("augmented unicode keymap failed to compile; skipping batch");
        return;
    };
    let live = live_codes(&enhanced, &batch.mapping);
    if live.len() < batch.mapping.len() {
        warn!(
            dropped = batch.mapping.len() - live.len(),
            "unicode key assignments did not survive keymap compilation"
        );
    }
    if live.is_empty() {
        return;
    }
    let enhanced_file = KeymapFile::new(&enhanced);
    // Installing the guard before the augmented keymap goes out guarantees
    // the original is resent even if forwarding unwinds.
    let _restore = KeymapRestore {
        original,
        modifiers: keyboard.modifier_state().serialized,
        targets,
    };
    let mut send_failed = false;
    for target in targets.iter().filter(|target| target.is_alive()) {
        if let Err(error) = enhanced_file.send(target) {
            warn!(%error, "could not send augmented keymap to focused client");
            send_failed = true;
        }
    }
    if send_failed {
        // Key events cannot be narrowed to a single wl_keyboard: a failed
        // target would receive pool keycodes under its *original* keymap and
        // translate them into real media keysyms. Drop the whole batch
        // instead; the guard still restores the keymap on every target that
        // did receive it.
        warn!("skipping synthesized keys; a focused wl_keyboard missed the augmented keymap");
        return;
    }
    for evdev in batch.sequence.iter().filter(|code| live.contains(code)) {
        route.forward_virtual_key(keyboard, state, *evdev, KeyState::Pressed, time);
        route.forward_virtual_key(keyboard, state, *evdev, KeyState::Released, time);
    }
}

/// Sends the original keymap back to the target `wl_keyboard` resources on
/// drop, plus a `modifiers` event: a keymap event resets the client's XKB
/// state, and without re-arming it a physically held modifier would be lost.
struct KeymapRestore<'a> {
    original: &'a KeymapFile,
    modifiers: smithay::input::keyboard::SerializedMods,
    targets: &'a [WlKeyboard],
}

impl Drop for KeymapRestore<'_> {
    fn drop(&mut self) {
        let serial = smithay::utils::SERIAL_COUNTER.next_serial();
        let modifiers = self.modifiers;
        for target in self.targets.iter().filter(|target| target.is_alive()) {
            if let Err(error) = self.original.send(target) {
                warn!(%error, "could not restore client keymap after unicode synthesis");
            }
            target.modifiers(
                serial.into(),
                modifiers.depressed,
                modifiers.latched,
                modifiers.locked,
                modifiers.layout_effective,
            );
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A minimal self-contained keymap that declares a few pool keycodes;
    /// `<I240>` is deliberately absent to model a keycode outside the
    /// keycodes section.
    const TEST_KEYMAP: &str = "xkb_keymap {\n\
        xkb_keycodes \"test\" {\n\
        \tminimum = 8;\n\
        \tmaximum = 255;\n\
        \t<I208> = 208;\n\
        \t<I209> = 209;\n\
        \t<I210> = 210;\n\
        \t<I211> = 211;\n\
        };\n\
        xkb_types \"test\" {\n\
        \ttype \"ONE_LEVEL\" {\n\
        \t\tmap[None] = Level1;\n\
        \t\tlevel_name[Level1] = \"Any\";\n\
        \t};\n\
        };\n\
        xkb_compat \"test\" {\n\
        };\n\
        xkb_symbols \"test\" {\n\
        \tkey <I208> { [ XF86AudioPlay ] };\n\
        };\n\
        };\n";

    #[test]
    fn batches_dedupe_chars_and_preserve_order() {
        let batches = plan_batches("中國中国", &HashSet::new());
        assert_eq!(batches.len(), 1);
        assert_eq!(
            batches[0].mapping,
            vec![(200, '中'), (201, '國'), (202, '国')]
        );
        assert_eq!(batches[0].sequence, vec![200, 201, 200, 202]);
    }

    #[test]
    fn occupied_pool_codes_are_never_assigned() {
        let occupied = HashSet::from([200, 202]);
        let batches = plan_batches("ab", &occupied);
        assert_eq!(batches[0].mapping, vec![(201, 'a'), (203, 'b')]);
    }

    #[test]
    fn more_distinct_chars_than_free_codes_split_into_batches() {
        // Only four pool keycodes are free.
        let occupied: HashSet<u32> = (200..=235).collect();
        let batches = plan_batches("abcdef", &occupied);
        assert_eq!(batches.len(), 2);
        assert_eq!(batches[0].mapping.len(), 4);
        assert_eq!(batches[1].mapping.len(), 2);
        // Pool keycodes are reused across batches since each batch ships its
        // own keymap.
        assert_eq!(batches[0].mapping[0].0, 236);
        assert_eq!(batches[1].mapping[0].0, 236);
        assert_eq!(batches[0].sequence, vec![236, 237, 238, 239]);
        assert_eq!(batches[1].sequence, vec![236, 237]);
    }

    #[test]
    fn repeated_chars_across_batches_remap() {
        let occupied: HashSet<u32> = (201..=239).collect();
        // Only evdev 200 is free: each batch maps a single distinct char, so
        // "aba" needs three keymap rounds.
        let batches = plan_batches("aba", &occupied);
        assert_eq!(batches.len(), 3);
        assert_eq!(batches[0].mapping, vec![(200, 'a')]);
        assert_eq!(batches[0].sequence, vec![200]);
        assert_eq!(batches[1].mapping, vec![(200, 'b')]);
        assert_eq!(batches[1].sequence, vec![200]);
        assert_eq!(batches[2].mapping, vec![(200, 'a')]);
        assert_eq!(batches[2].sequence, vec![200]);
    }

    #[test]
    fn fully_occupied_pool_yields_no_batches() {
        let occupied: HashSet<u32> = (200..=239).collect();
        assert!(plan_batches("abc", &occupied).is_empty());
    }

    #[test]
    fn augment_inserts_key_lines_inside_xkb_symbols() {
        let base = "xkb_keymap {\n\
            xkb_keycodes \"t\" {\n\
            };\n\
            xkb_symbols \"t\" {\n\
            \tkey <I208> { [ XF86AudioPlay ] };\n\
            };\n\
            };\n";
        let out = augment_keymap_text(base, &[(200, '中'), (201, '😀')]).unwrap();
        assert!(out.contains("key <I208> { [ U4E2D ] };"));
        assert!(out.contains("key <I209> { [ U1F600 ] };"));
        // Our statement lands after the stock one inside the same section,
        // so it wins the override.
        let stock = out.find("XF86AudioPlay").unwrap();
        let ours = out.find("U4E2D").unwrap();
        assert!(stock < ours);
        // And it lands before the xkb_symbols closing brace, not inside
        // some other section or after the keymap.
        let xkb_keymap_close = out.rfind("};").unwrap();
        assert!(ours < xkb_keymap_close);
    }

    #[test]
    fn augment_rejects_keymap_without_symbols_section() {
        assert!(augment_keymap_text("xkb_keymap {\n};\n", &[(200, 'a')]).is_none());
        assert!(augment_keymap_text("", &[(200, 'a')]).is_none());
    }

    #[test]
    fn augmented_keymap_compiles_and_assigns_unicode_keysyms() {
        let context = xkb::Context::new(xkb::CONTEXT_NO_FLAGS);
        let augmented =
            augment_keymap_text(TEST_KEYMAP, &[(200, '中'), (201, '😀'), (202, 'a')]).unwrap();
        let keymap = xkb::Keymap::new_from_string(
            &context,
            augmented,
            xkb::KEYMAP_FORMAT_TEXT_V1,
            xkb::KEYMAP_COMPILE_NO_FLAGS,
        )
        .expect("augmented keymap must compile");
        assert_eq!(
            keymap.key_get_syms_by_level(Keycode::new(208), 0, 0),
            &[xkb::utf32_to_keysym('中' as u32)]
        );
        assert_eq!(
            keymap.key_get_syms_by_level(Keycode::new(209), 0, 0),
            &[xkb::utf32_to_keysym('😀' as u32)]
        );
    }

    #[test]
    fn live_codes_accept_chars_with_legacy_keysyms() {
        // '。' U+3002 has the legacy keysym 0x04a1, 'а' U+0430 -> 0x06c1,
        // '「' U+300C -> 0x04a2, 'a' U+0061 -> 0x61. `U<hex>` keymap text is
        // stored verbatim as 0x01000000+cp while utf32_to_keysym prefers the
        // legacy form, so both expected values must be accepted.
        let context = xkb::Context::new(xkb::CONTEXT_NO_FLAGS);
        let mapping = [(200, '。'), (201, 'а'), (202, '「'), (203, 'a')];
        let augmented = augment_keymap_text(TEST_KEYMAP, &mapping).unwrap();
        let keymap = xkb::Keymap::new_from_string(
            &context,
            augmented,
            xkb::KEYMAP_FORMAT_TEXT_V1,
            xkb::KEYMAP_COMPILE_NO_FLAGS,
        )
        .expect("augmented keymap must compile");
        // The stored keysym really is the verbatim Unicode form.
        assert_eq!(
            keymap.key_get_syms_by_level(Keycode::new(208), 0, 0),
            &[Keysym::from(0x0100_0000 + '。' as u32)]
        );
        let live = live_codes(&keymap, &mapping);
        for (code, _) in mapping {
            assert!(live.contains(&code), "code {code} wrongly dropped");
        }
    }

    #[test]
    fn live_codes_drop_assignments_outside_the_keycode_range() {
        let context = xkb::Context::new(xkb::CONTEXT_NO_FLAGS);
        // evdev 232 -> <I240> is not declared by TEST_KEYMAP's keycodes
        // section, so its assignment is dropped by the compiler.
        let augmented =
            augment_keymap_text(TEST_KEYMAP, &[(200, '中'), (232, '国')]).unwrap();
        let keymap = xkb::Keymap::new_from_string(
            &context,
            augmented,
            xkb::KEYMAP_FORMAT_TEXT_V1,
            xkb::KEYMAP_COMPILE_NO_FLAGS,
        )
        .expect("augmented keymap must compile");
        let live = live_codes(&keymap, &[(200, '中'), (232, '国')]);
        assert!(live.contains(&200));
        assert!(!live.contains(&232));
    }

    #[test]
    fn truncate_commit_stops_at_char_boundary() {
        let text = format!("{}x", "中".repeat(2000));
        // 2000 * 3B + 1B > 4000; truncation must not split the last 中.
        let truncated = truncate_commit(&text);
        assert!(truncated.len() <= MAX_COMMIT_TEXT_BYTES);
        assert!(truncated.is_char_boundary(truncated.len()));
        assert!(truncated.ends_with('中'));
    }
}
