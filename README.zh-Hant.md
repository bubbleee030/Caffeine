<img src="assets/Cup.png" alt="Caffeine 咖啡杯圖示" width="160"/>

# Caffeine

### 讓你的 Mac 保持清醒 — 連闔上蓋子也行。

[English](README.md) • [繁體中文](README.zh-Hant.md)

Caffeine 是一個小巧的選單列工具，可以防止 Mac 進入睡眠、螢幕變暗或啟動螢幕保護程式。這個 fork 以 [`domzilla/Caffeine`](https://github.com/domzilla/Caffeine) 為基礎，新增 **「闔蓋時保持運作」**（接電源或用電池都有效）和 **「登入時啟動」** 兩個開關，並加入繁體中文介面。

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
| **登入時啟動** *(新)* | 偏好設定 → *登入時啟動*。使用 `SMAppService`，不需 helper。 |
| **闔蓋時保持運作** *(新)* | 右鍵點杯子 → *闔蓋時保持運作*（或偏好設定裡的同一個勾選框）。筆電闔上蓋子後仍會繼續運作，**接電源或用電池都可以**，螢幕則會照常關閉。每次啟用 Caffeine 時用 Touch ID 確認，結束後睡眠設定會自動還原。 |
| **保持 App 活躍** | 模擬 HID 活動，避免 Teams、Slack 等把你標為「離開」。 |
| **手動睡眠時停用** | 從 Apple 選單手動進入睡眠時停止 Caffeine。 |

## 教學：兩個新開關

<p align="center">
  <img src="docs/images/preferences.png" width="409" alt="Caffeine 偏好設定：登入時啟動、闔蓋時保持運作、電池電量低於此值時恢復睡眠">
</p>

（截圖為英文介面；繁體中文介面的項目位置相同。）

### 登入時啟動

打開偏好設定（右鍵杯子 → *偏好設定…*），開啟 **登入時啟動**。macOS 會把 Caffeine 註冊為登入項目，你也可以在 **系統設定 → 一般 → 登入項目與擴充功能** 看到它。不論從哪一邊切換，狀態都會同步：每次開啟偏好設定視窗，Caffeine 都會重新讀取 `SMAppService.mainApp.status`。

### 闔蓋時保持運作

<p align="center">
  <img src="docs/images/menu-lid-toggle.png" width="303" alt="Caffeine 選單：闔蓋時保持運作已勾選">
</p>

右鍵點杯子，在選單點選 **闔蓋時保持運作**（打勾代表已開啟），也可以用偏好設定裡的勾選框。接著點杯子啟用 Caffeine，之後闔上蓋子，Mac 仍會繼續執行，接電源或用電池都可以。適合下載檔案、長時間轉檔，或把筆電接上外接螢幕、闔起來當主機用。

**闔上蓋子後螢幕一樣會關閉**，Mac 只是繼續運作。有接外接螢幕的話，外接螢幕會保持開啟。

**第一次使用：** Caffeine 會先說明接下來要做什麼，接著 macOS 會要求輸入**一次**管理者密碼。Caffeine 會安裝 `/etc/sudoers.d/caffeine-lid`，這條規則只允許它執行 `pmset disablesleep 0` 和 `pmset disablesleep 1`，其他一概不行。

**每次啟用：** 用 Touch ID（或密碼）確認。如果 Caffeine 是在啟動時自動啟用（「啟動 Caffeine 時自動啟用」），就會略過這一步，所以登入時不會跳出提示；電池模式會等你下次手動啟用時才開始。

#### 如果取消 Touch ID

| 在什麼時候取消… | 結果 |
| --- | --- |
| 剛把開關**打開**時（Caffeine 已在啟用中） | 開關會自動**關回去**，其他設定都不變。 |
| 開關已開啟、**啟用** Caffeine 時 | Caffeine 仍會啟用，但闔蓋運作**只在接上電源（AC）時有效**。選單會在開關下方顯示灰色的「未能開啟電池供電時的闔蓋模式。」重新啟用一次並用 Touch ID 確認，就能開啟電池模式。 |

<p align="center">
  <img src="docs/images/menu-lid-not-enabled.png" width="375" alt="Caffeine 選單顯示：電池供電時的闔蓋模式未啟用">
</p>

**睡眠一定會還原**：停用 Caffeine、計時結束、結束 Caffeine（包含 `killall Caffeine`），或當機後下次啟動時都會還原。使用電池時，只要電量低於 **電池電量低於此值時恢復睡眠** 的設定值（預設 20%），闔蓋模式也會自動關閉。還原睡眠時，如果蓋子已經闔上又沒有接外接螢幕，Mac 會直接進入睡眠。

> ⚠️ 闔蓋模式開啟時，Mac 完全不會睡眠，別把運作中的 Mac 放進包包。

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

本 fork 新增字串（登入時啟動與闔蓋模式）的翻譯為盡力而為，歡迎母語人士透過 issue 或 PR 協助校稿。

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

是，這是它加上新功能的 fork。Tomas Franzén 在 2006 年釋出最初版本，2018 年 Michael Jones（IntelliScape）以開源授權重新推出，2025 年 Dominic Rodemer（[domzilla/Caffeine](https://github.com/domzilla/Caffeine)）用 SwiftUI 重寫。本 fork 在這個基礎上加入登入時啟動與闔蓋支援。

##### 可以在 macOS 10.x 上跑嗎？

不行，本版本需要 macOS 14.6（Sonoma）或更新。上游 `domzilla/Caffeine` 支援 macOS 11+；更舊的系統不再支援。

##### 跟 Amphetamine、KeepingYouAwake 這些有什麼不一樣？

本 fork 保留 Caffeine 一貫的簡潔，再加上類似 Amphetamine 的闔蓋功能。如果你需要 Amphetamine 的工作階段／觸發器系統，用 Amphetamine 會比較適合；如果你只想要點一下就保持清醒的咖啡杯，外加闔蓋繼續運作，這個就很適合。

## 支援

發現 bug 或想許願功能？請到 GitHub 開 issue：

> **<https://github.com/bubbleee030/Caffeine/issues>**

## 致謝

- © 2006 **Tomas Franzén** — 最初的 Caffeine
- © 2018 **Michael Jones**（IntelliScape）— 復活並開源
- © 2022 **Dominic Rodemer** — SwiftUI 重寫、Sparkle 更新、多語系
- 2026 **[@bubbleee030](https://github.com/bubbleee030)** — 登入時啟動、闔蓋支援、繁體中文

完整版本歷史見 [`CHANGELOG.md`](CHANGELOG.md)。
