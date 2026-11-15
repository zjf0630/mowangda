# 莫忘哒 · iOS 工程

一句话记行程：说一句 / 打一行 → 自动拆条、按时间排好 → 写进系统「提醒事项」。

- 目标系统：iOS 17 及以上（含 iOS 26）
- 界面：SwiftUI，零第三方依赖
- 数据：权威数据在系统「提醒事项」（EventKit），App 只做输入口与缓存
- 语音：Speech 框架本机识别，不联网不上传

## 怎么装到手机

本目录上一级有《莫忘哒-装到iPhone-操作手册.md》，从注册 GitHub 一路写到手机点开图标，全程不需要 Mac。按那份做即可。

## 目录结构

```
project.yml                      XcodeGen 工程描述（云编译时用它生成 .xcodeproj）
Info.plist                       权限说明：提醒事项 / 麦克风 / 语音识别
Sources/                         11 个 Swift 源文件
Resources/Assets.xcassets/       App 图标
.github/workflows/build-ipa.yml  GitHub Actions 云编译脚本
```

## 两种编译方式

### 方式一：GitHub Actions（无需 Mac，推荐）

推到 GitHub 仓库后自动编译，在 Actions → Artifacts 下载 `MoWangDa.ipa`（未签名，需用 Sideloadly 签名安装）。

### 方式二：本地 Mac

```bash
brew install xcodegen
xcodegen generate
open MoWangDa.xcodeproj
```

在 Xcode 里选自己的开发者 Team，连上 iPhone 直接 Run（免费 Apple ID 7 天有效）。

## 功能对应

| 文件 | 作用 |
|---|---|
| Sources/MoWangDaApp.swift | App 入口 |
| Sources/Models.swift | TodoItem / ParsedItem / Theme 色板 |
| Sources/TimeParser.swift | 中文时间解析引擎（与网页原型同规则） |
| Sources/ReminderStore.swift | EventKit 读写 + 本地缓存 |
| Sources/SpeechController.swift | 本机中文语音识别（requiresOnDeviceRecognition） |
| Sources/RootView.swift | 主界面：分组时间轴 / 已完成折叠 / 批量选择删除 |
| Sources/ComposeView.swift | 录入页：实时拆条 + 语音 + 写入 |
| Sources/DetailView.swift | 详情页：标题/时间/提醒/列表/优先级/截止/备注 |
| Sources/SettingsView.swift | 设置页：默认提前量、字体大小三档 + 铃声/振动说明 |
| Sources/Preferences.swift | 本地偏好（默认提前分钟数、字体档位） |
| Sources/WidgetBridge.swift | 把当天条目快照写给桌面小组件 |

## 与网页原型的差异

- 写入提醒事项是真的：默认写入名为「工作」的列表，不存在会自动创建
- 提醒真的会响：默认提前 15 分钟（设置页可改成 0/5/15/30/60），由系统提醒事项推送，本 App 不申请通知权限
- 界面跟随系统深浅色：色板全部是 `UIColor` 动态色，`Info.plist` 不锁定 `UIUserInterfaceStyle`
- 左滑只有右侧：「完成」在左、「删除」在最右，关闭全滑避免误删；长按有同样菜单
- 重复提醒：详情页可设「每天 / 工作日」，走 EKRecurrenceRule，系统提醒事项按规则提醒
- 桌面小组件：WidgetKit 扩展（MoWangDaWidget target），经 App Group `group.com.wuhan.mowangda` 读当天快照；点小组件经 `mowangda://` scheme 回 App
- 字体大小三档：设置页选档，所有字号经 `Theme.fs()` 统一缩放，`.id(fontLevel)` 触发整树重建
- 语音是本机识别：`requiresOnDeviceRecognition = true`，不联网不上传
- 「截止」以备注前缀 `[截止]` 持久化（EventKit 没有该字段）
- 未授权提醒事项时 App 仍可用，数据走本地缓存，详情页顶部有提示

## 已验证与未验证

- 已验证：中文时间解析规则（与网页原型同源，11 条用例全过）、界面布局、分组排序逻辑
- 已验证：GitHub Actions（macos-latest + Xcode 26.6）编译通过，产出可签名的 unsigned ipa

## 已知边界

- 免费 Apple ID 签名 7 天过期，需重装续签；长期免续签可用 AltStore 或付费开发者账号
- EventKit 无法原生存储「截止」语义，这是苹果数据模型的限制
- **提醒铃声 / 振动 App 改不了**：`EKAlarm.soundName` 仅 macOS 可用，iOS 编译报 `'soundName' is unavailable in iOS`；振动次数更无接口。到点响不响、振几下由系统「提醒事项」决定，设置页里给了改法
