#!/usr/bin/env python3
import subprocess
import time
import sys
import dbus

def get_registered_items(bus):
    watcher = bus.get_object("org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher")
    props = dbus.Interface(watcher, "org.freedesktop.DBus.Properties")
    items = props.Get("org.kde.StatusNotifierWatcher", "RegisteredStatusNotifierItems")
    return list(items)

def get_host_registered(bus):
    watcher = bus.get_object("org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher")
    props = dbus.Interface(watcher, "org.freedesktop.DBus.Properties")
    return bool(props.Get("org.kde.StatusNotifierWatcher", "IsStatusNotifierHostRegistered"))

def main():
    bus = dbus.SessionBus()
    print("=== T13 SNI Verification Suite ===")

    # 1. Check Watcher & Host
    is_host = get_host_registered(bus)
    print(f"1. IsStatusNotifierHostRegistered: {is_host}")
    assert is_host, "Host must be registered!"

    initial_items = get_registered_items(bus)
    print(f"Initial registered items: {initial_items}")

    # 2. Launch 3 distinct apps
    print("\n2. Launching 3 SNI applications (KDE style + Ayatana style)...")
    p1 = subprocess.Popen([
        sys.executable, "tool/sni_test_app.py",
        "org.kde.StatusNotifierItem-5001-1", "/StatusNotifierItem",
        "steam", "Steam Client", "kde"
    ])
    time.sleep(0.5)

    p2 = subprocess.Popen([
        sys.executable, "tool/sni_test_app.py",
        "org.ayatana.NotificationItem.nm_applet", "/org/ayatana/NotificationItem/nm_applet",
        "nm-applet", "Network Applet", "ayatana"
    ])
    time.sleep(0.5)

    p3 = subprocess.Popen([
        sys.executable, "tool/sni_test_app.py",
        "org.kde.StatusNotifierItem-5003-1", "/StatusNotifierItem",
        "discord", "Discord", "kde"
    ])
    time.sleep(0.8)

    items_3 = get_registered_items(bus)
    print(f"Items with 3 apps running: {items_3}")
    assert len(items_3) >= 3, f"Expected at least 3 items, got {len(items_3)}"

    # Check Ayatana entry is registered
    ayatana_found = any("/org/ayatana/NotificationItem/nm_applet" in item for item in items_3)
    print(f"Ayatana style item registered: {ayatana_found}")
    assert ayatana_found, "Ayatana style item must be tracked!"

    # 3. Crash termination test (kill -9 on Steam)
    print("\n3. Testing crash termination (kill -9 on Steam)...")
    p1.kill()
    p1.wait()
    time.sleep(0.8)

    items_after_kill = get_registered_items(bus)
    print(f"Items after killing Steam: {items_after_kill}")
    steam_present = any("5001" in item or "steam" in item for item in items_after_kill)
    print(f"Steam still in items? {steam_present}")
    assert not steam_present, "Steam item must be removed after crash (kill -9)!"

    # 4. Normal exit test (SIGTERM on nm-applet)
    print("\n4. Testing normal termination on nm-applet...")
    p2.terminate()
    p2.wait()
    time.sleep(0.8)

    items_after_term = get_registered_items(bus)
    print(f"Items after terminating nm-applet: {items_after_term}")
    nm_present = any("nm_applet" in item for item in items_after_term)
    print(f"nm-applet still in items? {nm_present}")
    assert not nm_present, "nm-applet must be removed after exit!"

    # 5. Repeated start/stop test (10 cycles)
    print("\n5. Testing 10 cycles of rapid start & kill on a test app...")
    p3.kill()
    p3.wait()
    time.sleep(0.5)

    for i in range(10):
        temp_p = subprocess.Popen([
            sys.executable, "tool/sni_test_app.py",
            f"org.kde.StatusNotifierItem-loop-{i}", "/StatusNotifierItem",
            f"loop_app_{i}", f"Loop App {i}", "kde"
        ])
        time.sleep(0.3)
        current = get_registered_items(bus)
        assert any(f"loop-{i}" in item for item in current), f"Iteration {i} failed to register"
        temp_p.kill()
        temp_p.wait()
        time.sleep(0.3)

    final_items = get_registered_items(bus)
    print(f"Final items after 10 loop cycles: {final_items}")
    loop_leaks = [item for item in final_items if "loop" in item]
    assert len(loop_leaks) == 0, f"Found leaked loop items: {loop_leaks}"

    print("\n=== ALL SNI LIFECYCLE TESTS PASSED! ===")

if __name__ == "__main__":
    main()
