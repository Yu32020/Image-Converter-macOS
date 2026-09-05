# Image Converter for macOS

A small, local SwiftUI utility for converting images to JPEG, PNG, TIFF and HEIC. Includes English and Simplified Chinese, drag and drop, and a file picker.

**The maintenance fixes below are in the current source. The existing v1.0 release download does not include them; build the current source to use this version.**

## What changed in 1.1

- Originals and existing output files are preserved. Name collisions become `photo (1).png`, `photo (2).png`, and so on, including conversion back into the source folder. Images are encoded to a temporary file, then published atomically without overwriting an existing path.
- Duplicate inputs are removed across files, folders and repeated imports. Directories with image-like names are not treated as images.
- Import and conversion cannot change the queue at the same time. Conversion and thumbnail decoding run away from the UI, with one conversion and one thumbnail decoder at a time.
- Add images with **Add Images…** or **⌘O**, remove individual items, inspect failure details and reveal results in Finder. **Stop** finishes the current image and leaves the remaining queue unconverted; completed files are kept. Starting again converts the whole queue to new output files.
- JPEG transparency is composited onto white. PNG and TIFF preserve transparency. EXIF orientation is applied to the output pixels.
- App Sandbox stays enabled with access to user-selected files and folders. Network access is disabled; no account or upload is needed.

## Requirements and format limits

- macOS **13 or later**; Xcode **26 or later** for the Swift 6 source and project format. This maintenance revision was built and regression-tested with Xcode 27 / Swift 6.4 on Apple Silicon. Older supported macOS versions have not been runtime-tested.
- Inputs: JPEG, PNG, TIFF, HEIC/HEIF and selected RAW extensions (NEF, CR2, CR3, DNG, ARW, ORF, PEF, RAW). Actual RAW camera support and HEIC encoding depend on the installed macOS version and hardware; unsupported or damaged images produce a visible per-file error.
- Adding a folder scans its **immediate visible image files only**. It does not traverse subfolders.
- This is a **single-image conversion tool**. It does not preserve multi-page TIFFs, image sequences, HEIC auxiliary images, RAW editing data or all source metadata.
- Output uses **8-bit sRGB** rendering. PNG/TIFF compression is lossless for the rendered pixels, but converting a high-bit-depth, HDR, wide-gamut or RAW source is not an archival lossless operation. JPEG quality is 90%; HEIC quality is 85%. Keep originals when source detail or metadata matters.

## Build and use

```sh
git clone https://github.com/Yu32020/Image-Converter-macOS.git
cd Image-Converter-macOS
open 'Image Converter.xcodeproj'
```

Select the **Image Converter** scheme, choose your development team in Signing & Capabilities if needed, and run on **My Mac**. Keep App Sandbox and user-selected read/write file access enabled.

For an unsigned build check that does not require a development account:

```sh
xcodebuild -project 'Image Converter.xcodeproj' \
  -scheme 'Image Converter' -configuration Release \
  -destination 'platform=macOS' -derivedDataPath .build/DerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

Add images or folders, select the output format, then click **Convert…** (or **⌘Return**) and choose a destination folder. Completed rows show the actual saved filename. **Show Output** opens the chosen folder.

## Regression checks

```sh
bash scripts/test.sh
```

The runner compiles the production conversion code and view model with Swift 6 strict concurrency. It creates synthetic fixtures in a dedicated system temporary directory, tests all four output formats, image dimensions, transparency, EXIF orientation, duplicate imports, cancellation, mixed success/failure, temporary-file cleanup and concurrent filename collisions. It does not open the app, read personal images or access the network. Fixtures remain under the printed path for inspection. GitHub Actions runs this suite and a macOS Release build on pushes and pull requests.

## 中文说明

本工具在本地将图片转换为 JPEG、PNG、TIFF 或 HEIC，提供简体中文与英文界面。

**本次维护修复仅包含在当前源码中；现有 v1.0 Release 下载包没有这些修复。请构建当前源码使用新版本。**

- **保留原图**：输出遇到重名时自动编号；先完成临时文件编码，再以不覆盖已有文件的方式原子保存。可以安全地选择原图所在目录。
- **更清晰的操作**：支持文件选择器、拖放、单项移除、错误详情、访达定位，以及当前图片完成后停止。再次开始会重新转换整个列表并保存为新文件。
- **可靠的队列**：同一图片只添加一次，导入与转换不能同时修改列表；文件夹仅扫描直接包含的可见图片，不递归扫描子文件夹。
- **图像规则明确**：JPEG 透明区域使用白底，PNG/TIFF 保留透明度，输出像素应用 EXIF 方向。输出统一使用 8 位 sRGB；不适合无损归档高位深、HDR、广色域或 RAW 原始数据，也不保留多页 TIFF、图像序列、HEIC 辅助图或全部元数据。
- **保持应用沙盒**：只使用用户选中的文件和目录，不需要关闭 App Sandbox，无网络上传。

系统要求为 **macOS 13 及以上**，源码构建需要 **Xcode 26 及以上**。本次在 Apple Silicon、Xcode 27 / Swift 6.4 环境完成构建与回归检查；没有在所有旧版 macOS 上运行测试。RAW 相机格式与 HEIC 编码能否使用取决于系统和硬件，不支持的文件会显示失败原因。

使用上方命令克隆仓库，在 Xcode 打开项目并选择 `Image Converter` scheme；必要时选择自己的开发团队，**保留 App Sandbox**。添加图片，选择输出格式，点击“转换…”并选择输出目录。开发者可运行 `bash scripts/test.sh` 执行仅使用合成图片的回归检查。

## License

[MIT](LICENSE)
