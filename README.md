<p align="center">
  <img src="Sources/GridSnap/Resources/AppIcon.png" width="128" alt="GridSnap Icon">
</p>

<h1 align="center">GridSnap</h1>

<p align="center">
  <b>⚡ Lightweight macOS Window Manager & Screenshot Tool</b><br>
  <i>Grid layouts · Drag-to-snap · Hotkeys · Screen capture with annotation</i>
</p>

<p align="center">
  <a href="#installation">Install</a> ·
  <a href="#features">Features</a> ·
  <a href="#keyboard-shortcuts">Shortcuts</a> ·
  <a href="#中文说明">中文</a> ·
  <a href="LICENSE">License</a>
</p>

---

## Features

🪟 **Window Management**
- One-click grid layouts: 2×2, 2×3, 2×4, 1+2, 1+3, 2+3
- Auto-grid: automatically picks the best layout for your open windows
- Drag-to-snap: drag any window to screen edges/corners to snap into position
- Window swapping: drag one window onto another to swap positions
- Multi-display support

📸 **Screen Capture**
- Region screenshot with annotation tools (arrow, text, rectangle, mosaic)
- Screen recording
- All captures auto-copied to clipboard

⌨️ **Keyboard Driven**
- Global hotkeys for every layout and action
- Lives in your menu bar — zero dock clutter

## Installation

### Homebrew (Recommended)

```bash
brew tap chilamBJ/tap
brew install --cask gridsnap
```

### Manual Download

1. Download `GridSnap-x.x.x.dmg` from [Releases](https://github.com/chilamBJ/GridSnap/releases)
2. Open the DMG and drag **GridSnap** to **Applications**
3. Launch GridSnap — grant **Accessibility** permission when prompted

### Build from Source

```bash
git clone https://github.com/chilamBJ/GridSnap.git
cd GridSnap
bash build_app.sh
open GridSnap.app
```

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `⌃⌥1` | 2×2 Grid |
| `⌃⌥2` | 2×3 Grid |
| `⌃⌥3` | 2×4 Grid |
| `⌃⌥4` | 1+2 Layout |
| `⌃⌥5` | 1+3 Layout |
| `⌃⌥6` | 2+3 Layout |
| `⌃⌥G` | Auto Grid |
| `⌃⌥S` | Screenshot |
| `⌃⌥R` | Screen Recording |

> `⌃` = Control, `⌥` = Option

## Requirements

- macOS 13.0 (Ventura) or later
- Apple Silicon or Intel Mac

## Permissions

GridSnap requires the following permissions:

| Permission | Why |
|------------|-----|
| **Accessibility** | Move and resize windows |
| **Screen Recording** | Screenshot & recording features |

On first launch, GridSnap will guide you to enable these in **System Settings → Privacy & Security**.

## Tech Stack

- Swift 5.9 + SwiftUI
- Swift Package Manager
- AX (Accessibility) API for window management
- ScreenCaptureKit for screen capture
- CGEvent tap for drag-to-snap

## License

[MIT](LICENSE)

---

# 中文说明

## 功能

🪟 **窗口管理**
- 一键网格布局：2×2、2×3、2×4、1+2、1+3、2+3
- 自动网格：根据当前打开的窗口数量自动选择最佳布局
- 拖拽贴靠：将窗口拖到屏幕边缘/角落自动贴靠
- 窗口互换：将一个窗口拖到另一个窗口上方即可交换位置
- 多显示器支持

📸 **截屏录屏**
- 区域截屏，支持标注工具（箭头、文字、矩形、马赛克）
- 屏幕录制
- 截图自动复制到剪贴板

⌨️ **快捷键驱动**
- 所有布局和操作都有全局快捷键
- 菜单栏常驻，不占用 Dock 栏

## 安装方式

### Homebrew（推荐）

```bash
brew tap chilamBJ/tap
brew install --cask gridsnap
```

### 手动下载

1. 从 [Releases](https://github.com/chilamBJ/GridSnap/releases) 下载 `GridSnap-x.x.x.dmg`
2. 打开 DMG，将 **GridSnap** 拖入 **应用程序** 文件夹
3. 启动 GridSnap，按提示授予 **辅助功能** 权限

### 从源码构建

```bash
git clone https://github.com/chilamBJ/GridSnap.git
cd GridSnap
bash build_app.sh
open GridSnap.app
```

## 快捷键

| 快捷键 | 功能 |
|--------|------|
| `⌃⌥1` | 2×2 网格 |
| `⌃⌥2` | 2×3 网格 |
| `⌃⌥3` | 2×4 网格 |
| `⌃⌥4` | 1+2 布局 |
| `⌃⌥5` | 1+3 布局 |
| `⌃⌥6` | 2+3 布局 |
| `⌃⌥G` | 自动网格 |
| `⌃⌥S` | 截屏 |
| `⌃⌥R` | 录屏 |

## 系统要求

- macOS 13.0（Ventura）或更高版本
- Apple Silicon 或 Intel Mac

## 权限说明

| 权限 | 用途 |
|------|------|
| **辅助功能** | 移动和调整窗口大小 |
| **屏幕录制** | 截屏和录屏功能 |

首次启动时，GridSnap 会引导你在 **系统设置 → 隐私与安全性** 中开启相关权限。
