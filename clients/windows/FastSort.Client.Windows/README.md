# FastSort.Client.Windows

Windows 原生客户端，WPF + .NET 8 实现。

目标运行环境：

- Windows 10 19041 及以上
- .NET 8 Desktop Runtime

验证命令需要在 Windows 环境执行：

```powershell
dotnet build clients/windows/FastSort.Client.Windows/FastSort.Client.Windows.csproj
dotnet run --project clients/windows/FastSort.Client.Windows/FastSort.Client.Windows.csproj
```

当前状态：

- Phase 0 骨架。
- 已有 WPF 工程、主窗口、主题资源、API Client 基础类。
- 后续按 `docs/native-client-development-plan.md` 逐页补齐。

