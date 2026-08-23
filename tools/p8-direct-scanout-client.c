#define _POSIX_C_SOURCE 200809L

#include <EGL/egl.h>
#include <GLES2/gl2.h>
#include <errno.h>
#include <poll.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <wayland-client.h>
#include <wayland-egl.h>

#include "xdg-shell-client-protocol.h"
#include "viewporter-client-protocol.h"

struct client {
    struct wl_display *display;
    struct wl_registry *registry;
    struct wl_compositor *compositor;
    struct wl_surface *surface;
    struct wl_seat *seat;
    struct wl_pointer *pointer;
    struct xdg_wm_base *wm_base;
    struct xdg_surface *xdg_surface;
    struct xdg_toplevel *toplevel;
    struct wp_viewporter *viewporter;
    struct wp_viewport *viewport;
    struct wl_egl_window *egl_window;
    EGLDisplay egl_display;
    EGLContext egl_context;
    EGLSurface egl_surface;
    uint32_t width;
    uint32_t height;
    uint64_t frame;
    bool configured;
    bool running;
    int32_t configured_width;
    int32_t configured_height;
};

static void fail(const char *message) {
    fprintf(stderr, "p8-direct-scanout-client: %s\n", message);
    exit(EXIT_FAILURE);
}

static void wm_base_ping(void *data, struct xdg_wm_base *wm_base, uint32_t serial) {
    (void)data;
    xdg_wm_base_pong(wm_base, serial);
}

static const struct xdg_wm_base_listener wm_base_listener = {
    .ping = wm_base_ping,
};

static void pointer_enter(void *data, struct wl_pointer *pointer, uint32_t serial,
                          struct wl_surface *surface, wl_fixed_t x, wl_fixed_t y) {
    (void)data;
    (void)surface;
    (void)x;
    (void)y;
    wl_pointer_set_cursor(pointer, serial, NULL, 0, 0);
}

static void pointer_leave(void *data, struct wl_pointer *pointer, uint32_t serial,
                          struct wl_surface *surface) {
    (void)data;
    (void)pointer;
    (void)serial;
    (void)surface;
}

static void pointer_motion(void *data, struct wl_pointer *pointer, uint32_t time,
                           wl_fixed_t x, wl_fixed_t y) {
    (void)data;
    (void)pointer;
    (void)time;
    (void)x;
    (void)y;
}

static void pointer_button(void *data, struct wl_pointer *pointer, uint32_t serial,
                           uint32_t time, uint32_t button, uint32_t state) {
    (void)data;
    (void)pointer;
    (void)serial;
    (void)time;
    (void)button;
    (void)state;
}

static void pointer_axis(void *data, struct wl_pointer *pointer, uint32_t time,
                         uint32_t axis, wl_fixed_t value) {
    (void)data;
    (void)pointer;
    (void)time;
    (void)axis;
    (void)value;
}

static void pointer_frame(void *data, struct wl_pointer *pointer) {
    (void)data;
    (void)pointer;
}

static void pointer_axis_source(void *data, struct wl_pointer *pointer, uint32_t source) {
    (void)data;
    (void)pointer;
    (void)source;
}

static void pointer_axis_stop(void *data, struct wl_pointer *pointer, uint32_t time,
                              uint32_t axis) {
    (void)data;
    (void)pointer;
    (void)time;
    (void)axis;
}

static void pointer_axis_discrete(void *data, struct wl_pointer *pointer, uint32_t axis,
                                  int32_t discrete) {
    (void)data;
    (void)pointer;
    (void)axis;
    (void)discrete;
}

static const struct wl_pointer_listener pointer_listener = {
    .enter = pointer_enter,
    .leave = pointer_leave,
    .motion = pointer_motion,
    .button = pointer_button,
    .axis = pointer_axis,
    .frame = pointer_frame,
    .axis_source = pointer_axis_source,
    .axis_stop = pointer_axis_stop,
    .axis_discrete = pointer_axis_discrete,
};

static void seat_capabilities(void *data, struct wl_seat *seat, uint32_t capabilities) {
    struct client *client = data;
    if ((capabilities & WL_SEAT_CAPABILITY_POINTER) != 0 && client->pointer == NULL) {
        client->pointer = wl_seat_get_pointer(seat);
        wl_pointer_add_listener(client->pointer, &pointer_listener, client);
    } else if ((capabilities & WL_SEAT_CAPABILITY_POINTER) == 0 && client->pointer != NULL) {
        wl_pointer_destroy(client->pointer);
        client->pointer = NULL;
    }
}

static void seat_name(void *data, struct wl_seat *seat, const char *name) {
    (void)data;
    (void)seat;
    (void)name;
}

static const struct wl_seat_listener seat_listener = {
    .capabilities = seat_capabilities,
    .name = seat_name,
};

static void registry_global(void *data, struct wl_registry *registry, uint32_t name,
                            const char *interface, uint32_t version) {
    struct client *client = data;
    if (strcmp(interface, wl_compositor_interface.name) == 0) {
        client->compositor = wl_registry_bind(registry, name, &wl_compositor_interface,
                                              version < 4 ? version : 4);
    } else if (strcmp(interface, xdg_wm_base_interface.name) == 0) {
        client->wm_base = wl_registry_bind(registry, name, &xdg_wm_base_interface, 1);
        xdg_wm_base_add_listener(client->wm_base, &wm_base_listener, client);
    } else if (strcmp(interface, wl_seat_interface.name) == 0) {
        client->seat = wl_registry_bind(registry, name, &wl_seat_interface,
                                        version < 7 ? version : 7);
        wl_seat_add_listener(client->seat, &seat_listener, client);
    } else if (strcmp(interface, wp_viewporter_interface.name) == 0) {
        client->viewporter = wl_registry_bind(registry, name, &wp_viewporter_interface, 1);
    }
}

static void registry_remove(void *data, struct wl_registry *registry, uint32_t name) {
    (void)data;
    (void)registry;
    (void)name;
}

static const struct wl_registry_listener registry_listener = {
    .global = registry_global,
    .global_remove = registry_remove,
};

static void xdg_surface_configure(void *data, struct xdg_surface *surface, uint32_t serial) {
    struct client *client = data;
    xdg_surface_ack_configure(surface, serial);
    client->configured = true;
}

static const struct xdg_surface_listener xdg_surface_listener = {
    .configure = xdg_surface_configure,
};

static void toplevel_configure(void *data, struct xdg_toplevel *toplevel, int32_t width,
                               int32_t height, struct wl_array *states) {
    (void)toplevel;
    (void)states;
    struct client *client = data;
    if (width > 0 && height > 0) {
        client->configured_width = width;
        client->configured_height = height;
    }
    /* Deliberately retain the exact physical test-buffer size. */
}

static void toplevel_close(void *data, struct xdg_toplevel *toplevel) {
    struct client *client = data;
    (void)toplevel;
    client->running = false;
}

static void toplevel_configure_bounds(void *data, struct xdg_toplevel *toplevel,
                                      int32_t width, int32_t height) {
    (void)data;
    (void)toplevel;
    (void)width;
    (void)height;
}

static void toplevel_wm_capabilities(void *data, struct xdg_toplevel *toplevel,
                                     struct wl_array *capabilities) {
    (void)data;
    (void)toplevel;
    (void)capabilities;
}

static const struct xdg_toplevel_listener toplevel_listener = {
    .configure = toplevel_configure,
    .close = toplevel_close,
    .configure_bounds = toplevel_configure_bounds,
    .wm_capabilities = toplevel_wm_capabilities,
};

static EGLConfig choose_config(EGLDisplay display) {
    static const EGLint attributes[] = {
        EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
        EGL_RED_SIZE, 8,
        EGL_GREEN_SIZE, 8,
        EGL_BLUE_SIZE, 8,
        EGL_ALPHA_SIZE, 0,
        EGL_NONE,
    };
    EGLConfig config = NULL;
    EGLint count = 0;
    if (!eglChooseConfig(display, attributes, &config, 1, &count) || count != 1) {
        fail("could not choose an opaque EGL window config");
    }
    return config;
}

static void initialize_egl(struct client *client) {
    client->egl_display = eglGetDisplay((EGLNativeDisplayType)client->display);
    if (client->egl_display == EGL_NO_DISPLAY ||
        !eglInitialize(client->egl_display, NULL, NULL)) {
        fail("could not initialize Wayland EGL");
    }
    if (!eglBindAPI(EGL_OPENGL_ES_API)) {
        fail("could not bind OpenGL ES");
    }
    EGLConfig config = choose_config(client->egl_display);
    static const EGLint context_attributes[] = {EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE};
    client->egl_context = eglCreateContext(client->egl_display, config, EGL_NO_CONTEXT,
                                           context_attributes);
    if (client->egl_context == EGL_NO_CONTEXT) {
        fail("could not create GLES2 context");
    }
    client->egl_window = wl_egl_window_create(client->surface, (int)client->width,
                                              (int)client->height);
    if (client->egl_window == NULL) {
        fail("could not create exact-size wl_egl_window");
    }
    client->egl_surface = eglCreateWindowSurface(client->egl_display, config,
                                                 (EGLNativeWindowType)client->egl_window, NULL);
    if (client->egl_surface == EGL_NO_SURFACE ||
        !eglMakeCurrent(client->egl_display, client->egl_surface, client->egl_surface,
                        client->egl_context)) {
        fail("could not activate exact-size EGL surface");
    }
    eglSwapInterval(client->egl_display, 1);
}

static void draw_frame(struct client *client) {
    const float phase = (float)(client->frame % 240) / 239.0f;
    const float red = phase;
    const float green = 1.0f - phase;
    const float blue = ((client->frame / 30) & 1U) != 0 ? 0.85f : 0.15f;
    glViewport(0, 0, (GLsizei)client->width, (GLsizei)client->height);
    glDisable(GL_BLEND);
    glClearColor(red, green, blue, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);

    glEnable(GL_SCISSOR_TEST);
    for (uint32_t bit = 0; bit < 16; ++bit) {
        const bool set = ((client->frame >> bit) & 1U) != 0;
        glScissor(24 + (GLint)bit * 36, 24, 28, 96);
        glClearColor(set ? 1.0f : 0.02f, set ? 1.0f : 0.02f, set ? 1.0f : 0.02f, 1.0f);
        glClear(GL_COLOR_BUFFER_BIT);
    }
    glDisable(GL_SCISSOR_TEST);
    if (!eglSwapBuffers(client->egl_display, client->egl_surface)) {
        fail("eglSwapBuffers failed");
    }
    ++client->frame;
}

static bool dispatch_events(struct client *client) {
    if (wl_display_dispatch_pending(client->display) < 0) {
        return false;
    }
    if (wl_display_flush(client->display) < 0 && errno != EAGAIN) {
        return false;
    }

    struct pollfd display_fd = {
        .fd = wl_display_get_fd(client->display),
        .events = POLLIN,
    };
    const int ready = poll(&display_fd, 1, 0);
    if (ready < 0) {
        return errno == EINTR;
    }
    if ((display_fd.revents & (POLLERR | POLLHUP | POLLNVAL)) != 0) {
        return false;
    }
    if ((display_fd.revents & POLLIN) != 0 &&
        wl_display_dispatch(client->display) < 0) {
        return false;
    }
    return true;
}

static uint32_t parse_dimension(const char *value, const char *name) {
    char *end = NULL;
    errno = 0;
    unsigned long parsed = strtoul(value, &end, 10);
    if (errno != 0 || end == value || *end != '\0' || parsed == 0 || parsed > 16384) {
        fprintf(stderr, "p8-direct-scanout-client: invalid %s: %s\n", name, value);
        exit(EXIT_FAILURE);
    }
    return (uint32_t)parsed;
}

int main(int argc, char **argv) {
    struct client client = {
        .egl_display = EGL_NO_DISPLAY,
        .egl_context = EGL_NO_CONTEXT,
        .egl_surface = EGL_NO_SURFACE,
        .width = 2560,
        .height = 1600,
        .running = true,
    };
    if (argc == 3) {
        client.width = parse_dimension(argv[1], "width");
        client.height = parse_dimension(argv[2], "height");
    } else if (argc != 1) {
        fail("usage: p8-direct-scanout-client [WIDTH HEIGHT]");
    }

    client.display = wl_display_connect(NULL);
    if (client.display == NULL) {
        fail("could not connect to WAYLAND_DISPLAY");
    }
    client.registry = wl_display_get_registry(client.display);
    wl_registry_add_listener(client.registry, &registry_listener, &client);
    wl_display_roundtrip(client.display);
    if (client.compositor == NULL || client.wm_base == NULL) {
        fail("compositor does not expose wl_compositor and xdg_wm_base");
    }
    if (client.viewporter == NULL) {
        fail("compositor does not expose wp_viewporter");
    }

    client.surface = wl_compositor_create_surface(client.compositor);
    struct wl_region *opaque = wl_compositor_create_region(client.compositor);
    wl_region_add(opaque, 0, 0, (int32_t)client.width, (int32_t)client.height);
    wl_surface_set_opaque_region(client.surface, opaque);
    wl_region_destroy(opaque);

    client.xdg_surface = xdg_wm_base_get_xdg_surface(client.wm_base, client.surface);
    xdg_surface_add_listener(client.xdg_surface, &xdg_surface_listener, &client);
    client.toplevel = xdg_surface_get_toplevel(client.xdg_surface);
    xdg_toplevel_add_listener(client.toplevel, &toplevel_listener, &client);
    xdg_toplevel_set_title(client.toplevel, "P8 Direct Scanout Test");
    xdg_toplevel_set_app_id(client.toplevel, "dev.denial.p8-direct-scanout-test");
    xdg_toplevel_set_fullscreen(client.toplevel, NULL);
    wl_surface_commit(client.surface);

    while (!client.configured && wl_display_dispatch(client.display) >= 0) {
    }
    if (!client.configured) {
        fail("fullscreen surface was not configured");
    }
    client.viewport = wp_viewporter_get_viewport(client.viewporter, client.surface);
    wp_viewport_set_source(client.viewport, 0, 0, (int32_t)client.width << 8,
                           (int32_t)client.height << 8);
    if (client.configured_width > 0 && client.configured_height > 0) {
        wp_viewport_set_destination(client.viewport, client.configured_width,
                                    client.configured_height);
    }
    wl_surface_commit(client.surface);
    initialize_egl(&client);
    fprintf(stderr, "p8-direct-scanout-client: fullscreen buffer %ux%u; move pointer into the window once to hide cursor\n",
            client.width, client.height);

    while (client.running) {
        if (!dispatch_events(&client)) {
            break;
        }
        draw_frame(&client);
        struct timespec delay = {.tv_sec = 0, .tv_nsec = 16 * 1000 * 1000};
        nanosleep(&delay, NULL);
    }
    return EXIT_SUCCESS;
}
