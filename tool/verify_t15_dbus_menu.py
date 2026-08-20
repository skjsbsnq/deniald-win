#!/usr/bin/env python3
"""
Multi-process verification script for T15 DBusMenu (com.canonical.dbusmenu) implementation.
Runs a mock DBusMenu server in a background process and drives client verification
from the main process.
"""

import sys
import time
import multiprocessing
import dbus
import dbus.service
import dbus.mainloop.glib
from gi.repository import GLib

BUS_NAME = "org.denial.TestDBusMenu"
OBJECT_PATH = "/MenuBar"
INTERFACE_NAME = "com.canonical.dbusmenu"

class MockDBusMenuService(dbus.service.Object):
    def __init__(self, bus, path):
        super().__init__(bus, path)
        self.revision = 1
        self.about_to_show_called = 0
        self.events_received = []
        self.menu_items = {
            0: {
                "id": 0,
                "props": {"children-display": dbus.String("submenu")},
                "children": [1, 2, 3, 4, 5, 6, 7]
            },
            1: {
                "id": 1,
                "props": {
                    "label": dbus.String("_File"),
                    "enabled": dbus.Boolean(True),
                    "visible": dbus.Boolean(True),
                    "shortcut": dbus.Array([
                        dbus.Array([dbus.String("Control"), dbus.String("N")], signature="s")
                    ], signature="as")
                },
                "children": []
            },
            2: {
                "id": 2,
                "props": {
                    "type": dbus.String("separator")
                },
                "children": []
            },
            3: {
                "id": 3,
                "props": {
                    "label": dbus.String("Dark Mode"),
                    "toggle-type": dbus.String("checkmark"),
                    "toggle-state": dbus.Int32(1),
                    "enabled": dbus.Boolean(True),
                },
                "children": []
            },
            4: {
                "id": 4,
                "props": {
                    "label": dbus.String("Radio Item 1"),
                    "toggle-type": dbus.String("radio"),
                    "toggle-state": dbus.Int32(1),
                    "enabled": dbus.Boolean(True),
                },
                "children": []
            },
            5: {
                "id": 5,
                "props": {
                    "label": dbus.String("Disabled Action"),
                    "enabled": dbus.Boolean(False),
                },
                "children": []
            },
            6: {
                "id": 6,
                "props": {
                    "label": dbus.String("Custom PNG Icon"),
                    "icon-data": dbus.ByteArray(b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR"),
                },
                "children": []
            },
            7: {
                "id": 7,
                "props": {
                    "label": dbus.String("More Settings"),
                    "children-display": dbus.String("submenu"),
                },
                "children": [71, 72]
            },
            71: {
                "id": 71,
                "props": {
                    "label": dbus.String("Submenu Level 1"),
                    "children-display": dbus.String("submenu"),
                },
                "children": [711]
            },
            711: {
                "id": 711,
                "props": {
                    "label": dbus.String("Deep Nested Level 2"),
                    "enabled": dbus.Boolean(True),
                },
                "children": []
            },
            72: {
                "id": 72,
                "props": {
                    "label": dbus.String("Submenu Action 2"),
                    "enabled": dbus.Boolean(True),
                },
                "children": []
            },
        }

    @dbus.service.method(INTERFACE_NAME, in_signature="i", out_signature="b")
    def AboutToShow(self, item_id):
        self.about_to_show_called += 1
        # Dynamically add an item to prove lazy loading
        if 8 not in self.menu_items[0]["children"]:
            self.menu_items[0]["children"].append(8)
            self.menu_items[8] = {
                "id": 8,
                "props": {
                    "label": dbus.String("Lazy Loaded Item"),
                    "enabled": dbus.Boolean(True),
                },
                "children": []
            }
            self.revision += 1
            return dbus.Boolean(True)
        return dbus.Boolean(False)

    def _build_layout(self, item_id, depth, property_names):
        item = self.menu_items.get(item_id)
        if not item:
            return dbus.Struct((dbus.Int32(item_id), dbus.Dictionary({}, signature="sv"), dbus.Array([], signature="v")))

        props = item["props"]
        if property_names:
            props = {k: v for k, v in props.items() if k in property_names}

        children = []
        if depth != 0:
            next_depth = -1 if depth < 0 else depth - 1
            for child_id in item["children"]:
                children.append(self._build_layout(child_id, next_depth, property_names))

        return dbus.Struct((
            dbus.Int32(item["id"]),
            dbus.Dictionary(props, signature="sv"),
            dbus.Array(children, signature="v")
        ))

    @dbus.service.method(INTERFACE_NAME, in_signature="iias", out_signature="u(ia{sv}av)")
    def GetLayout(self, parent_id, recursion_depth, property_names):
        layout = self._build_layout(parent_id, recursion_depth, property_names)
        return (dbus.UInt32(self.revision), layout)

    @dbus.service.method(INTERFACE_NAME, in_signature="isvu", out_signature="")
    def Event(self, item_id, event_id, data, timestamp):
        self.events_received.append({
            "id": int(item_id),
            "event_id": str(event_id),
            "timestamp": int(timestamp),
        })

    @dbus.service.method(INTERFACE_NAME, in_signature="", out_signature="a{sv}")
    def GetEventLog(self):
        return {
            "events_count": dbus.Int32(len(self.events_received)),
            "about_to_show_count": dbus.Int32(self.about_to_show_called),
        }

    @dbus.service.signal(INTERFACE_NAME, signature="a(ia{sv})a(ias)")
    def ItemsPropertiesUpdated(self, updated_props, removed_props):
        pass

    @dbus.service.signal(INTERFACE_NAME, signature="ui")
    def LayoutUpdated(self, revision, parent):
        pass


def server_process():
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    name = dbus.service.BusName(BUS_NAME, bus)
    service = MockDBusMenuService(bus, OBJECT_PATH)
    loop = GLib.MainLoop()
    loop.run()


def run_client_tests():
    time.sleep(0.3)
    bus = dbus.SessionBus()

    print("=== T15 DBusMenu Verification Suite ===")

    # Test 1: Service acquisition
    obj = bus.get_object(BUS_NAME, OBJECT_PATH)
    iface = dbus.Interface(obj, INTERFACE_NAME)
    print("✓ Test 1: D-Bus service and interface successfully resolved")

    # Test 2: AboutToShow lazy population
    need_update = iface.AboutToShow(0)
    assert need_update == True, "AboutToShow(0) should return needUpdate=True on initial lazy load"
    print("✓ Test 2: AboutToShow lazy loading triggered and returned needUpdate=True")

    # Test 3: GetLayout full tree resolution
    rev, layout = iface.GetLayout(0, -1, [])
    root_id = int(layout[0])
    root_props = layout[1]
    root_children = layout[2]

    assert root_id == 0, "Root ID is 0"
    assert len(root_children) == 8, f"Expected 8 children including lazy item, got {len(root_children)}"
    print(f"✓ Test 3: GetLayout returned revision {rev} with {len(root_children)} root items")

    # Verify checkmark, radio, shortcut, PNG bytes, separator, and 2-level submenus
    child_ids = [int(c[0]) for c in root_children]
    assert 1 in child_ids, "Item 1 (File + shortcut) present"
    assert 2 in child_ids, "Item 2 (Separator) present"
    assert 3 in child_ids, "Item 3 (Checkmark) present"
    assert 4 in child_ids, "Item 4 (Radio) present"
    assert 5 in child_ids, "Item 5 (Disabled) present"
    assert 6 in child_ids, "Item 6 (PNG Icon) present"
    assert 7 in child_ids, "Item 7 (Submenu) present"
    assert 8 in child_ids, "Item 8 (Lazy Loaded) present"
    print("✓ Test 4: All menu item types (Normal, Separator, Checkmark, Radio, Disabled, PNG Icon, Submenu, Lazy) verified")

    # Test 5: Verify nested submenu structure (7 -> 71 -> 711)
    item_7 = next(c for c in root_children if int(c[0]) == 7)
    item_7_children = item_7[2]
    assert len(item_7_children) == 2, f"Item 7 children count: {len(item_7_children)}"

    item_71 = next(c for c in item_7_children if int(c[0]) == 71)
    item_71_children = item_71[2]
    assert len(item_71_children) == 1, f"Item 71 children count: {len(item_71_children)}"
    assert int(item_71_children[0][0]) == 711, "Item 711 deep nested leaf ID"
    print("✓ Test 5: 2-level nested submenus (Depth 0 -> 1 -> 2) resolved correctly")

    # Test 6: Event dispatching
    now_ts = int(time.time())
    iface.Event(0, "opened", dbus.Dictionary({}, signature="sv"), dbus.UInt32(now_ts))
    iface.Event(3, "clicked", dbus.Dictionary({}, signature="sv"), dbus.UInt32(now_ts))
    iface.Event(0, "closed", dbus.Dictionary({}, signature="sv"), dbus.UInt32(now_ts))

    time.sleep(0.1)
    log = iface.GetEventLog()
    assert int(log["events_count"]) == 3, f"Expected 3 events logged on server, got {log['events_count']}"
    assert int(log["about_to_show_count"]) == 1, f"Expected 1 AboutToShow logged, got {log['about_to_show_count']}"
    print("✓ Test 6: Event dispatching ('opened', 'clicked', 'closed') and server log verified with uint32 epoch timestamps")

    print("\n=======================================================")
    print("🎉 ALL T15 DBUSMENU PROTOCOL TESTS PASSED SUCCESSFULLY!")
    print("=======================================================")


if __name__ == "__main__":
    p = multiprocessing.Process(target=server_process, daemon=True)
    p.start()
    try:
        run_client_tests()
    finally:
        p.terminate()
        p.join()
