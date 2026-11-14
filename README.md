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
Sources/                         8 个 Swift 源文件
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

## 与网页原型的差异

- 写入提醒事项是真的：默认写入名为「工作」的列表，不存在会自动创建
- 提醒真的会响：默认提前 15 分钟，由系统提醒事项推送，本 App 不申请通知权限
- 语音是本机识别：`requiresOnDeviceRecognition = true`，不联网不上传
- 「截止」以备注前缀 `[截止]` 持久化（EventKit 没有该字段）
- 未授权提醒事项时 App 仍可用，数据走本地缓存，详情页顶部有提示

## 已验证与未验证

- 已验证：中文时间解析规则（与网页原型同源，11 条用例全过）、界面布局、分组排序逻辑
- 未验证：本工程尚未在真实 Xcode 中编译过（编写环境为 Windows）。首次云编译如报错，多为 API 签名细节，按日志改即可，不涉及架构调整

## 已知边界

- 免费 Apple ID 签名 7 天过期，需重装续签；长期免续签可用 AltStore 或付费开发者账号
- EventKit 无法原生存储「截止」语义，这是苹果数据模型的限制
