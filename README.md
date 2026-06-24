# B-Music

B-Music 是一个使用 iOS 原生界面重建的 B 站音乐播放器。项目目标是把 ENO-M iOS 已经验证过的搜索、登录、解析播放、资料库和播放控制能力，改成更接近系统 App 的 SwiftUI 原生体验。

当前工程使用 `SwiftUI`、`AVPlayer`、`MediaPlayer`、`NavigationStack`、`TabView`、`List`、`Sheet` 等 iOS 原生能力构建，不再以 WebView 壳作为主要界面。

> 本项目不是 B 站官方客户端，也不包含任何官方授权关系。请仅在个人学习、研究和测试范围内使用，并遵守相关平台规则。
> 
> 本项目同样由 CodeX 完成。本篇 ReadMe文档 同样由 CodeX 撰写。

## 系统要求

- iOS 26.0 及以上
- Xcode 27 beta / iOS 27 SDK
- Swift 5
- 支持后台音频播放
- 支持 ProMotion 设备优先使用高刷新率，实际刷新率仍受设备能力、省电模式和系统策略影响

## 主要功能

- B 站音乐、视频内容搜索
- 输入 BV 号或 Bilibili 视频链接直接播放
- 搜索结果分页加载
- 搜索结果作为临时播放列表连续播放
- 搜索结果、UP 主列表支持全部播放
- 首页每周 Bilibili 音乐榜
- 网页登录和二维码登录
- 登录 Cookie 本地保存
- B 站视频音频地址解析
- 原生 `AVPlayer` 音频播放
- 播放、暂停、上一首、下一首、进度拖动
- 后台播放
- 锁屏 Now Playing 信息
- 系统远程播放控制
- 列表循环、单曲循环、随机播放
- 可配置音量平衡，减小连续切歌时的响度差异
- 播放过半后预缓存下一首，并在卡顿或失败后自动重试
- 当前播放迷你栏
- 正在播放页面
- 根据封面主色生成渐变模糊背景
- 播放队列展示与管理
- 我的收藏
- 自定义播放列表
- 播放列表编辑、删除和原生拖拽排序
- 收藏 UP 主
- UP 主空间视频列表分页加载
- UP 主详情页本页筛选
- 资料库内音乐和 UP 主搜索
- 从资料库搜索跳转到 B 站搜索
- 列表备份与恢复
- 最近播放音频缓存
- 固定缓存我的收藏和指定播放列表
- 手动清理最近播放缓存、全部音频缓存和临时播放文件
- App 图标生成脚本

## 页面结构

### 首页

首页用于搜索 B 站内容。输入关键词后可以搜索音乐、歌手和视频相关内容，也可以粘贴裸 BV 号、Bilibili 视频网页链接或 `b23.tv` 短链，直接解析并播放对应视频。搜索结果列表点击即可播放，右侧提供收藏和加入播放列表操作。

首页空状态展示每周 Bilibili 音乐榜。榜单条目可以直接播放、收藏或加入播放列表。

搜索结果会被视为一个临时播放列表。点击任意歌曲或点击“全部播放”后，播放器会按当前搜索结果生成播放队列，并支持列表循环、单曲循环和随机播放。搜索继续分页加载时，会把新结果追加到当前临时队列。

### 资料库

资料库包含本地保存的内容：

- 我的收藏
- 最近播放
- 自定义播放列表
- 收藏 UP 主

资料库支持本地搜索。默认搜索资料库中的音乐和 UP 主，也可以通过提示跳转到 B 站搜索更多内容。

从播放列表、我的收藏或最近播放中点击任意歌曲时，B-Music 会把整个列表作为当前播放队列，并从点击的歌曲位置开始播放。随机播放会生成真实随机队列，播放队列显示顺序和实际播放顺序保持一致。

### 正在播放

正在播放页面包含：

- 当前歌曲封面
- 歌曲标题和 UP 主入口
- 收藏和加入列表
- 播放进度
- 播放控制
- 播放模式切换
- 播放队列

页面背景会根据当前封面提取近似主色，生成柔和的渐变和模糊背景。切歌时背景颜色会缓慢过渡。

### 设置

设置页包含：

- 登录状态
- 网页登录
- 扫码登录
- 退出登录
- 播放状态
- 资料库统计
- 清空最近播放列表
- 缓存状态和缓存策略开关
- 清理最近播放缓存
- 清理全部音频缓存
- 清理临时播放文件
- 列表备份与恢复
- 当前版本号

## 收藏和播放列表

B-Music 统一了音乐列表的交互：

- 点击列表项直接播放
- 心形按钮用于收藏或取消收藏
- 加号按钮用于加入播放列表
- 加号不会判断是否已收藏，会直接弹出播放列表选择页
- 播放列表选择页支持新建播放列表

`我的收藏` 是默认列表，不支持改名或删除。取消收藏后，在当前收藏页面中不会立即消失，避免误触；离开页面再返回后会刷新。

自定义播放列表支持：

- 新建
- 删除
- 歌曲删除
- 原生编辑模式排序
- 导入导出

收藏 UP 主后，可以在资料库进入 UP 主详情页。详情页支持继续加载更多视频、本页按歌名筛选，以及将当前列表全部加入播放队列。

## 备份与恢复

设置页提供列表备份能力：

- 每个列表导出为一个独立 JSON 文件
- `我的收藏` 会单独导出
- 每个自定义播放列表会单独导出
- 导入时支持一次选择多个 JSON 文件
- 导入 `我的收藏` 文件会恢复我的收藏
- 导入自定义播放列表文件时，优先按 `playlistID` 匹配已有列表，匹配不到再按列表名匹配
- 匹配到已有列表会覆盖该列表内容
- 匹配不到会创建新的播放列表

导入时的去重只发生在单个列表内部，不会跨列表去重。同一首歌可以同时存在于不同播放列表中。

## 缓存策略

B-Music 会把音频缓存到 App 的 `Library/Caches/BMusicAudio` 目录。缓存按歌曲标识复用，同一首歌即使同时存在于最近播放、我的收藏和多个播放列表中，也只对应一份本地音频文件。

默认策略：

- 保留最近播放的 100 首音频缓存
- 可以在设置中选择固定缓存“我的收藏”
- 可以在设置中选择固定缓存指定自定义播放列表
- 播放已缓存歌曲时会优先使用本地文件，避免重复拉流

设置页提供三个手动清理入口：

- 清理最近播放缓存：只清理最近播放策略带来的缓存，保留收藏和已固定播放列表缓存
- 清理全部音频缓存：清理最近播放、我的收藏和播放列表相关的全部音频缓存
- 清理临时播放文件：清理 `tmp` 中残留的播放下载临时文件

## 性能与体验

项目做了一些针对原生体验的优化：

- `CADisableMinimumFrameDurationOnPhone` 已开启，用于支持 ProMotion 高刷新率
- 播放进度从主 `BMusicViewModel` 拆分到独立的 `BMusicPlaybackProgress`
- 避免播放进度更新导致首页、资料库、设置页等无关页面重复刷新
- 正在播放页队列使用 `LazyVStack`
- 播放队列行避免直接观察整个全局 ViewModel
- 快速切歌时取消旧下载任务，减少无效流量和临时文件膨胀
- 当前歌曲播放过半后预缓存下一首，网络卡顿或播放失败超过 10 秒会自动重试当前歌曲
- 音量平衡只采样本地音频的若干短片段，并缓存本次运行中的分析结果，避免逐首完整扫描

## 工程结构

```text
B-Music
├── B-Music.xcodeproj
├── BMusic
│   ├── Assets.xcassets
│   │   └── AppIcon.appiconset
│   ├── BiliApiClient.swift
│   ├── BiliLoginClient.swift
│   ├── BMusicApp.swift
│   ├── ContentView.swift
│   ├── CookieStore.swift
│   ├── Info.plist
│   └── NativeAudioPlayer.swift
├── Build
│   └── DerivedData
├── Scripts
│   └── generate_bmusic_icon.swift
└── README.md
```

### 核心文件

- `BMusic/ContentView.swift`
  - SwiftUI 页面、主状态管理、资料库、播放页、设置页、备份恢复逻辑
- `BMusic/BiliApiClient.swift`
  - B 站搜索、视频详情、播放地址接口
- `BMusic/BiliLoginClient.swift`
  - 二维码登录、网页登录状态验证、用户信息获取
- `BMusic/CookieStore.swift`
  - Keychain Cookie 保存和读取
- `BMusic/NativeAudioPlayer.swift`
  - `AVPlayer` 播放、音频下载、后台播放、锁屏信息、远程控制
- `Scripts/generate_bmusic_icon.swift`
  - 旧版 App 图标生成脚本

## 构建方式

### 使用 Xcode

```sh
open B-Music.xcodeproj
```

如果要安装到真机，需要在 Xcode 中配置自己的 Team、Bundle Identifier 和签名。

### 命令行构建

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project B-Music.xcodeproj -scheme BMusic -sdk iphoneos27.0 -arch arm64 -derivedDataPath ./Build/DerivedData CODE_SIGNING_ALLOWED=NO build
```

## 生成 App 图标

项目内保留了图标生成脚本：

```sh
swift -module-cache-path Build/SwiftModuleCache Scripts/generate_bmusic_icon.swift BMusic/Assets.xcassets/AppIcon.appiconset/AppIcon.png
```

生成后重新构建项目即可。

## 数据保存

- 登录 Cookie 保存到 Keychain
- 收藏、最近播放、播放列表、播放队列、收藏 UP 主保存到 `UserDefaults`
- 音频缓存保存到 `Library/Caches/BMusicAudio`
- 临时播放下载文件保存到系统 `tmp`，可在设置页手动清理
- 列表备份文件为 JSON

## 当前限制

- 音频来自 B 站视频资源解析，不是独立音乐版权服务
- 播放能力依赖 B 站接口返回结果和登录状态
- 暂未实现歌词
- 暂未实现 CarPlay
- 暂未实现完整账号内容页
- 备份文件没有加密，不建议放入敏感共享目录

## 说明

B-Music 目前重点是验证一套更原生、更贴近系统习惯的 iOS 音乐播放体验。后续可以继续补充歌词、播放历史筛选、更多资料库管理能力和更完整的账号内容浏览。
