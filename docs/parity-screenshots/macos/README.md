# macOS parity screenshots

Captured: 2026-07-08

These screenshots are reference material for rebuilding the Windows WPF client to match the current macOS SwiftUI client. Use them together with the macOS source files listed in `docs/windows-macos-ui-business-parity-handoff.md`.

## Files

| File | macOS route | Notes |
| --- | --- | --- |
| `dashboard.png` | 首页 | Dashboard cards, report chart, room list, blacklist card |
| `live-rooms.png` | 直播端 | Room list, current room, printer panel, danmaku panel |
| `entertainment.png` | 娱乐模式 | Entertainment room selection, interaction output switches, event panel |
| `pick.png` | 理货端 | Batch list, platform tabs, tag table, blacklist action |
| `order-remark.png` | 订单一键备注 | Platform/batch selectors, remark preview, action buttons |
| `blacklist.png` | 黑名单 | Filter bar, blacklist list, detail panel |
| `vip-orders.png` | 充值记录 | Order status segmented control and order table |
| `danmaku-auth.png` | 直播授权测试 | Platform auth list, login window placeholder, Cookie result, danmaku panel |

## Current gaps

- `settings.png` and `profile.png` are not included in this capture set because those bottom/sidebar entries were not reliably navigated during automated screenshot capture.
- The screenshots reflect the current logged-in macOS app state and should be used for layout/flow parity, not as test data fixtures.
