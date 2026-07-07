# Windows Business Feature Parity

Updated: 2026-07-07

This document tracks the Windows client work that mirrors the remaining macOS business features inside `clients/windows/FastSort.Client.Windows`.

## Implemented In Windows

- Main navigation no longer routes non-dashboard modules to placeholder cards.
- `BusinessPageView` and `BusinessPageViewModel` now back the following routes with real service calls or Windows-native capabilities:
  - Entertainment mode
  - Pick
  - Douyin/XHS order remark export
  - Blacklist
  - VIP orders
  - Settings
  - Profile
  - Payment
  - Printer test
- API services were added for macOS-matching endpoints:
  - Blacklist: page query, detail query, detail delete
  - VIP: payment orders, VIP plan list, PC payment page creation
  - Profile: profile, nickname/password/phone update, captcha, account cancel
  - Settings: rooms, tag templates, danmaku templates, mappings, sort settings, blacklist settings
  - Pick: batch list, live tags, complete batch, add blacklist
  - Live rooms: status, update, delete, print config, start live, finish live
- Windows JSON handling now accepts backend fields that may arrive as strings, numbers, booleans, or flexible enum-like values.
- Printer test uses Windows WinSpool RAW printing:
  - Enumerates local and connected printers.
  - Generates TSPL, CPCL, and ESC/POS presets.
  - Sends raw command payloads directly to the selected printer.
- Order remark export generates a local JSON payload from backend live-tag rows and opens the platform workbench page. It does not introduce browser automation or external helper processes.
- Entertainment mode consumes backend room `liveSession` through `NativeDanmakuSessionCoordinator` and writes unified native events into the business table.

## Test Scope

Run:

```powershell
dotnet build clients/windows/FastSort.Client.Windows/FastSort.Client.Windows.csproj
```

After login, test these routes:

- `Live`: authorize and save backend liveSession, then connect selected backend room.
- `Entertainment`: select a backend room, connect native adapter, stop it.
- `Pick`: load current/history batches, load tags, add a tag to blacklist, complete a batch.
- `Remark`: load Douyin or XHS batches, load tags, export remark JSON, open platform workbench.
- `Blacklist`: query list, load detail, delete detail rows that belong to the current user.
- `VIP Orders`: filter order status and page through results.
- `Payment`: select a VIP plan and open the generated Alipay PC page.
- `Profile`: update nickname/password/phone and send account-cancel request using backend captcha flow.
- `Settings`: load rooms/templates/mappings/settings and inspect room print config.
- `Printer Test`: enumerate printers, generate preset commands, and send a raw command to a selected test printer.

## Remaining Boundaries

- Douyin native danmaku remains a native placeholder because Windows still needs a safe WebView/JavaScript bridge for browser-like signing without Node/Python.
- TikTok and Shopee remain collection/registry/stub scope until backend `liveType` and room-save contracts are confirmed.
- Order remark execution currently exports the payload and opens the platform workbench; it does not automate merchant backend pages.
- Profile account cancellation is wired to the backend API, but production use should still be validated against backend captcha policy and logout/token invalidation behavior.
