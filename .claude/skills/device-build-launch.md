---
name: device-build-launch
description: Build Simba for a physical iPhone, install the .app via devicectl, and launch it on the device.
---

# Simba Device Build + Launch

Use this skill when asked to build and launch Simba on a connected iPhone (not the simulator).

## Workflow

1) List connected devices (to get the iOS device identifier used by Xcode).

```bash
xcrun devicectl list devices
```

2) Build for the device destination ID shown by Xcode (the iOS id, not the CoreDevice UUID).

```bash
xcodebuild -scheme Simba -destination "id=<DEVICE_ID>" build
```

3) Locate the built .app path from build settings.

```bash
xcodebuild -scheme Simba -destination "id=<DEVICE_ID>" -showBuildSettings | rg -n "BUILT_PRODUCTS_DIR|FULL_PRODUCT_NAME"
```

Combine:

```
<BUILT_PRODUCTS_DIR>/<FULL_PRODUCT_NAME>
```

4) Install the app to the device.

```bash
xcrun devicectl device install app --device <DEVICE_ID> <BUILT_PRODUCTS_DIR>/<FULL_PRODUCT_NAME>
```

5) Launch the app by bundle id.

```bash
xcrun devicectl device process launch --device <DEVICE_ID> com.bb.simba.app
```

## Notes

- Use the iOS destination ID from `xcodebuild` output (looks like `00008150-...`).
- If the device name includes an apostrophe, wrap the destination in double quotes.
- If build fails with a missing device, re-run step 1 and use the iOS destination ID listed under available destinations.
