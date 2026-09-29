<img src="assets/Cup.png" alt="Caffeine 咖啡杯圖示" width="160"/>

# Caffeine

### 讓你的 Mac 保持清醒 — 連闔上蓋子也行。

[English](README.md) • [繁體中文](README.zh-Hant.md)

Caffeine 是一個小巧的選單列工具，可以防止 Mac 進入睡眠、暗螢幕或啟動螢幕保護程式。本 fork（基於 [`domzilla/Caffeine`](https://github.com/domzilla/Caffeine)）新增了 **「闔蓋時保持運作」**（接通電源或使用電池時都有效）與 **「登入時啟動」** 開關，並補上繁體中文在地化。

---

## 快速開始

1. 從 [Releases](https://github.com/bubbleee030/Caffeine/releases) 頁面下載最新的 `Caffeine.app`。
2. 拖到 `~/Applications` 或 `/Applications`。
3. 點兩下啟動，選單列右側會出現一個咖啡杯圖示。
4. **點按** 杯子切換啟用狀態，**按右鍵**（或 ⌃-點按）顯示完整選單。

## 功能

| 功能 | 說明 |
| --- | --- |
| **切換啟用** | 點按選單列的咖啡杯。滿杯＝啟用中，空杯＝Mac 正常睡眠。 |
| **計時啟用** | 右鍵選單 → *啟用時長* → 選擇 5 分鐘 ‥ 5 小時，或 *無限期*。 |
| **登入時啟動** *(新)* | 偏好設定 → *登入時啟動*。使用 `SMAppService`，App Sandbox 友善，不需 helper bundle。 |
| **闔蓋時保持運作** *(新)* | 偏好設定 → *闔蓋時保持運作*。讓筆電闔上蓋子後繼續運作 — **接通電源或使用電池都可以**。每次啟用 Caffeine 時用 Touch ID 確認，睡眠設定會自動還原。 |
| **保持 App 活躍** | 模擬 HID 活動，避免 Teams、Slack 等把你標為「離開」。 |
| **手動睡眠時停用** | 從 Apple 選單手動進入睡眠時停止 Caffeine。 |

## 教學：兩個新開關

### 登入時啟動

打開偏好設定（右鍵杯子 → *偏好設定…*），開啟 **登入時啟動**。macOS 會將 Caffeine 註冊為登入項目；你也可以在 **系統設定 → 一般 → 登入項目與擴充功能** 中看到它。從任一邊切換狀態都會同步 — 偏好設定視窗開啟時 Caffeine 會重新讀取 `SMAppService.mainApp.status`。

### 闔蓋時保持運作

開啟 **闔蓋時保持運作**，然後啟用 Caffeine（點杯子）。之後你可以闔上蓋子，Mac 會繼續執行 — 接通電源或使用電池都行。適合下載中、長時間轉檔，或把筆電當主機接外接螢幕時闔起來放著。

**第一次使用：** Caffeine 會先說明接下來的動作，然後 macOS 會要求輸入**一次**管理者密碼。Caffeine 會安裝 `/etc/sudoers.d/caffeine-lid`，這條規則只允許它執行 `pmset disablesleep 0` 和 `pmset disablesleep 1`，其他一概不行。

**每次啟用：** 用 Touch ID（或密碼）確認。如果取消，Caffeine 仍會啟用，但闔蓋運作只在接通電源時有效。Caffeine 在啟動時自動啟用（「啟動 Caffeine 時自動啟用」）會略過這一步，登入時不會跳出提示；電池模式會在你下次手動啟用時開始。

**睡眠一定會還原**：停用 Caffeine、計時結束、結束 Caffeine（包含 `killall Caffeine`），以及當機後下次啟動時。使用電池時，電量低於 **電池電量低於此值時恢復睡眠** 的設定值（預設 20%）也會自動關閉。只要恢復睡眠時蓋子已經闔上、而且沒有接外接螢幕，Mac 就會直接進入睡眠。

> ⚠️ 闔蓋模式開啟時，Mac 完全不會睡眠 — 不要讓它在包包裡繼續運作。

在終端機檢查目前設定（闔蓋模式開啟時顯示 `Yes`）：

```bash
ioreg -rn IOPMrootDomain -d 1 | grep '"SleepDisabled"'
```

移除規則（下次使用此功能時 Caffeine 會再詢問一次）：

```bash
sudo rm /etc/sudoers.d/caffeine-lid
```

如果睡眠一直沒有恢復（例如在闔蓋模式開啟時刪除了 Caffeine）：

```bash
sudo pmset disablesleep 0
```

## 支援的語言

Caffeine 內建 14 種語系：

> English · 繁體中文 · 简体中文 · 日本語 · 한국어 · Deutsch · Español · Français · Italiano · Nederlands · Português (BR) · Português (PT) · Русский · Українська

歐語與斯拉夫語的兩個新字串為盡力翻譯，歡迎母語人士透過 issue 或 PR 校稿。

## 系統需求

- macOS 14.6（Sonoma）或更新版本
- Apple Silicon 或 Intel 處理器

## 從原始碼建構

```bash
git clone git@github.com:bubbleee030/Caffeine.git
cd Caffeine
xcodebuild -project src/Caffeine.xcodeproj -scheme Caffeine \
    -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
swift test     # 跑 manager 類別的單元測試
scripts/integration-test.sh    # 建構並驗證 pmset assertion 類型
```

## 常見問題

##### 這是我以前用過的那個 Caffeine 嗎？

是 — 這是它的功能 fork。Tomas Franzén 在 2006 年釋出最初版本，2018 年由 Michael Jones（IntelliScape）以開源授權復活，2025 年 Dominic Rodemer（[domzilla/Caffeine](https://github.com/domzilla/Caffeine)）用 SwiftUI 重寫。本 fork 在這個基礎上加入登入時啟動與闔蓋支援。

##### 可以在 macOS 10.x 上跑嗎？

不行，本版本需要 macOS 14.6（Sonoma）或更新。上游 `domzilla/Caffeine` 支援 macOS 11+；更舊的系統不再支援。

##### 跟 Amphetamine、KeepingYouAwake 這些有什麼不一樣？

本 fork 的重點是保留 Caffeine 一貫的簡潔，再加上 Amphetamine 的闔蓋功能。如果你喜歡 Amphetamine 的工作階段／觸發器系統，那個比較適合。如果你只想要一個點一下就清醒的咖啡杯、再加上闔蓋繼續跑，那就是本作。

## 支援

發現 bug 或想許願功能？請到 GitHub 開 issue：

> **<https://github.com/bubbleee030/Caffeine/issues>**

## 致謝

- © 2006 **Tomas Franzén** — 最初的 Caffeine
- © 2018 **Michael Jones**（IntelliScape）— 復活並開源
- © 2022 **Dominic Rodemer** — SwiftUI 重寫、Sparkle 更新、多語系
- 2026 **[@bubbleee030](https://github.com/bubbleee030)** — 登入時啟動、闔蓋支援、繁體中文

完整版本歷史見 [`CHANGELOG.md`](CHANGELOG.md)。
