# Windows EXE 安装器

先按仓库 README 发布完整的 Windows x64 自包含应用，再运行：

```powershell
./scripts/package-windows.ps1 -PublishDirectory ./dist/iPreview-windows-x64 -OutputDirectory ./dist
```

构建需要 Inno Setup 6；CI 当前使用 runner 预装的 6.7.1。许可见固定版本 [Inno Setup 6.7.1 license.txt](https://github.com/jrsoftware/issrc/blob/is-6_7_1/license.txt)，允许包含商业应用在内的使用。供应商官网[请求商业用户购买许可支持项目](https://jrsoftware.org/inno-setup)；本项目未购买许可或修改其条款。简体中文资源及许可在 [Languages](Languages/README.md) 中维护。

安装器在当前用户权限下运行，所有运行时随包提供。默认目录为 `%LOCALAPPDATA%\Programs\iPreview`，也可选择专用应用目录。同版本覆盖会替换应用发布文件；不要选择媒体或数据库目录。卸载仅移除安装器登记的文件和入口，保留独立的 `%LOCALAPPDATA%\iPreview` 库及未由安装器安装的文件。

CI 在隔离 runner 中用 `scripts/check-windows-installer.ps1` 验证首次安装、覆盖修复、卸载、入口和全部发布文件的 SHA-256，以及库和用户文件的保留。Windows 11 实机验收结果随版本交付记录。未配置 Authenticode 证书，当前 EXE 没有数字签名。
