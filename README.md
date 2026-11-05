# WakeWise

WakeWise is a local-first alarm clock for Android and iOS, built with Flutter.
Alarm records are stored in Hive. The pinned `alarm` plugin schedules native
alarms, plays a looping system alarm sound, vibrates, and displays the Android
full-screen alarm notification.

## App icon

The WakeWise launcher icon uses a lavender alarm clock on a deep indigo
background, with teal and warm peach clock hands. The 1024 px master artwork is
`assets/wakewise-icon.png`; Android density assets and the iOS App Store icon
are generated from this master.

## Run

1. Install the current stable Flutter SDK and platform tooling.
2. Connect an Android phone (USB debugging enabled) or an iPhone configured
   for development signing.
3. Run:

   ```sh
   flutter pub get
   flutter run
   ```

4. On first launch, grant notifications, exact-alarm access, and full-screen
   alarm access. Battery-optimization exemption is recommended on Android.
5. Add an alarm and use the app's Settings > Permission check page if a system
   permission is missing.

Build an Android APK with `flutter build apk --release`. iOS builds must be made
on macOS with Xcode signing configured.

## Alarm behavior

- Alarms use local device time. Repeating alarms use Monday=1 through Sunday=7.
- Android schedules exact alarm-clock events with the `alarm` plugin. The
  plugin's boot receiver restores alarms after reboot. WakeWise also rebuilds
  schedules when it returns to the foreground, including after a timezone or
  daylight-saving offset change.
- Repeating alarms are queued for the coming 14 days. When the ringing screen
  opens, WakeWise extends that window; reopening the app also refreshes it.
- Alarm audio uses the device's default alarm sound, loops natively, and fades
  in over 30 seconds. Snooze defaults to five minutes.
- Each alarm can optionally require a wake-up challenge: shake the phone 30
  times or walk 20 steps. Snooze and dismiss controls remain unavailable until
  the selected challenge is completed. Walk challenges require Activity
  Recognition permission on Android and motion usage permission on iOS.
- The screen shown while ringing has Snooze and Dismiss controls. Android can
  show it over the lock screen when full-screen alarm access is granted.

## Android setup

The alarm plugin contributes the exact-alarm, notification, boot receiver,
foreground media playback service, wake lock, vibration, and full-screen intent
declarations. `android/app/src/main/AndroidManifest.xml` additionally declares
`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` and the app registers the plugin's
notification-on-kill service. The minimum Android SDK is 23.

On Android 12 and newer, grant exact-alarm access. Android 13 and newer also
require notification permission. Android 14 and newer may require separately
allowing full-screen notifications for WakeWise in system settings. Some device
vendors have additional autostart or battery controls.

## iOS setup and limitations

The iOS target enables audio/background-fetch modes and the alarm plugin's
background task identifier. Standard notification permission is requested;
critical alerts are not enabled because Apple requires a special entitlement.

iOS does not provide Android-equivalent exact alarms or a general-purpose
background service. The alarm plugin cannot guarantee that sound continues
after a user force-quits the app or restarts the phone. Scheduled iOS alarms
depend on system notification/background policies, so test on a physical
device. Critical alerts, if needed, require an Apple-approved entitlement.

## Device test checklist

- Schedule an alarm one or two minutes ahead; verify sound, vibration, snooze,
  and dismiss.
- Lock the phone before the alarm. On Android, verify the full-screen screen
  opens and the alarm rings.
- Reboot Android after scheduling an alarm, unlock the phone, and verify it is
  still scheduled.
- Close the app normally and test Android alarm delivery. Avoid Force stop:
  Android intentionally suppresses alarms for force-stopped apps until the
  user launches them again.
- Test with Do Not Disturb, battery saver, and the manufacturer's battery
  optimization controls enabled and disabled.
- Change timezone or cross a daylight-saving transition, then reopen WakeWise
  and verify the displayed and scheduled local time.
- On iOS, test with the app backgrounded and locked; separately verify the
  documented force-quit and reboot limitations.

## Code layout

- `lib/models/` — persisted alarm and settings data.
- `lib/providers/` — Riverpod state backed by Hive.
- `lib/services/` — native alarm scheduling, persistence, and permissions.
- `lib/screens/` — onboarding, alarm list/editor, ringing, and settings UI.
