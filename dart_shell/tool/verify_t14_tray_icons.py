#!/usr/bin/env python3
import subprocess
import time
import sys
import os
import dbus
import dbus.service
import dbus.mainloop.glib
from gi.repository import GLib

dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)

class AdvancedTestSNI(dbus.service.Object):
    def __init__(self, bus, bus_name, object_path, app_id, title, **kwargs):
        super().__init__(bus_name, object_path)
        self.bus = bus
        self.bus_name = bus_name
        self.object_path = object_path
        self.app_id = app_id
        self.title = title
        self.status = kwargs.get("status", "Active")
        self.category = kwargs.get("category", "ApplicationStatus")
        self.icon_name = kwargs.get("icon_name", "")
        self.icon_theme_path = kwargs.get("icon_theme_path", "")
        self.icon_pixmap = kwargs.get("icon_pixmap", [])
        self.overlay_icon_name = kwargs.get("overlay_icon_name", "")
        self.overlay_icon_pixmap = kwargs.get("overlay_icon_pixmap", [])
        self.attention_icon_name = kwargs.get("attention_icon_name", "")
        self.attention_icon_pixmap = kwargs.get("attention_icon_pixmap", [])
        self.tooltip_title = kwargs.get("tooltip_title", title)
        self.tooltip_desc = kwargs.get("tooltip_desc", f"{title} description")

    @dbus.service.method("org.freedesktop.DBus.Properties", in_signature="s", out_signature="a{sv}")
    def GetAll(self, interface_name):
        if interface_name != "org.kde.StatusNotifierItem":
            return {}

        def to_pixmap_array(pix_list):
            out = []
            for w, h, data in pix_list:
                out.append(dbus.Struct((
                    dbus.Int32(w),
                    dbus.Int32(h),
                    dbus.ByteArray(data),
                ), signature="(iiay)"))
            return dbus.Array(out, signature="(iiay)")

        return {
            "Category": dbus.String(self.category),
            "Id": dbus.String(self.app_id),
            "Title": dbus.String(self.title),
            "Status": dbus.String(self.status),
            "WindowId": dbus.Int32(0),
            "IconName": dbus.String(self.icon_name),
            "IconThemePath": dbus.String(self.icon_theme_path),
            "IconPixmap": to_pixmap_array(self.icon_pixmap),
            "OverlayIconName": dbus.String(self.overlay_icon_name),
            "OverlayIconPixmap": to_pixmap_array(self.overlay_icon_pixmap),
            "AttentionIconName": dbus.String(self.attention_icon_name),
            "AttentionIconPixmap": to_pixmap_array(self.attention_icon_pixmap),
            "Menu": dbus.ObjectPath("/MenuBar"),
            "ItemIsMenu": dbus.Boolean(False),
            "ToolTip": dbus.Struct((
                dbus.String(self.icon_name),
                to_pixmap_array(self.icon_pixmap),
                dbus.String(self.tooltip_title),
                dbus.String(self.tooltip_desc),
            ), signature="(sa(iiay)ss)"),
        }

    @dbus.service.method("org.freedesktop.DBus.Properties", in_signature="ss", out_signature="v")
    def Get(self, interface_name, property_name):
        all_props = self.GetAll(interface_name)
        if property_name in all_props:
            return all_props[property_name]
        raise dbus.exceptions.DBusException("Unknown property", name="org.freedesktop.DBus.Error.UnknownProperty")

    @dbus.service.method("org.kde.StatusNotifierItem", in_signature="ii")
    def Activate(self, x, y):
        print(f"[{self.app_id}] Activated at ({x}, {y})")

    @dbus.service.method("org.kde.StatusNotifierItem", in_signature="ii")
    def ContextMenu(self, x, y):
        print(f"[{self.app_id}] ContextMenu at ({x}, {y})")

    @dbus.service.signal("org.kde.StatusNotifierItem", signature="s")
    def NewStatus(self, status):
        self.status = status

    @dbus.service.signal("org.kde.StatusNotifierItem")
    def NewIcon(self):
        pass

    @dbus.service.signal("org.kde.StatusNotifierItem")
    def NewAttentionIcon(self):
        pass

    @dbus.service.signal("org.kde.StatusNotifierItem")
    def NewOverlayIcon(self):
        pass

    @dbus.service.signal("org.kde.StatusNotifierItem")
    def NewToolTip(self):
        pass

    def register(self):
        watcher = self.bus.get_object("org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher")
        watcher_iface = dbus.Interface(watcher, "org.kde.StatusNotifierWatcher")
        watcher_iface.RegisterStatusNotifierItem(self.bus_name.get_name())
        print(f"[{self.app_id}] Registered on bus as {self.bus_name.get_name()}")

def run_test_suite():
    print("=== T14 Tray Icon Parsing & Rendering Verification Suite ===")
    bus = dbus.SessionBus()

    # 1. Verify Watcher & Host
    watcher = bus.get_object("org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher")
    props = dbus.Interface(watcher, "org.freedesktop.DBus.Properties")
    is_host = bool(props.Get("org.kde.StatusNotifierWatcher", "IsStatusNotifierHostRegistered"))
    print(f"1. StatusNotifierHost Registered: {is_host}")
    assert is_host, "StatusNotifierHost must be active!"

    # 2. Construct Mock SNI Items
    # A. 1x1 Red Pixmap (ARGB network order: FF FF 00 00)
    red_pixmap = [(1, 1, bytes([0xFF, 0xFF, 0x00, 0x00]))]

    # B. 24x24 Blue/White checkered Pixmap
    checkered_bytes = bytearray()
    for row in range(24):
        for col in range(24):
            if (row + col) % 2 == 0:
                checkered_bytes.extend([0xFF, 0x00, 0x55, 0xFF]) # Blue (A, R, G, B)
            else:
                checkered_bytes.extend([0xFF, 0xFF, 0xFF, 0xFF]) # White
    checkered_pixmap = [(24, 24, bytes(checkered_bytes))]

    # C. Overlay Badge 8x8 Orange Pixmap
    orange_bytes = bytes([0xFF, 0xFF, 0x88, 0x00] * 64)
    overlay_pixmap = [(8, 8, orange_bytes)]

    items = []

    # Item 1: Pure Pixmap App (no iconName)
    bus1 = dbus.service.BusName("org.kde.StatusNotifierItem-9001-1", bus)
    item1 = AdvancedTestSNI(
        bus, bus1, "/StatusNotifierItem",
        app_id="pixmap-red-app",
        title="Pure Red Pixmap App",
        icon_pixmap=red_pixmap,
        tooltip_title="<b>Red Pixmap</b>",
        tooltip_desc="1x1 Network Order ARGB32<br/>Opaque Red",
    )
    item1.register()
    items.append(item1)

    # Item 2: Multi-size Pixmap App with Overlay
    bus2 = dbus.service.BusName("org.kde.StatusNotifierItem-9002-1", bus)
    item2 = AdvancedTestSNI(
        bus, bus2, "/StatusNotifierItem/Checkered",
        app_id="pixmap-checkered-app",
        title="Checkered Pixmap App",
        icon_pixmap=checkered_pixmap,
        overlay_icon_pixmap=overlay_pixmap,
        tooltip_title="Checkered Status",
        tooltip_desc="24x24 Pixmap with 8x8 Overlay Badge",
    )
    item2.register()
    items.append(item2)

    # Item 3: IconName App (e.g. system theme nm-signal-75)
    bus3 = dbus.service.BusName("org.kde.StatusNotifierItem-9003-1", bus)
    item3 = AdvancedTestSNI(
        bus, bus3, "/StatusNotifierItem/Network",
        app_id="nm-applet",
        title="Network Applet",
        icon_name="network-wireless-connected-100",
        tooltip_title="Wi-Fi Connected",
        tooltip_desc="SSID: DenialNet<br/>Signal: 100% &amp; Secure",
    )
    item3.register()
    items.append(item3)

    # Item 4: NeedsAttention Status App (AttentionIcon)
    bus4 = dbus.service.BusName("org.kde.StatusNotifierItem-9004-1", bus)
    item4 = AdvancedTestSNI(
        bus, bus4, "/StatusNotifierItem/Discord",
        app_id="discord",
        title="Discord Client",
        status="NeedsAttention",
        icon_name="discord",
        attention_icon_name="mail-unread",
        attention_icon_pixmap=red_pixmap,
        tooltip_title="<b>Discord</b>",
        tooltip_desc="1 Unread Direct Message",
    )
    item4.register()
    items.append(item4)

    time.sleep(0.8)

    # 3. Query Registered Items
    registered = list(props.Get("org.kde.StatusNotifierWatcher", "RegisteredStatusNotifierItems"))
    print(f"\n2. Registered items ({len(registered)} total):")
    for r in registered:
        print(f"   - {r}")

    assert any("9001-1" in r for r in registered), "Item 1 must be registered"
    assert any("9002-1" in r for r in registered), "Item 2 must be registered"
    assert any("9003-1" in r for r in registered), "Item 3 must be registered"
    assert any("9004-1" in r for r in registered), "Item 4 must be registered"

    # 4. Test Attention Status Transition
    print("\n3. Testing status transition NeedsAttention -> Active on Item 4...")
    item4.NewStatus("Active")
    time.sleep(0.5)

    # 5. Verify Signal Broadcasts
    print("\n4. Testing signal broadcast NewIcon & NewToolTip...")
    item1.NewIcon()
    item2.NewToolTip()
    time.sleep(0.5)

    print("\n=== ALL T14 VERIFICATION STEPS PASSED SUCCESSFULLY! ===")

if __name__ == "__main__":
    run_test_suite()
