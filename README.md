# MissionControlExtend

A lightweight macOS agent that enhances Mission Control by adding window management overlays and shortcuts.

## Features

* **Close Buttons**: Adds a clean close (`✕`) button on window thumbnails in Mission Control.
* **Click to Close**: Intercepts mouse clicks on overlays to close windows instantly.
* **Keyboard Shortcuts**:
  * `⌘W`: Close the window currently under the cursor.
  * `⌘Q`: Quit the application of the window currently under the cursor.
* **Menu Bar Agent**: Runs silently in the background with a status item (`✕`). No Dock icon.
* **Native & Efficient**: Written in Swift, using standard Accessibility APIs with zero-dependency polling.

## Requirements

* macOS 11.0 or later.
* **Accessibility Permissions**: Required to detect Mission Control windows and simulate close events.

## Build & Run

1. Clone the repository.
2. Open terminal in the directory and build the app:
   ```bash
   ./build.sh
   ```
3. Launch the compiled application:
   ```bash
   open MissionControlExtend.app
   ```
4. Click the menu bar icon `✕` and select **Grant Accessibility Permissions**.
5. Enable **Mission Control Extend** in *System Settings > Privacy & Security > Accessibility*.

## License

MIT License
