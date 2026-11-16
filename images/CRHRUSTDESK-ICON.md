# CrhRustDesk icon

Source: `logo1.jpg`. The original JPEG is unchanged. Background extraction used the built-in imagegen tool with a transparent background. The selected PNG is saved as `logo1-transparent.png`; its alpha channel contains transparent and opaque pixels. White monitor and mouse details remain part of the logo.

Final prompt:

> Edit the provided logo file as the exact edit target. Remove ONLY the exterior dark navy blue background and the navy background visible in the open empty spaces between the monitor, letters, mouse and cable so that those empty areas have genuine transparent alpha. Preserve the CRH lettering exactly, the green/gold medical monitor with ECG, its white lower bezel and white base, green stand, green mouse with white highlights and cable, and dark navy outlines which are part of the foreground logo. Do NOT erase white parts of the monitor or mouse; these are foreground. Do not redesign the logo, change text, add any elements, or add a background/checkerboard/shadow. Tight, balanced square framing for an application icon, modest transparent padding around the complete logo, sharp clean edges, transparent PNG.

Windows System.Drawing converted the transparent PNG into PNG-encoded ICO frames at 16, 20, 24, 32, 40, 48, 64, 128 and 256 pixels. This was asset conversion only; the application and installer were not built.

Assets:

* `flutter/assets/crhrustdesk_icon.png`: in-app icon and packaged tray image.
* `flutter/windows/runner/resources/crhrustdesk_icon.ico`: Windows executable, taskbar and shortcut icon for the CrhRustDesk build.
* `res/crhrustdesk/icon.ico`: embedded tray fallback and installer icon source.

Existing paths changed: `flutter/lib/common.dart` selects the asset for CrhRustDesk; `Runner.rc` selects the Windows icon under the existing branding define; `src/tray.rs` selects the feature's runtime and embedded icons; `build.rs` selects the icon for a Windows inline CrhRustDesk build. Feature-disabled paths retain their original assets. CrhRustDesk build scripts copy the ICO into the bundle and the Inno script uses it as SetupIconFile. These asset selectors are necessary for the same icon to appear in each Windows surface after the next requested build.

The repository ignores PNG files by default. Two explicit `.gitignore` exceptions keep the new source PNG and runtime PNG available for version control.

Validation: both PNG copies have RGBA transparency; both ICO copies contain nine readable sizes with transparent corners. No native compilation, Flutter build, installer compilation or icon-generator command was run. Runtime appearance remains to be checked after an explicitly requested build.
