# Printing Rules

第一版按 Web 端行为对齐。

- 标签打印由后端生成 Hex 指令，客户端只负责发送到打印机。
- 标签模板测试使用 `/app/fsLiveTag/textPrintLiveTagV2`。
- 直播弹幕打印使用 `/app/fsLiveTag/printLiveTagV2`。
- 普通标签指令类型：TSPL 或 CPCL，由模板 `instructionType` 决定。
- 娱乐模式互动打印使用 ESC/POS 位图。
- 自动打印队列在打印机断开时暂停，重连后继续。
- 黑名单命中时不打印，并在 UI 上标记拦截状态。
- 直播端手动打印优先使用弹幕映射；无映射时从弹幕内容提取数字。

