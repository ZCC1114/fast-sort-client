# 弹幕标签打印客户端改造上下文

更新时间：2026-07-05  
记录位置：`/Users/zcc/Documents/git-workspace-zcc/fast-sort-client/docs/client-rebuild-context.md`

## 改造目标

基于现有后端弹幕标签打印服务，新增一个客户端版本。客户端需要与现有 Web 端和 App 端功能完全一致，并在后续改造中优化当前 Web/App 使用体验不够顺畅的地方。

## 现有项目

| 项目 | 本地路径 | 作用 | 当前分支 | 远端 |
| --- | --- | --- | --- | --- |
| 后端服务 | `/Users/zcc/Documents/git-workspace-zcc/fast-sort` | 统一后台服务，供 Web/App/后续客户端调用 | `prod-sj` -> `origin/prod-sj` | `https://github.com/ZCC1114/fast-sort.git` |
| Web 端 | `/Users/zcc/Documents/git-workspace-zcc/fast-sort-web` | 现有 Web 前端 | `main` -> `origin/main` | `https://github.com/ZCC1114/fast-sort-web.git` |
| App 端 | `/Users/zcc/Documents/git-workspace-zcc/rapid-sorting` | 现有 App/uni-app 端 | `20260403` -> `origin/20260403` | `https://github.com/ysm900617/rapid-sorting.git` |

## 本次拉取基线

已在 2026-07-05 对三个现有项目执行：

```bash
git pull --ff-only --autostash
```

拉取结果：

| 项目 | 结果 | 最新提交 |
| --- | --- | --- |
| 后端服务 `fast-sort` | 已是最新 | `64cda2427bde69591080f3e40d70cc5234c39d90` / `64cda242` |
| Web 端 `fast-sort-web` | 已是最新 | `573bff559f365aa464d6874761fcc04f381d024c` / `573bff5` |
| App 端 `rapid-sorting` | 从 `172af59` 快进到 `eeda56e`，并成功应用 autostash | `eeda56e526a0bb968c6b79cd1467f57b48ca606d` / `eeda56e` |

最新提交详情：

| 项目 | 提交时间 | 作者 | 提交说明 |
| --- | --- | --- | --- |
| 后端服务 | `2026-06-16 10:13:30 +0800` | 莫醒醒 | 直播间列表直播间名称去掉末尾非法字符 |
| Web 端 | `2026-06-26 01:45:45 +0800` | ZCC1114 | Merge branch 'sj' |
| App 端 | `2026-07-03 14:44:16 +0800` | 莫醒醒 | 适配标签 |

拉取后的本地工作区状态：

| 项目 | 状态 |
| --- | --- |
| 后端服务 | 有未跟踪目录：`docs/contracts/`、`ops/` |
| Web 端 | 工作区干净 |
| App 端 | 有本地改动：`.DS_Store`；有未跟踪内容：`docs/`、`manual-videos/`、`my-release-key.keystore` |
| 客户端目录 | `/Users/zcc/Documents/git-workspace-zcc/fast-sort-client` 当前不是 Git 仓库 |

## 技术栈线索

### 后端服务

- 入口配置：`/Users/zcc/Documents/git-workspace-zcc/fast-sort/pom.xml`
- Maven / Spring Boot 项目
- Spring Boot 版本：`2.7.18`
- Java 版本：`1.8`
- 主要依赖线索：Spring Web、AOP、JDBC、Redis、Validation、MySQL、MyBatis-Plus、PageHelper、Knife4j OpenAPI、Fastjson2、Hutool、EasyExcel 等

### Web 端

- 入口配置：
  - `/Users/zcc/Documents/git-workspace-zcc/fast-sort-web/package.json`
  - `/Users/zcc/Documents/git-workspace-zcc/fast-sort-web/vite.config.js`
- 技术栈：Vite、Vue 3、Vue Router、Vue I18n、ECharts
- 构建脚本：
  - `npm run dev`
  - `npm run build`
  - `npm run preview`
- Vite `base`：`/xunjian/`
- 开发代理线索：
  - `/api` -> `https://xunjian.org.cn`
  - `/app`、`/admin`、`/common`、`/oss` -> `http://localhost:8888`
- Web 项目内还包含本地语音服务脚本：`local-speech-agent-mac`

### App 端

- 入口配置：
  - `/Users/zcc/Documents/git-workspace-zcc/rapid-sorting/manifest.json`
  - `/Users/zcc/Documents/git-workspace-zcc/rapid-sorting/uni.scss`
- 应用名称：迅拣
- 应用描述：帮助主播快速打印标签以及高效理货的辅助 App
- 当前版本：`3.2.11` / `3211`
- 技术线索：uni-app x、Vue 3、UTS/UVue 页面结构
- 关键能力线索：
  - 蓝牙权限，用于连接打印机
  - 支付模块：支付宝支付、微信支付、虚拟支付
  - Android/iOS 权限和图标配置
- 新近 App 提交新增了字体文件：`static/fonts/noto_sans_cjk_bold.ttc`、`static/fonts/noto_sans_cjk_regular.ttc`

## 后续客户端改造待补充

后续进入客户端改造时，建议继续在本文档补充：

- 后端接口清单：从后端 Controller、Web 调用层、App 请求层交叉确认。
- 功能清单：直播间、弹幕、标签模板、批量打印、黑名单、拣货/理货、登录、支付、打印机连接等模块逐项对齐。
- 平台能力差异：桌面客户端需要替代或复用 App 里的蓝牙、打印、字体、权限、支付、本地语音等能力。
- 体验优化点：记录 Web/App 当前不好用的问题、复现路径、期望客户端交互。
- 数据/配置兼容：确认客户端是否沿用同一个后台账号体系、接口域名、模板数据、打印协议和标签渲染规则。
