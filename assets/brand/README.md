# Mema brand assets

`mema-app-icon-1024.png` is the checked-in full-resolution source supplied for
the current Mema app mark. Runtime-sized exports live with the clients that
consume them:

- macOS AppIcon variants are in
  `apps/macos/Mema/Resources/Assets.xcassets/AppIcon.appiconset/`;
- Chrome extension icons are in `apps/chrome-extension/assets/icons/`.

Keep the generated sizes and their manifests in sync when the mark changes. The
color app icon is not a macOS menu-bar template image; the menu-bar item should
continue using an SF Symbol or a purpose-built monochrome template asset.
