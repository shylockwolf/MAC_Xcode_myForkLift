# myForkLift

一个基于SwiftUI的双面板文件浏览器应用，专为macOS系统设计，提供高效的文件管理体验。

## 📊 项目概览

- **当前版本**: v1.4.8
- **开发平台**: macOS
- **开发语言**: Swift
- **UI框架**: SwiftUI
- **IDE**: Xcode

## 🏗️ 项目构建

### 系统要求

- macOS 13.0 (Ventura) 或更高版本
- Xcode 14.0 或更高版本
- Swift 5.8 或更高版本

### 构建步骤

1. **克隆项目**
   - 使用SSH协议：
     ```bash
     git clone git@github.com:shylockwolf/MAC_Xcode_myForkLift.git
     cd MAC_Xcode_myForkLift
     ```
   - 使用HTTPS协议：
     ```bash
     git clone https://github.com/shylockwolf/MAC_Xcode_myForkLift.git
     cd MAC_Xcode_myForkLift
     ```

2. **打开项目**
   ```bash
   open myForkLift.xcodeproj
   ```

3. **构建应用**
   - 选择目标设备：`My Mac`
   - 点击顶部工具栏的「运行」按钮（▶️）
   - 或使用快捷键：`Command + R`

4. **生成可执行文件**
   - 选择 `Product` → `Archive`
   - 在 Archives 窗口中选择最新版本，点击 `Distribute App`
   - 选择 `Development` 或 `Distribution` 进行导出

## 📦 项目结构

```
myForkLift/
├── Models/                # 数据模型
│   ├── FavoriteItem.swift     # 收藏夹项目
│   ├── ExternalDevice.swift   # 外部设备
│   ├── ContentViewModel.swift # 核心视图模型
│   ├── CopyProgress.swift     # 复制进度数据
│   ├── StatisticsInfo.swift   # 统计信息数据
│   └── ExternalDevice.swift   # 外部设备
├── Views/                 # 视图组件
│   ├── MainToolbarView.swift     # 主工具栏
│   ├── ContentView.swift         # 主内容视图
│   ├── ContentView+FileOperations.swift # 文件操作扩展
│   ├── ContentView+ExternalDevices.swift # 外部设备扩展
│   ├── FileBrowserPane.swift     # 文件浏览器面板
│   ├── SidebarView.swift         # 侧边栏
│   ├── ProgressWindow.swift      # 进度窗口
│   ├── CopyProgressView.swift    # 复制进度视图
│   ├── StatisticsWindow.swift    # 统计窗口
│   └── KeyboardShortcutHandler.swift # 键盘快捷键处理
├── Services/              # 服务层
│   ├── FileOperationService.swift   # 文件操作服务
│   └── ExternalDeviceService.swift  # 外部设备服务
├── myForkLiftApp.swift    # 应用入口
└── Assets.xcassets        # 资源文件
```

## 🧩 项目依赖

### 核心框架（Apple原生）

- **SwiftUI**: 用于构建现代、响应式的用户界面
- **Foundation**: 基础功能支持（文件操作、URL处理等）
- **AppKit**: macOS特定功能支持
- **UniformTypeIdentifiers**: 文件类型识别
- **Combine**: 响应式编程框架

### 第三方依赖

项目目前仅使用Apple原生框架，没有第三方依赖。

## 🎯 主要功能

### 📁 双面板文件浏览
- 左侧和右侧面板可同时浏览不同目录
- 支持多种视图模式
- 实时显示文件信息（类型、大小、修改日期）

### 📋 文件操作
- **复制/移动**: 支持跨面板文件复制和移动，带有实时进度显示
- **删除**: 安全的文件删除功能
- **重命名**: 支持文件和文件夹重命名
- **新建文件夹**: 快速创建新目录

### 📊 进度显示
- 实时显示文件操作进度
- 速度监控和剩余时间估算
- 确保进度条只前进不后退
- 支持多文件操作的累积进度显示
- 可取消的文件操作（带放弃按钮）

### 🔄 自动刷新
- **定时刷新**: 无任务时每2秒自动刷新目录
- **实时响应**: 确保其他应用生成的文件能及时显示
- **手动刷新**: 支持用户手动触发刷新

### 📱 外部设备支持
- 自动检测连接的外部存储设备
- 支持通过侧边栏快速访问外部设备

### ⭐ 收藏夹功能
- 支持将常用目录添加到收藏夹
- 收藏夹重排序功能
- 自动保存收藏夹配置

### 📈 统计功能
- 精确统计文件和文件夹数量
- 实时显示目录大小
- 与系统find命令结果完全一致
- 支持包含隐藏文件的完整统计

### ⌨️ 键盘快捷键
- **复制**: `Command + C`
- **粘贴**: `Command + V`
- **删除**: `Delete`
- **全选**: `Command + A`
- **统计**: 工具栏统计按钮
- **返回上一目录**: 工具栏按钮

### 🎨 界面定制
- 可配置显示/隐藏文件类型、大小和修改日期
- 支持显示隐藏文件
- 双面板独立配置

## 📜 版本历史

### v1.4.8 (最新)
- 更新版本号
- 完善了复制粘贴功能
- 修复了粘贴操作在源文件夹和目标文件夹各复制一份的问题
- 确保粘贴目标为当前激活的文件夹
- 改进了.app文件显示，类型显示为"MAC APP"

### v1.2.1
- 添加了完整的文件和文件夹统计功能
- 修复了复制操作中的取消按钮显示问题
- 统计结果与系统find命令完全一致
- 优化了统计窗口界面，显示文件数、文件夹数和总大小
- 添加了可取消的文件操作支持

### v1.2
- 修复了多个文件复制移动时进度条显示问题
- 添加了无任务时的定时刷新功能（每2秒）
- 优化了进度条显示，确保只前进不后退
- 改进了多文件操作的累积进度计算

### v1.1
- 修复了大文件复制移动时进度条回缩问题
- 添加了文件操作的实时速度显示
- 优化了目录刷新机制

### v1.0
- 初始版本发布
- 双面板文件浏览功能
- 基本文件操作支持
- 收藏夹功能

## 📖 Git历史记录

```
3cfa66b 9th --- command-a -c -v added       # 添加了Command+A全选功能
f3b5e67 8th --- icons updated               # 更新了界面图标
97ab143 7th --- 目录返回功能添加            # 添加了返回上一目录功能
a92694a 6th --- sort function added         # 添加了文件排序功能
b6e1258 5th --- active windows optimized    # 优化了活动窗口显示
6022a10 4th --- active file panel display optimized # 优化了文件面板显示
1e2c364 3rd --- rename and select all bottons added # 添加了重命名和全选按钮
3db293c 2nd --- file path optimized         # 优化了文件路径处理
336a92e 1st --- base version                # 初始版本
```

## 🛠️ 开发规范

### 代码风格
- 使用Swift官方推荐的代码风格
- 类名使用大驼峰命名法（PascalCase）
- 方法和变量使用小驼峰命名法（camelCase）
- 常量使用全大写加下划线（UPPER_CASE_WITH_UNDERSCORES）

### 架构模式
- 采用MVVM（Model-View-ViewModel）架构模式
- 清晰的分层结构：Models、Views、Services
- 视图与业务逻辑分离

### 注释规范
- 使用Markdown格式的文档注释
- 复杂逻辑添加详细注释
- 关键功能添加使用说明

## 🤝 贡献指南

1. **Fork项目**
2. **创建功能分支** (`git checkout -b feature/AmazingFeature`)
3. **提交更改** (`git commit -m 'Add some AmazingFeature'`)
4. **推送到分支** (`git push origin feature/AmazingFeature`)
5. **创建Pull Request**

## 📄 许可证

本项目采用MIT许可证，详情请参阅LICENSE文件。

## 📞 联系方式

- **项目作者**: shylockwolf
- **GitHub**: [shylockwolf](https://github.com/shylockwolf)
- **Email**: shylockwolf@yahoo.com

---

**© 2025 myForkLift. All rights reserved.**
