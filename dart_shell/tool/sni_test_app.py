#!/usr/bin/env python3
import sys
import time
import signal
import dbus
import dbus.service
import dbus.mainloop.glib
from gi.repository import GLib

dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)

class TestStatusNotifierItem(dbus.service.Object):
    def __init__(self, bus, bus_name, object_path, app_id, title, style="kde"):
        super().__init__(bus, object_path)
        self.bus = bus
        self.bus_name = bus_name
        self.object_path = object_path
        self.app_id = app_id
        self.title = title
        self.status = "Active"
        self.category = "ApplicationStatus"
        self.style = style

    @dbus.service.method("org.freedesktop.DBus.Properties", in_signature="s", out_signature="a{sv}")
    def GetAll(self, interface_name):
        if interface_name != "org.kde.StatusNotifierItem":
            return {}
        return {
            "Category": dbus.String(self.category),
            "Id": dbus.String(self.app_id),
            "Title": dbus.String(self.title),
            "Status": dbus.String(self.status),
            "WindowId": dbus.Int32(0),
            "IconName": dbus.String("application-default-icon"),
            "IconThemePath": dbus.String(""),
            "OverlayIconName": dbus.String(""),
            "AttentionIconName": dbus.String(""),
            "Menu": dbus.ObjectPath("/MenuBar"),
            "ItemIsMenu": dbus.Boolean(False),
            "ToolTip": dbus.Struct((
                dbus.String(""),
                dbus.Array([], signature="(iiay)"),
                dbus.String(self.title),
                dbus.String(f"{self.title} status description"),
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

    def register(self):
        watcher = self.bus.get_object("org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher")
        watcher_iface = dbus.Interface(watcher, "org.kde.StatusNotifierWatcher")
        if self.style == "kde":
            # Pass bus name
            watcher_iface.RegisterStatusNotifierItem(self.bus_name.get_name())
        elif self.style == "ayatana":
            # Pass object path
            watcher_iface.RegisterStatusNotifierItem(self.object_path)
        print(f"[{self.app_id}] Registered with style={self.style}")

def main():
    if len(sys.argv) < 5:
        print("Usage: sni_test_app.py <bus_name> <object_path> <id> <title> [kde|ayatana]")
        sys.exit(1)

    bus_name_str = sys.argv[1]
    obj_path = sys.argv[2]
    app_id = sys.argv[3]
    title = sys.argv[4]
    style = sys.argv[5] if len(sys.argv) > 5 else "kde"

    session_bus = dbus.SessionBus()
    bus_name = dbus.service.BusName(bus_name_str, session_bus)
    item = TestStatusNotifierItem(session_bus, bus_name, obj_path, app_id, title, style)
    item.register()

    loop = GLib.MainLoop()
    loop.run()

if __name__ == "__main__":
    main()
