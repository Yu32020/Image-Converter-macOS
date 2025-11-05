# Image-Converter-macOS
A beautiful, high-performance macOS utility for converting various image formats (including RAW/NEF/TIFF) . 高性能、高颜值的 macOS 图像格式转换工具。

# Image Converter for macOS

A high-performance macOS utility designed for converting various image formats, including professional RAW types (NEF, CR2/3, DNG, TIFF), into universally compatible formats like JPEG, PNG, HEIC, and TIFF. Built with SwiftUI, it features a modern "Liquid Glass" (Vibrancy) aesthetic and is optimized for processing hundreds of images without excessive memory usage.


---

## ✨ Features

*   **Broad Format Support**: Input support for NEF, CR2, CR3, RAW, DNG, TIFF, JPG, PNG, HEIC, ARW, ORF, and more.
*   **Versatile Output**: Convert to JPEG (High Quality), PNG (Lossless), TIFF (Professional), or HEIC (Efficient).
*   **Optimized Performance**:
    *   Utilizes Apple's Core Image framework with GPU acceleration.
    *   Processes images sequentially in the background to maintain low memory footprint.
    *   Employs `autoreleasepool` to immediately free memory after each conversion.
    *   Efficient thumbnail generation avoids loading full RAW files into memory.
*   **Drag & Drop Interface**: Easily add individual files or entire folders.
*   **Multi-language Support**: Includes English and Simplified Chinese, with an in-app language switcher.

## 🖥️ Requirements

*   macOS 11.0 (Big Sur) or later.

## 🚀 Installation & Usage

1.  **Download the App**:
    *   Go to the [Releases](https://github.com/Yu32020/Image-Converter-macOS/releases) section of this repository.
    *   Download the latest `Image Converter.zip` file.
    *   Unzip the file and move `Image Converter.app` to your Applications folder.

2.  **Usage**:
    *   Launch the application.
    *   Drag your images or folders into the main window.
    *   Select your desired Output Format and Language.
    *   Click "Start Conversion" and choose a destination folder.

## 🛠️ Building from Source

This project is built using Swift and SwiftUI. To build from source:

1.  Clone the repository:
    ```bash
    git clone [https://github.com/Yu32020/Image-Converter-macOS.git](https://github.com/Yu32020/Image-Converter-macOS.git)
    ```
2.  Open the project in the latest version of Xcode.
3.  Build and Run the `Image Converter` scheme.
    *   *Note: For successful file writing during development, ensure the App Sandbox is disabled in the project's "Signing & Capabilities" settings.*

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---
---

# 中文说明

# macOS 图像转换器 (Image Converter)

一款高性能的 macOS 实用工具，专为转换各种图像格式而设计，包括专业的 RAW 类型（如 NEF, CR2/3, DNG, TIFF），并可输出为通用格式（如 JPEG, PNG, HEIC 和 TIFF）。该应用使用 SwiftUI 构建，并针对处理数百张图像进行了优化，不会过度占用内存。


---

## ✨ 功能特性

*   **广泛的格式支持**：支持输入 NEF, CR2, CR3, RAW, DNG, TIFF, JPG, PNG, HEIC, ARW, ORF 等格式。
*   **多样的输出选项**：可转换为 JPEG (高质量)、PNG (无损)、TIFF (专业) 或 HEIC (高效)。
*   **极致的性能优化**：
    *   利用 Apple 的 Core Image 框架进行 GPU 加速处理。
    *   在后台按顺序处理图像，保持低内存占用。
    *   使用 `autoreleasepool` 在每次转换后立即释放内存。
    *   高效的缩略图生成机制，避免将完整的 RAW 文件加载到内存中。
*   **拖放界面**：轻松添加单个文件或整个文件夹。
*   **多语言支持**：包含英文和简体中文，并提供应用内语言切换器。

## 🖥️ 系统要求

*   macOS 11.0 (Big Sur) 或更高版本。

## 🚀 安装与使用

1.  **下载应用**：
    *   前往本仓库的 [Releases](https://github.com/Yu32020/Image-Converter-macOS/releases) 页面。
    *   下载最新的 `Image Converter.zip` 文件。
    *   解压文件，并将 `Image Converter.app` 移动到您的“应用程序”文件夹。

2.  **使用方法**：
    *   启动应用程序。
    *   将您的图像或文件夹拖放到主窗口中。
    *   选择您想要的输出格式和语言。
    *   点击“开始转换”并选择一个目标文件夹。

## 🛠️ 从源码构建

本项目使用 Swift 和 SwiftUI 构建。从源码构建：

1.  克隆仓库：
    ```bash
    git clone [https://github.com/Yu32020/Image-Converter-macOS.git](https://github.com/Yu32020/Image-Converter-macOS.git)
    ```
2.  在最新版本的 Xcode 中打开项目。
3.  构建并运行 `Image Converter` scheme。
    *   *注意：为了在开发过程中成功写入文件，请确保在项目的 "Signing & Capabilities" 设置中禁用了 App Sandbox（应用沙盒）。*

## 📜 许可证

本项目采用 MIT 许可证授权 - 详情请参阅 [LICENSE](LICENSE) 文件。
