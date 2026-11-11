# calendarLens <a href="https://github.com/TimMacy/calendarLens/releases"><img height="25px" align="right" src="https://img.shields.io/github/v/release/TimMacy/calendarLens?style=for-the-badge" alt="Releases"></a><a href="https://github.com/TimMacy/calendarLens/blob/main/LICENSE"><img height="25px" align="right" src="https://img.shields.io/github/license/TimMacy/calendarLens?style=for-the-badge&color=white" alt="MIT License"></a>

A Mac app that reads Calendar events to visualize where the time went. Each tracker follows one or more event titles in Calendar to show the weekly total and daily average.

<p align="center"><img width="80%" alt="calendarLens" src="https://github.com/user-attachments/assets/5016cc66-467c-4377-89c6-38fabb8f12f7" /></p>

## Add a Tracker
1. Allow Full Access.
2. Click **+** to add a tracker.
3. Enter a name, pick a calendar, and check one or more event titles.
4. Choose whether events count toward the day they start or end.
5. Optionally, set a daily goal and how many days per week count toward the average.
6. Click **Save**.

Only completed events are included, and overlapping events are merged. Use **←** and **→** to move between weeks, and **↑** or **↓** to return to the current week.

## Colors
By default, each tracker uses its calendar's color. Turn off **Use Calendar color** to pick a different one. If a color is too dark, click the **Use Lighter Color** button in settings.

## Install

Requires macOS 27 or later. Download the app from [Releases](https://github.com/TimMacy/calendarLens/releases), or build from source with `bash build.sh` using Xcode 27.

If macOS blocks the app, click [Open Anyway](https://support.apple.com/102445) under **System Settings → Privacy & Security**.

## Privacy

calendarLens only reads Calendar; it can't edit, store, or send events. Tracker settings, including calendar colors, are saved on the Mac inside the app's sandbox.

## License

MIT. See [LICENSE](LICENSE).