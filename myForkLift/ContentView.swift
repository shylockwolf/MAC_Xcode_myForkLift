//
//  ContentView.swift
//  DWBrowser
//
//  Created by Your Name on 2025/1/17.
//

import SwiftUI
import Foundation
import AppKit
import Combine
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var viewModel: ContentViewModel
    
    @State var leftPaneURL: URL
    @State var rightPaneURL: URL
    
    // 文件信息显示选项 - 提升到ContentView级别以便保存
    @State var leftShowFileType = true
    @State var leftShowFileSize = true
    @State var leftShowFileDate = true
    @State var rightShowFileType = true
    @State var rightShowFileSize = true
    @State var rightShowFileDate = true
    
    // 初始化方法
    init() {
        // 设置默认路径
        let homeURL = FileManager.default.homeDirectoryForCurrentUser
        let downloadsURL = homeURL.appendingPathComponent("Downloads")
        _leftPaneURL = State(initialValue: homeURL)
        _rightPaneURL = State(initialValue: downloadsURL)
    }
    
    // 进度窗口相关状态
    @State var isProgressWindowPresented: Bool = false
    @State var progressInfo: ProgressInfo = ProgressInfo(
        title: "操作进行中"
    )
    // 复制进度相关
    @State var copyProgress: CopyProgress?
    @State var showCopyProgress = false
    @State var isCopyOperationCancelled: Bool = false
    @State var isRefreshing = false
    @State var refreshingText = "刷新中…"
    @State var maxProgress: Double = 0.0 // 用于确保进度条只前进不后退
    
    // 统计相关状态
    @State var isStatisticsWindowPresented: Bool = false
    @State var statisticsInfo: StatisticsInfo = StatisticsInfo(
        totalFiles: 0,
        totalFolders: 0,
        totalSize: 0,
        currentFile: "",
        progress: 0.0
    )
    @State var isStatisticsCancelled: Bool = false
    
    // 定时刷新相关
    @State var timerCancellable: Cancellable? = nil
    @State var shouldRefreshTimerRun: Bool = false
    
    // 外部设备列表
    @State var externalDevices: [ExternalDevice] = []
    
    // 收藏夹列表
    @State var favorites: [FavoriteItem] = [
        FavoriteItem(name: "Home", url: FileManager.default.homeDirectoryForCurrentUser, icon: "house"),
        FavoriteItem(name: "Documents", url: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents"), icon: "folder.fill")
    ]
    
    @State var window: NSWindow? // 窗口引用用于保存位置和大小
    

    // 保存收藏夹到UserDefaults
    private func saveFavorites() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(favorites.filter {
                // 不保存默认的系统收藏夹（Home和Documents）
                $0.name != "Home" && $0.name != "Documents"
            })
            UserDefaults.standard.set(data, forKey: viewModel.favoritesKey)
        } catch {
        }
    }
    
    // 从UserDefaults加载收藏夹
    private func loadFavorites() {
        guard let data = UserDefaults.standard.data(forKey: viewModel.favoritesKey) else {
            return
        }
        
        do {
            let decoder = JSONDecoder()
            let savedFavorites = try decoder.decode([FavoriteItem].self, from: data)
            
            // 合并默认收藏夹和保存的收藏夹
            let defaultFavorites = favorites.filter { 
                $0.name == "Home" || $0.name == "Documents" 
            }
            
            favorites = defaultFavorites + savedFavorites.filter { fav in
                // 检查目录是否仍然存在
                FileManager.default.fileExists(atPath: fav.url.path)
            }
            
        } catch {
        }
    }
    

    
    // 获取当前窗口引用
    private func getWindow() {
        // 使用NSApplication.shared.windows获取当前窗口
        if let currentWindow = NSApplication.shared.windows.first(where: { $0.contentView?.window == $0 }) {
            self.window = currentWindow
            
            // 设置窗口委托，在窗口关闭时保存位置和大小
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: currentWindow,
                queue: .main
            ) { _ in
                if let window = self.window {
                    viewModel.saveWindowFrame(window.frame)
                }
                viewModel.saveFileDisplayOptions(
                    leftShowFileSize: leftShowFileSize,
                    leftShowFileDate: leftShowFileDate,
                    leftShowFileType: leftShowFileType,
                    rightShowFileSize: rightShowFileSize,
                    rightShowFileDate: rightShowFileDate,
                    rightShowFileType: rightShowFileType
                )
            }
            
            // 在窗口移动或调整大小时保存
            NotificationCenter.default.addObserver(
                forName: NSWindow.didMoveNotification,
                object: currentWindow,
                queue: .main
            ) { _ in
                if let window = self.window {
                    viewModel.saveWindowFrame(window.frame)
                }
            }
            
            NotificationCenter.default.addObserver(
                forName: NSWindow.didResizeNotification,
                object: currentWindow,
                queue: .main
            ) { _ in
                if let window = self.window {
                    viewModel.saveWindowFrame(window.frame)
                }
            }
        }
    }
    

    
    // 处理收藏夹重新排序
    private func handleFavoriteReorder(providers: [NSItemProvider], targetFavorite: FavoriteItem) -> Bool {
        
        for provider in providers {
            if provider.canLoadObject(ofClass: NSString.self) {
                provider.loadObject(ofClass: NSString.self) { object, error in
                    if let error = error {
                        return
                    }
                    
                    if let sourceName = object as? String {
                        DispatchQueue.main.async {
                            self.reorderFavorites(sourceName: sourceName, targetFavorite: targetFavorite)
                        }
                    }
                }
            }
        }
        return true
    }
    
    // 重新排序收藏夹
    private func reorderFavorites(sourceName: String, targetFavorite: FavoriteItem) {
        
        guard let sourceIndex = favorites.firstIndex(where: { $0.name == sourceName }) else {
            return
        }
        
        guard let targetIndex = favorites.firstIndex(where: { $0.id == targetFavorite.id }) else {
            return
        }
        
        let sourceFavorite = favorites[sourceIndex]
        
        // 如果是同一个项目，不进行排序
        if sourceIndex == targetIndex {
            return
        }
        
        // 创建新的数组顺序
        var newFavorites = favorites
        newFavorites.remove(at: sourceIndex)
        
        // 计算新的插入位置
        let newTargetIndex = newFavorites.firstIndex(where: { $0.id == targetFavorite.id }) ?? targetIndex
        if sourceIndex < targetIndex {
            newFavorites.insert(sourceFavorite, at: newTargetIndex + 1)
        } else {
            newFavorites.insert(sourceFavorite, at: newTargetIndex)
        }
        
        withAnimation(.easeInOut(duration: 0.3)) {
            favorites = newFavorites
        }
        
        // 保存新的顺序
        saveFavorites()
        
    }
    
    // 处理拖拽drop
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        
        for provider in providers {
            
            // 尝试多种方式获取URL
            if provider.canLoadObject(ofClass: URL.self) {
                provider.loadObject(ofClass: URL.self) { (object, error) in
                    if let error = error {
                        return
                    }
                    
                    if let url = object as? URL {
                        DispatchQueue.main.async {
                            self.processDroppedURL(url)
                        }
                    }
                }
            } else if provider.canLoadObject(ofClass: NSString.self) {
                provider.loadObject(ofClass: NSString.self) { object, error in
                    if let path = object as? String {
                        let url = URL(fileURLWithPath: path)
                        DispatchQueue.main.async {
                            self.processDroppedURL(url)
                        }
                    }
                }
            }
        }
        return true
    }
    
    // 处理拖拽的URL
    private func processDroppedURL(_ url: URL) {
        
        // 检查是否是目录
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return
        }
        
        guard isDirectory.boolValue else {
            return
        }
        
        // 检查是否已经在收藏夹中
        if favorites.contains(where: { $0.url.path == url.path }) {
            return
        }
        
        // 添加到收藏夹
        let newFavorite = FavoriteItem(
            name: url.lastPathComponent,
            url: url,
            icon: "folder.fill"
        )
        
        withAnimation(.easeInOut(duration: 0.3)) {
            favorites.append(newFavorite)
        }
        
        // 自动保存收藏夹
        saveFavorites()
        
    }
    
    var body: some View {
        mainContentView
            .onAppear {
                setupAppearance()
                // 初始化历史记录
                viewModel.initializeHistory(leftURL: leftPaneURL, rightURL: rightPaneURL)
                // 加载打开的文件列表
                viewModel.loadOpenedFiles()
                // 设置定时刷新
                setupTimer()
            }
            .onDisappear {
                // 取消定时器
                cancelTimer()
                // 保存打开的文件列表
                viewModel.saveOpenedFiles()
            }
            // 监听openedFiles变化，自动保存
            .onReceive(viewModel.$openedFiles) {
                _ in
                viewModel.saveOpenedFiles()
            }
            .withProgressWindow(
                isPresented: $isProgressWindowPresented,
                progressInfo: $progressInfo,
                onCancel: { 
                    // 这里可以添加取消操作的具体逻辑
                }
            )
            .withStatisticsWindow(
                isPresented: $isStatisticsWindowPresented,
                statisticsInfo: $statisticsInfo,
                onOK: { 
                    isStatisticsWindowPresented = false
                },
                onCancel: { 
                    isStatisticsCancelled = true
                }
            )
            .overlay(
                // 复制进度窗口
                copyProgressOverlay,
                alignment: .center
            )
            .overlay(
                refreshingOverlay,
                alignment: .center
            )
    }
    
    // 定时刷新相关方法
    private func setupTimer() {
        // 如果已经有定时器，先取消
        timerCancellable?.cancel()
        
        // 设置2秒定时器
        timerCancellable = Timer.publish(every: 2.0, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                // 只有在无任务时才刷新
                if !self.showCopyProgress && !self.isRefreshing {
                    self.viewModel.triggerRefresh()
                }
            }
    }
    
    private func cancelTimer() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }
    
    // 主内容视图
    private var mainContentView: some View {
        VStack(spacing: 0) {
            mainToolbarView
            Divider()
            mainBrowserView
        }
        .frame(minWidth: 800, maxWidth: .infinity, minHeight: 600, maxHeight: .infinity)
        .clipped() // 确保内容不会超出容器边界
        .frame(maxWidth: .infinity, alignment: .leading) // 确保内容左对齐，防止向左偏移
        .overlay(
            // 添加键盘快捷键处理器
            KeyboardShortcutHandler(
                onSelectAll: { handleSelectAll() },
                onCopy: { copyItem() },
                onPaste: { pasteItem() }
            )
            .allowsHitTesting(false) // 允许鼠标事件穿透，不影响底层视图点击
        )
        .onChange(of: leftPaneURL) { newURL in
            // 添加到历史记录
            viewModel.addToHistory(url: newURL, for: .left)
            handleURLChange(newURL, pane: .left)
        }
        .onChange(of: rightPaneURL) { newURL in
            // 添加到历史记录
            viewModel.addToHistory(url: newURL, for: .right)
            handleURLChange(newURL, pane: .right)
        }
        .onChange(of: leftShowFileSize) { _ in saveFileDisplayOptions() }
        .onChange(of: leftShowFileDate) { _ in saveFileDisplayOptions() }
        .onChange(of: leftShowFileType) { _ in saveFileDisplayOptions() }
        .onChange(of: rightShowFileSize) { _ in saveFileDisplayOptions() }
        .onChange(of: rightShowFileDate) { _ in saveFileDisplayOptions() }
        .onChange(of: rightShowFileType) { _ in saveFileDisplayOptions() }
        // 监听任务状态变化，动态调整定时器
        .onChange(of: showCopyProgress) { _ in
            // 任务状态变化时不需要重新设置定时器，定时器内部会判断是否需要刷新
        }
        .onChange(of: isRefreshing) { _ in
            // 任务状态变化时不需要重新设置定时器，定时器内部会判断是否需要刷新
        }
    }
    
    // 工具栏视图
    private var mainToolbarView: some View {
        MainToolbarView(
            activePane: viewModel.activePane,
            selectedCount: viewModel.getCurrentSelectedItems().count,
            isShowingHiddenFiles: viewModel.activePane == .left ? viewModel.leftShowHiddenFiles : viewModel.rightShowHiddenFiles,
            canGoBack: viewModel.canGoBack(for: viewModel.activePane),
            onExit: {
                NSApplication.shared.terminate(nil)
            },
            onSelectPane: { pane in
                viewModel.setActivePane(pane)
            },
            onGoBack: {
                // 实现返回上一个目录功能
                if let previousURL = viewModel.goBackInHistory(for: viewModel.activePane) {
                    if viewModel.activePane == .left {
                        leftPaneURL = previousURL
                    } else {
                        rightPaneURL = previousURL
                    }
                }
            },
            onCopy: {
                copyToAnotherPane()
            },
            onDelete: {
                deleteItem()
            },
            onMove: {
                moveItem()
            },
            onClearSelection: {
                viewModel.clearAllSelections()
            },
            onNewFolder: {
                createNewFolder()
            },
            onStatistics: {
                startStatistics()
            },
            onRename: {
                renameItem()
            },
            onSelectAll: {
                // 实现全部选中/取消选中功能
                let isLeftActive = viewModel.activePane == .left
                let currentURL = isLeftActive ? leftPaneURL : rightPaneURL
                
                do {
                    let options: FileManager.DirectoryEnumerationOptions = (isLeftActive ? viewModel.leftShowHiddenFiles : viewModel.rightShowHiddenFiles) ? [] : [.skipsHiddenFiles]
                    let contents = try FileManager.default.contentsOfDirectory(at: currentURL, includingPropertiesForKeys: [.isDirectoryKey], options: options)
                    let filteredContents = (isLeftActive ? viewModel.leftShowHiddenFiles : viewModel.rightShowHiddenFiles) ? contents : contents.filter { !$0.lastPathComponent.hasPrefix(".") }
                    
                    let allFilesCount = filteredContents.count
                    let currentSelectedCount = isLeftActive ? viewModel.leftSelectedItems.count : viewModel.rightSelectedItems.count
                    
                    if currentSelectedCount == allFilesCount {
                        // 已经全部选中，取消全部选中
                        if isLeftActive {
                            viewModel.leftSelectedItems.removeAll()
                        } else {
                            viewModel.rightSelectedItems.removeAll()
                        }
                    } else {
                        // 没有全部选中，选中所有文件
                        if isLeftActive {
                            viewModel.leftSelectedItems = Set(filteredContents)
                        } else {
                            viewModel.rightSelectedItems = Set(filteredContents)
                        }
                    }
                } catch {
                }
            },
            onToggleHiddenFiles: {
                if viewModel.activePane == .left {
                    viewModel.leftShowHiddenFiles.toggle()
                } else {
                    viewModel.rightShowHiddenFiles.toggle()
                }
            }
        )
    }
    
    // 主浏览器视图
    private var mainBrowserView: some View {
        HStack(spacing: 0) {
            sidebarView
                .frame(width: 210) // 强制固定宽度
                .frame(maxHeight: .infinity) // 填满高度
                .clipped() // 确保侧边栏不会被覆盖
                .layoutPriority(1) // 提高布局优先级，确保不被压缩
            Divider()
                .frame(width: 1) // 固定分隔线宽度
            filePanesView
        }
        .frame(minWidth: 850, maxWidth: .infinity, minHeight: 560, maxHeight: .infinity)
        .clipped() // 确保整个浏览器视图不会溢出
        .frame(maxWidth: .infinity, alignment: .leading) // 确保整个浏览器视图左对齐
    }
    
    // 侧边栏视图
    private var sidebarView: some View {
        SidebarView(
            activePane: $viewModel.activePane,
            leftPaneURL: $leftPaneURL,
            rightPaneURL: $rightPaneURL,
            externalDevices: $externalDevices,
            favorites: $favorites,
            openedFiles: $viewModel.openedFiles,
            onEjectDevice: { device in
                ejectDevice(device: device)
            },
            onEjectAllDevices: {
                ejectAllDevices()
            },
            onFavoriteRemoved: { favorite in
                withAnimation(.easeInOut(duration: 0.2)) {
                    favorites.removeAll { $0.id == favorite.id }
                    saveFavorites()
                }
            },
            onFavoriteReorder: { providers, targetFavorite in
                handleFavoriteReorder(providers: providers, targetFavorite: targetFavorite)
            },
            onDropToFavorites: { providers in
                handleDrop(providers: providers)
            },
            onOpenedFileRemoved: { url in
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.openedFiles.removeAll { $0 == url }
                }
            }
        )
    }
    
    // 文件面板视图
    private var filePanesView: some View {
        HStack(spacing: 0) {
            leftFilePane
                .layoutPriority(0) // 较低的布局优先级，允许被压缩
            Divider()
                .frame(width: 1)
            rightFilePane
                .layoutPriority(0) // 较低的布局优先级，允许被压缩
        }
        .frame(minWidth: 600)
        .layoutPriority(0) // 文件面板区域整体使用低优先级
    }
    
    // 左侧文件面板
    private var leftFilePane: some View {
        ZStack {
            FileBrowserPane(
                currentURL: $leftPaneURL, 
                showHiddenFiles: $viewModel.leftShowHiddenFiles,
                selectedItems: $viewModel.leftSelectedItems,
                isActive: viewModel.activePane == .left,
                onActivate: { 
                    viewModel.setActivePane(.left)
                },
                refreshTrigger: viewModel.refreshTrigger,
                panelId: "left",
                selectionState: viewModel.leftSelectionState,
                showFileSize: $leftShowFileSize,
                showFileDate: $leftShowFileDate,
                showFileType: $leftShowFileType
            )
        }
        .frame(minWidth: 300)
        .frame(maxWidth: .infinity)
        .clipped() // 确保内容不会超出边界
    }
    
    // 右侧文件面板
    private var rightFilePane: some View {
        ZStack {
            FileBrowserPane(
                currentURL: $rightPaneURL, 
                showHiddenFiles: $viewModel.rightShowHiddenFiles,
                selectedItems: $viewModel.rightSelectedItems,
                isActive: viewModel.activePane == .right,
                onActivate: { 
                    viewModel.setActivePane(.right)
                },
                refreshTrigger: viewModel.refreshTrigger,
                panelId: "right",
                selectionState: viewModel.rightSelectionState,
                showFileSize: $rightShowFileSize,
                showFileDate: $rightShowFileDate,
                showFileType: $rightShowFileType
            )
        }
        .frame(minWidth: 300)
        .frame(maxWidth: .infinity)
        .clipped() // 确保内容不会超出边界
    }
    
    // 复制进度叠加层
    private var copyProgressOverlay: some View {
        Group {
            if showCopyProgress, let progress = copyProgress {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        CopyProgressView(progress: progress) {
                            // 取消回调
                            self.cancelCopyOperation()
                        }
                        .transition(.opacity.combined(with: .scale))
                        Spacer()
                    }
                    .padding(.bottom, 50)
                    Spacer()
                }
                .animation(.easeInOut, value: showCopyProgress)
            }
        }
    }

    private var refreshingOverlay: some View {
        Group {
            if isRefreshing {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        VStack(spacing: 12) {
                            ProgressView()
                            Text(refreshingText)
                                .font(.headline)
                        }
                        .padding(16)
                        .background(Color.black.opacity(0.6))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        Spacer()
                    }
                    .padding(.bottom, 50)
                    Spacer()
                }
                .transition(.opacity)
                .animation(.easeInOut, value: isRefreshing)
            }
        }
    }
    
    // 设置外观
    private func setupAppearance() {
        
        // 获取窗口引用
        getWindow()
        
        loadFavorites()
        
        // 初始化设备检测
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.detectExternalDevices()
            self.setupDeviceMonitoring()
        }
        
        // 延迟加载路径和窗口状态，确保状态已初始化
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            loadInitialPaths()
        }
    }
    
    // 加载初始路径
    private func loadInitialPaths() {
        
        let defaults = viewModel.loadWindowPaths(
            defaultLeft: leftPaneURL,
            defaultRight: rightPaneURL
        )
        
        leftPaneURL = defaults.left
        rightPaneURL = defaults.right
        
        
        // 验证UserDefaults中的值
        if let savedLeft = UserDefaults.standard.string(forKey: viewModel.leftPaneURLKey),
           let savedRight = UserDefaults.standard.string(forKey: viewModel.rightPaneURLKey) {
        } else {
        }
        
        // 加载窗口位置和大小
        if let window = self.window {
            viewModel.restoreWindowFrame(for: window)
        }
        
        // 加载文件信息显示选项
        viewModel.loadFileDisplayOptions(
            leftShowFileSize: &leftShowFileSize,
            leftShowFileDate: &leftShowFileDate,
            leftShowFileType: &leftShowFileType,
            rightShowFileSize: &rightShowFileSize,
            rightShowFileDate: &rightShowFileDate,
            rightShowFileType: &rightShowFileType
        )
    }
    
    // 处理URL变化
    private func handleURLChange(_ newURL: URL, pane: Pane) {
        viewModel.saveWindowPaths(leftPaneURL: leftPaneURL, rightPaneURL: rightPaneURL)
    }
    
    // 保存文件显示选项
    private func saveFileDisplayOptions() {
        viewModel.saveFileDisplayOptions(
            leftShowFileSize: leftShowFileSize,
            leftShowFileDate: leftShowFileDate,
            leftShowFileType: leftShowFileType,
            rightShowFileSize: rightShowFileSize,
            rightShowFileDate: rightShowFileDate,
            rightShowFileType: rightShowFileType
        )
    }
    
    // 开始统计选中的文件/目录
    private func startStatistics() {
        // 获取当前选中的项目
        let selectedItems = viewModel.getCurrentSelectedItems()
        
        // 统计功能强制包含所有文件（包括隐藏文件），以与Finder行为一致
        let showHiddenFiles = true
        
        if selectedItems.isEmpty {
            // 如果没有选中项目，使用当前目录
            let currentURL = viewModel.activePane == .left ? leftPaneURL : rightPaneURL
            let itemsToScan: [URL] = [currentURL]
            performStatistics(on: itemsToScan, showHiddenFiles: showHiddenFiles)
        } else {
            // 统计选中的项目
            performStatistics(on: Array(selectedItems), showHiddenFiles: showHiddenFiles)
        }
    }
    
    // 执行统计操作
    private func performStatistics(on items: [URL], showHiddenFiles: Bool) {
        // 重置统计状态
        isStatisticsCancelled = false
        statisticsInfo = StatisticsInfo(
            totalFiles: 0,
            totalFolders: 0,
            totalSize: 0,
            currentFile: "",
            progress: 0.0
        )
        
        // 显示统计窗口
        isStatisticsWindowPresented = true
        
        // 在后台线程执行统计
        DispatchQueue.global(qos: .utility).async {
            // 先计算总共有多少文件需要统计（用于进度计算）
            var totalFilesToScan: Int64 = 0
            var totalFoldersToScan: Int64 = 0
            var isCancelled = false
            
            // 第一遍：计算总文件数和文件夹数
            for item in items {
                if self.isStatisticsCancelled {
                    isCancelled = true
                    break
                }
                let result = self.countFilesAndFolders(in: item, isCancelled: &self.isStatisticsCancelled, showHiddenFiles: showHiddenFiles)
                totalFilesToScan += result.files
                totalFoldersToScan += result.folders
            }
            
            // 更新文件夹总数
            DispatchQueue.main.async {
                self.statisticsInfo.totalFolders = totalFoldersToScan
            }
            
            if isCancelled {
                return
            }
            
            // 第二遍：实际统计文件大小
            var scannedFiles: Int64 = 0
            var totalSize: Int64 = 0
            
            for item in items {
                if self.isStatisticsCancelled {
                    isCancelled = true
                    break
                }
                
                self.scanDirectory(
                    at: item,
                    totalFilesToScan: totalFilesToScan,
                    scannedFiles: &scannedFiles,
                    totalSize: &totalSize,
                    isCancelled: &self.isStatisticsCancelled,
                    showHiddenFiles: showHiddenFiles
                )
            }
            
            if !isCancelled {
                // 统计完成
                DispatchQueue.main.async {
                    self.statisticsInfo.isCompleted = true
                }
            }
        }
    }
    
    // 计算目录中的文件和文件夹数量（递归）
    private func countFilesAndFolders(in url: URL, isCancelled: inout Bool, showHiddenFiles: Bool) -> (files: Int64, folders: Int64) {
        if isCancelled {
            return (0, 0)
        }
        
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return (0, 0)
        }
        
        // 如果是文件，返回1个文件，0个文件夹
        if !isDirectory.boolValue {
            return (1, 0)
        }
        
        // 如果是目录，检查是否应该跳过
        if shouldSkipDirectory(url) {
            return (0, 0)
        }
        
        var files: Int64 = 0
        var folders: Int64 = 1 // 当前目录也算1个文件夹
        
        do {
            let options: FileManager.DirectoryEnumerationOptions = showHiddenFiles ? [] : [.skipsHiddenFiles]
            let contents = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: options)
            
            for item in contents {
                if isCancelled {
                    return (0, 0)
                }
                let result = countFilesAndFolders(in: item, isCancelled: &isCancelled, showHiddenFiles: showHiddenFiles)
                files += result.files
                folders += result.folders
            }
        } catch {
        }
        
        return (files, folders)
    }
    
    // 判断是否应该跳过某个目录的统计
    private func shouldSkipDirectory(_ url: URL) -> Bool {
        // 不跳过任何目录，让统计与Finder完全一致
        return false
    }
    
    // 扫描目录并统计文件大小（递归）
    private func scanDirectory(
        at url: URL,
        totalFilesToScan: Int64,
        scannedFiles: inout Int64,
        totalSize: inout Int64,
        isCancelled: inout Bool,
        showHiddenFiles: Bool
    ) {
        if isCancelled {
            return
        }
        
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return
        }
        
        if !isDirectory.boolValue {
            // 是文件
            do {
                let fileAttributes = try FileManager.default.attributesOfItem(atPath: url.path)
                if let size = fileAttributes[.size] as? Int64 {
                    totalSize += size
                }
                
                // 更新统计信息
                scannedFiles += 1
                let progress = Double(scannedFiles) / Double(totalFilesToScan)
                
                // 复制值以避免闭包捕获inout参数
                let currentScannedFiles = scannedFiles
                let currentTotalSize = totalSize
                let currentFileName = url.lastPathComponent
                
                DispatchQueue.main.async {
                    self.statisticsInfo.totalFiles = currentScannedFiles
                    self.statisticsInfo.totalSize = currentTotalSize
                    self.statisticsInfo.currentFile = currentFileName
                    self.statisticsInfo.progress = progress
                }
            } catch {
            }
            return
        }
        
        // 是目录，检查是否应该跳过
        if shouldSkipDirectory(url) {
            return
        }
        
        // 是目录，递归扫描
        do {
            // 更新当前处理的目录
            DispatchQueue.main.async {
                self.statisticsInfo.currentFile = url.lastPathComponent
            }
            
            let options: FileManager.DirectoryEnumerationOptions = showHiddenFiles ? [] : [.skipsHiddenFiles]
            let contents = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: options)
            
            for item in contents {
                if isCancelled {
                    return
                }
                
                scanDirectory(
                    at: item,
                    totalFilesToScan: totalFilesToScan,
                    scannedFiles: &scannedFiles,
                    totalSize: &totalSize,
                    isCancelled: &isCancelled,
                    showHiddenFiles: showHiddenFiles
                )
            }
        } catch {
        }
    }
    
    // 处理全部选中功能（Command-A快捷键）
    private func handleSelectAll() {
        let isLeftActive = viewModel.activePane == .left
        let currentURL = isLeftActive ? leftPaneURL : rightPaneURL
        
        do {
            let options: FileManager.DirectoryEnumerationOptions = (isLeftActive ? viewModel.leftShowHiddenFiles : viewModel.rightShowHiddenFiles) ? [] : [.skipsHiddenFiles]
            let contents = try FileManager.default.contentsOfDirectory(at: currentURL, includingPropertiesForKeys: [.isDirectoryKey], options: options)
            let filteredContents = (isLeftActive ? viewModel.leftShowHiddenFiles : viewModel.rightShowHiddenFiles) ? contents : contents.filter { !$0.lastPathComponent.hasPrefix(".") }
            
            let allFilesCount = filteredContents.count
            let currentSelectedCount = isLeftActive ? viewModel.leftSelectedItems.count : viewModel.rightSelectedItems.count
            
            if currentSelectedCount == allFilesCount {
                // 已经全部选中，取消全部选中
                if isLeftActive {
                    viewModel.leftSelectedItems.removeAll()
                } else {
                    viewModel.rightSelectedItems.removeAll()
                }
            } else {
                // 没有全部选中，选中所有文件
                if isLeftActive {
                    viewModel.leftSelectedItems = Set(filteredContents)
                } else {
                    viewModel.rightSelectedItems = Set(filteredContents)
                }
            }
        } catch {
        }
    }
}


#Preview {
    ContentView()
}
