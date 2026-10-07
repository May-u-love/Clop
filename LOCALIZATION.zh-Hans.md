# Clop 3.5.0 汉化版(快速汉化路线)

快速汉化的 macOS 剪贴板优化工具 Clop,基于上游 2026-10-07 的 main 分支(github.com/FuzzyIdeas/Clop,GPL-3.0)源码构建。

## 文件

- `Clop.app` / `Clop-3.5.0-汉化版.zip` — 汉化版应用(intel + Apple Silicon 双架构)
- `构建脚本/` — 翻译流水线(extract → 映射 → apply),上游更新后可重新套用

## 使用

把 Clop.app 拖进「应用程序」直接用(本机构建,无 quarantine,不会有 Gatekeeper 提示)。首次运行按需授予通知/辅助功能权限。

## 与官方版的差异(快速汉化 + 社区构建的固有限制)

| 项目 | 状态 |
|---|---|
| 界面文案 | 已汉化(约 1100 处:设置、右键菜单、悬浮结果、管线编辑器、状态提示) |
| 版本类型 | 免费版(许可证校验用了 stub,Pro 功能保持锁定,诚实显示免费限制) |
| 安全发送(Send securely) | 不可用(依赖作者私有 WarpDrop 后端,构建用了本地 stub) |
| iCloud 多机同步 | 不可用(去掉了需要开发证书的 entitlement) |
| 自动更新 | 已禁用(移除 Sparkle SUFeedURL,防止官方英文版覆盖汉化) |
| 命令行工具 | 输出保留英文(不影响脚本使用) |
| 保留英文 | 格式名(HEIC/PNG…)、单位(kbps/DPI)、快捷键符号、示例文件名 |

## 已知问题

- 设置搜索里部分长句描述可能仍为英文(搜索索引有约 250 条,已翻大部分)
- 个别拼接型句子语序生硬(碎片句按最小改动原则直译)

## 上游更新后重新汉化

1. `git clone` 新版,切到 `zh-Hans` 思路重放:`python3 extract_strings.py`(改路径)→ 补充 `trans_part*.py` 新增文案 → `apply_trans.py`
2. **取回 LFS 二进制包**:`Clop/bin.tar.lrz` 和 `bin.tar.lrz.sha256` 是 Git LFS 文件,浅克隆拿到的是 133 字节指针,启动解包会报 "Unrecognized archive format"。从
   `https://media.githubusercontent.com/media/FuzzyIdeas/Clop/main/Clop/bin.tar.lrz`(及 `.sha256`)下载真包放进 `Clop/`(bin.tar.lrz 用 raw 地址、bin.tar.lrz.sha256 用 raw.githubusercontent 地址)
3. WarpDrop stub:建 `WarpDropStub` 本地包(内容见 fork 仓库 `WarpDropStub/`),把 pbxproj 里的 `XCLocalSwiftPackageReference` 指向它
4. 建 `Clop/required.swift` stub(`proactive=false`、**`validReq()` 返回 true**(否则免费额度也被拦)、`invalidReq/invalidReq2/invalidReq3/hasShortcutsDB` 返回 false)
5. `xcodebuild -project Clop.xcodeproj -scheme Clop -configuration Release build CODE_SIGN_IDENTITY="-" CODE_SIGN_ENTITLEMENTS=<最小entitlements>`;改过 Info.plist 后要 `codesign -f -s -` 重签

## 源码(GPL-3.0 合规)

汉化后的完整源码在:**https://github.com/May-u-love/Clop/tree/zh-Hans**(fork 自 FuzzyIdeas/Clop)。分发本 zip 时请附上该仓库链接。
