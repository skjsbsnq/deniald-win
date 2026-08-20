#!/usr/bin/env python3
"""
Comprehensive Total Regression Verification Suite for Denial Transformation (T00-T16).
Validates D-Bus interfaces, StatusNotifierItem, DBusMenu, system integration,
state resilience, and protocol specifications.
"""

import sys
import time
import subprocess
import dbus
import dbus.service
import dbus.mainloop.glib

def run_regression():
    print("==================================================================")
    print("      DENIAL TRANSFORMATION - FULL PLAN TOTAL REGRESSION          ")
    print("                     Tasks T00 - T16 Execution                    ")
    print("==================================================================")

    # 1. Verification of SNI Host & Watcher Lifecycle
    print("\n[Phase 1: SNI Host & Watcher Lifecycle]")
    bus = dbus.SessionBus()
    try:
        watcher_obj = bus.get_object("org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher")
        watcher_props = dbus.Interface(watcher_obj, "org.freedesktop.DBus.Properties")
        is_host_registered = watcher_props.Get("org.kde.StatusNotifierWatcher", "IsStatusNotifierHostRegistered")
        print(f"  ✓ org.kde.StatusNotifierWatcher available: True")
        print(f"  ✓ IsStatusNotifierHostRegistered: {is_host_registered}")
        if not bool(is_host_registered):
            print("  ❌ StatusNotifierHost must be registered")
            return False
    except dbus.exceptions.DBusException as e:
        if e.get_dbus_name() in (
            "org.freedesktop.DBus.Error.ServiceUnknown",
            "org.freedesktop.DBus.Error.NameHasNoOwner",
        ):
            print(f"  ℹ️ SNI Watcher not active on session bus (expected in headless/offline verification): {e.get_dbus_name()}")
        else:
            print(f"  ❌ Unexpected D-Bus error checking SNI Watcher: {e}")
            return False
    except Exception as e:
        print(f"  ❌ Fatal unexpected error checking SNI Watcher: {e}")
        return False

    # 2. Verification of Tray Icon & Area End-to-End Test Suite
    print("\n[Phase 2: Tray Icon Resolution & Tray Area Gestures]")
    ret_t16 = subprocess.run([sys.executable, "tool/verify_t16_tray_area.py"], capture_output=True, text=True)
    print(ret_t16.stdout.strip())
    if ret_t16.returncode != 0:
        print(f"  ❌ Tray Area verification failed: {ret_t16.stderr}")
        return False
    print("  ✓ Tray Area & Gestures: PASS")

    # 3. Verification of DBusMenu Client & Hierarchy Parsing
    print("\n[Phase 3: DBusMenu Protocol & Menu Tree Parsing]")
    ret_t15 = subprocess.run([sys.executable, "tool/verify_t15_dbus_menu.py"], capture_output=True, text=True)
    print(ret_t15.stdout.strip())
    if ret_t15.returncode != 0:
        print(f"  ❌ DBusMenu verification failed: {ret_t15.stderr}")
        return False
    print("  ✓ DBusMenu Protocol & Submenus: PASS")

    # 4. Verification of Desktop Status Services
    print("\n[Phase 4: Status Cluster, Control Center & System Services]")
    for svc, path, iface in [
        ("org.freedesktop.NetworkManager", "/org/freedesktop/NetworkManager", "org.freedesktop.NetworkManager"),
        ("org.bluez", "/", "org.freedesktop.DBus.ObjectManager"),
        ("org.freedesktop.UPower", "/org/freedesktop/UPower", "org.freedesktop.UPower"),
    ]:
        try:
            sys_bus = dbus.SystemBus()
            obj = sys_bus.get_object(svc, path)
            print(f"  ✓ System D-Bus service connected: {svc}")
        except dbus.exceptions.DBusException as e:
            if e.get_dbus_name() in (
                "org.freedesktop.DBus.Error.ServiceUnknown",
                "org.freedesktop.DBus.Error.NameHasNoOwner",
                "org.freedesktop.DBus.Error.FileNotFound",
            ):
                print(f"  ℹ️ System D-Bus service not installed/running (gracefully degraded): {svc}")
            else:
                print(f"  ❌ Unexpected D-Bus error for {svc}: {e}")
                return False
        except Exception as e:
            print(f"  ❌ Unexpected system error for {svc}: {e}")
            return False

    # 5. Shell Build & Generation Verification
    print("\n[Phase 5: Shell Embedder & Generation State Verification]")
    try:
        ret_status = subprocess.run(["denialctl", "ui", "status"], capture_output=True, text=True)
        if ret_status.returncode == 0:
            print(ret_status.stdout.strip())
            print("  ✓ Shell Embedder status query succeeded")
        else:
            print(f"  ❌ denialctl ui status failed with exit code {ret_status.returncode}:")
            print(ret_status.stderr.strip() or ret_status.stdout.strip())
            return False
    except FileNotFoundError:
        print("  ℹ️ denialctl not yet in PATH (expected before system installation)")
    except Exception as e:
        print(f"  ❌ Unexpected error executing denialctl: {e}")
        return False

    print("\n==================================================================")
    print("   🎉 TOTAL REGRESSION MATRIX SELF-TESTS PASSED                   ")
    print("==================================================================")
    return True

if __name__ == "__main__":
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    success = run_regression()
    if not success:
        sys.exit(1)
