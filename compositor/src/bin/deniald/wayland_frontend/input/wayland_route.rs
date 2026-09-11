//! Client-owned Wayland input dispatch.

use super::flutter_route::{
    pointer_constraint_blocks_motion, pointer_constraint_reactivation_suppressed,
    process_wayland_keyboard_transition, route_pointer_axis,
};
use super::*;

pub(super) fn process_wayland_input_event(
    state: &mut RuntimeState,
    event: InputEvent<LibinputInputBackend>,
) {
    match event {
        InputEvent::Keyboard { event, .. } => process_wayland_keyboard_transition(
            state,
            event.key_code(),
            event.state(),
            event.time_msec(),
        ),
        InputEvent::PointerMotion { event, .. } => {
            let (position, under) = {
                let Some(frontend) = state.wayland.as_mut() else {
                    warn!("missing Wayland frontend; dropping pointer motion");
                    return;
                };
                let position = frontend.clamp_pointer(frontend.pointer_location + event.delta());
                (position, frontend.surface_under(position))
            };
            let Some(pointer) = state
                .wayland
                .as_ref()
                .and_then(|frontend| frontend.seat.get_pointer())
            else {
                warn!("missing Wayland frontend or seat pointer; dropping pointer motion");
                return;
            };
            let blocked = pointer_constraint_blocks_motion(
                &pointer,
                &under,
                position,
                pointer_constraint_reactivation_suppressed(state, &pointer),
            );
            pointer.relative_motion(
                state,
                if blocked {
                    pointer
                        .current_focus()
                        .map(|surface| (surface, Point::from((0.0, 0.0))))
                } else {
                    under.clone()
                },
                &RelativeMotionEvent {
                    delta: event.delta(),
                    delta_unaccel: event.delta_unaccel(),
                    utime: event.time_usec(),
                },
            );
            if blocked {
                pointer.frame(state);
                return;
            }
            let Some(frontend) = state.wayland.as_mut() else {
                warn!("missing Wayland frontend; dropping pointer motion");
                return;
            };
            frontend.pointer_location = position;
            pointer.motion(
                state,
                under,
                &MotionEvent {
                    location: position,
                    serial: SERIAL_COUNTER.next_serial(),
                    time: event.time_msec(),
                },
            );
            pointer.frame(state);
        }
        InputEvent::PointerMotionAbsolute { event, .. } => {
            let (position, under) = {
                let Some(frontend) = state.wayland.as_mut() else {
                    warn!("missing Wayland frontend; dropping pointer motion");
                    return;
                };
                let local = event.position_transformed(frontend.desktop_bounds.size);
                let position = frontend.clamp_pointer(local + frontend.desktop_bounds.loc.to_f64());
                (position, frontend.surface_under(position))
            };
            let Some(pointer) = state
                .wayland
                .as_ref()
                .and_then(|frontend| frontend.seat.get_pointer())
            else {
                warn!("missing Wayland frontend or seat pointer; dropping pointer motion");
                return;
            };
            if pointer_constraint_blocks_motion(
                &pointer,
                &under,
                position,
                pointer_constraint_reactivation_suppressed(state, &pointer),
            ) {
                pointer.frame(state);
                return;
            }
            let Some(frontend) = state.wayland.as_mut() else {
                warn!("missing Wayland frontend; dropping pointer motion");
                return;
            };
            frontend.pointer_location = position;
            pointer.motion(
                state,
                under,
                &MotionEvent {
                    location: position,
                    serial: SERIAL_COUNTER.next_serial(),
                    time: event.time_msec(),
                },
            );
            pointer.frame(state);
        }
        InputEvent::PointerButton { event, .. } => {
            let serial = SERIAL_COUNTER.next_serial();
            #[cfg(feature = "flutter")]
            if state.wayland.as_mut().is_some_and(|frontend| {
                retired_pointer_button_consumes_transition(
                    &mut frontend.retired_pointer_buttons,
                    event.button_code(),
                    event.state(),
                )
            }) {
                return;
            }
            let Some(pointer) = state
                .wayland
                .as_ref()
                .and_then(|frontend| frontend.seat.get_pointer())
            else {
                warn!("missing Wayland frontend or seat pointer; dropping pointer button event");
                return;
            };
            let Some(keyboard) = state
                .wayland
                .as_ref()
                .and_then(|frontend| frontend.seat.get_keyboard())
            else {
                warn!("missing Wayland frontend or seat keyboard; dropping pointer button event");
                return;
            };

            if event.state() == ButtonState::Pressed && !pointer.is_grabbed() {
                let window = state.wayland.as_ref().and_then(|frontend| {
                    frontend
                        .space
                        .element_under(pointer.current_location())
                        .map(|(window, _)| window.clone())
                });
                if let Some(window) = window {
                    #[cfg(feature = "flutter")]
                    {
                        let window_id = state.wayland.as_ref().and_then(|frontend| {
                            frontend
                                .window_root_surface(&window)
                                .and_then(|surface| frontend.surface_id(&surface))
                        });
                        if let Some(window_id) = window_id
                            && let Some(frontend) = state.wayland.as_mut()
                        {
                            frontend.pointer_constraint_escape.resume_window(window_id);
                        }
                    }
                    let Some(focus) = state
                        .wayland
                        .as_ref()
                        .map(|frontend| frontend.keyboard_focus_for_window(&window))
                    else {
                        warn!("missing Wayland frontend; dropping pointer button event");
                        return;
                    };
                    let Some(frontend) = state.wayland.as_mut() else {
                        warn!("missing Wayland frontend; dropping pointer button event");
                        return;
                    };
                    frontend.raise_window(&window, true);
                    for candidate in frontend.space.elements() {
                        let changed = candidate.set_activated(candidate == &window);
                        if changed && let Some(toplevel) = candidate.toplevel() {
                            toplevel.send_pending_configure();
                        }
                    }
                    keyboard.set_focus(state, focus, serial);
                } else {
                    keyboard.set_focus(
                        state,
                        Option::<super::super::KeyboardFocusTarget>::None,
                        serial,
                    );
                }
            }

            let Some(frontend) = state.wayland.as_mut() else {
                warn!("missing Wayland frontend; dropping pointer button event");
                return;
            };
            update_pressed_buttons(
                &mut frontend.wayland_pointer_buttons,
                event.button_code(),
                event.state(),
            );
            pointer.button(
                state,
                &ButtonEvent {
                    button: event.button_code(),
                    state: event.state(),
                    serial,
                    time: event.time_msec(),
                },
            );
            pointer.frame(state);
            state.scene_sync.mark_dirty();
        }
        InputEvent::PointerAxis { event, .. } => route_pointer_axis(state, &event),
        InputEvent::TouchDown { event, .. } => {
            let serial = SERIAL_COUNTER.next_serial();
            let (position, window) = {
                let Some(frontend) = state.wayland.as_ref() else {
                    warn!("missing Wayland frontend; dropping touch down event");
                    return;
                };
                let position = output_bound_absolute_position(
                    &event,
                    frontend.touch_bounds,
                    frontend.touch_transform,
                );
                let window = frontend
                    .space
                    .element_under(position)
                    .map(|(window, _)| window.clone());
                (position, window)
            };
            let Some((touch, keyboard)) = state.wayland.as_ref().and_then(|frontend| {
                Some((frontend.seat.get_touch()?, frontend.seat.get_keyboard()?))
            }) else {
                warn!("missing Wayland frontend or seat device; dropping touch down event");
                return;
            };

            if let Some(window) = window {
                let Some(focus) = state
                    .wayland
                    .as_ref()
                    .map(|frontend| frontend.keyboard_focus_for_window(&window))
                else {
                    warn!("missing Wayland frontend; dropping touch down event");
                    return;
                };
                let Some(frontend) = state.wayland.as_mut() else {
                    warn!("missing Wayland frontend; dropping touch down event");
                    return;
                };
                frontend.raise_window(&window, true);
                for candidate in frontend.space.elements() {
                    let changed = candidate.set_activated(candidate == &window);
                    if changed && let Some(toplevel) = candidate.toplevel() {
                        toplevel.send_pending_configure();
                    }
                }
                keyboard.set_focus(state, focus, serial);
            } else {
                keyboard.set_focus(
                    state,
                    Option::<super::super::KeyboardFocusTarget>::None,
                    serial,
                );
            }

            let under = state
                .wayland
                .as_ref()
                .and_then(|frontend| frontend.surface_under(position));
            touch.down(
                state,
                under,
                &DownEvent {
                    slot: event.slot(),
                    location: position,
                    serial,
                    time: event.time_msec(),
                },
            );
            state.scene_sync.mark_dirty();
        }
        InputEvent::TouchMotion { event, .. } => {
            let (position, under) = {
                let Some(frontend) = state.wayland.as_ref() else {
                    warn!("missing Wayland frontend; dropping touch motion event");
                    return;
                };
                let position = output_bound_absolute_position(
                    &event,
                    frontend.touch_bounds,
                    frontend.touch_transform,
                );
                (position, frontend.surface_under(position))
            };
            let Some(touch) = state
                .wayland
                .as_ref()
                .and_then(|frontend| frontend.seat.get_touch())
            else {
                warn!("missing Wayland frontend or seat touch; dropping touch motion");
                return;
            };
            touch.motion(
                state,
                under,
                &TouchMotionEvent {
                    slot: event.slot(),
                    location: position,
                    time: event.time_msec(),
                },
            );
        }
        InputEvent::TouchUp { event, .. } => {
            let Some(touch) = state
                .wayland
                .as_ref()
                .and_then(|frontend| frontend.seat.get_touch())
            else {
                warn!("missing Wayland frontend or seat touch; dropping touch up");
                return;
            };
            touch.up(
                state,
                &UpEvent {
                    slot: event.slot(),
                    serial: SERIAL_COUNTER.next_serial(),
                    time: event.time_msec(),
                },
            );
        }
        InputEvent::TouchFrame { .. } => {
            let Some(touch) = state
                .wayland
                .as_ref()
                .and_then(|frontend| frontend.seat.get_touch())
            else {
                warn!("missing Wayland frontend or seat touch; dropping touch frame");
                return;
            };
            touch.frame(state);
        }
        InputEvent::TouchCancel { .. } => {
            let Some(touch) = state
                .wayland
                .as_ref()
                .and_then(|frontend| frontend.seat.get_touch())
            else {
                warn!("missing Wayland frontend or seat touch; dropping touch cancel");
                return;
            };
            touch.cancel(state);
        }
        _ => {}
    }
}
