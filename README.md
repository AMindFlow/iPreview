# iPreview

iPreview 是用于本地图片和视频的原生媒体库。可以从已有创作者目录建立索引，按文件名或目录名搜索，用键盘预览，并把不同来源的媒体加入同一合集。媒体目录由应用读取，索引和合集保存在本机应用数据目录。

## 打开应用

- macOS 15+ Apple Silicon：打开 DMG，将 `iPreview.app` 拖入「应用程序」。也可使用 `.app` ZIP。
- Windows 11 x64：运行 EXE 安装器，按向导安装到专用应用目录；也可完整解压自包含 ZIP 后运行 `iPreview.exe`。无需联网或另装 .NET、Windows App SDK。
- 点击侧栏顶部的「导入文件夹」添加媒体目录。选中媒体后按 Space 打开预览，方向键切换。再次按 Space 退出并选中最后查看的媒体，按 Esc 或关闭按钮也退出并选中最后查看的媒体。

安装包和校验值见 [v0.1.0 Release](https://github.com/AMindFlow/iPreview/releases/tag/v0.1.0)。库数据独立于安装目录，卸载保留本地库。当前 Mac 包未公证、Windows 安装器未做发行签名。

## 从源码构建

在仓库根目录运行对应命令。Windows 需要 .NET 10 SDK 和面向 WinUI 的 Windows SDK 构建工具。macOS 可使用 Swift 命令行工具。

```sh
swift run iPreviewCoreChecks
bash scripts/package-macos.sh "$PWD/dist/iPreview-macos-arm64.zip"
```

```powershell
dotnet run --project apps/windows/CoreChecks/CoreChecks.csproj -c Release
dotnet publish apps/windows/iPreview/iPreview.csproj -c Release -r win-x64 --self-contained true -o dist/iPreview-windows-x64
```

[实机验收与样例](docs/project/acceptance.md) · [一期验收登记](docs/project/releases/0.1.0.md) · [未完成清单](docs/project/backlog.md) · [完整需求](docs/project/requirements.md) · [分工 DAG](docs/project/phase-1-collaboration.md)
