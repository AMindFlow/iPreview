# iPreview

iPreview 是用于本地图片和视频的原生媒体库。可以从已有创作者目录建立索引，按文件名或目录名搜索，用键盘预览，并把不同来源的媒体加入同一虚拟专辑。媒体目录由应用读取，索引和专辑保存在本机应用数据目录。

## 打开应用

- macOS 15+ Apple Silicon：解压 `iPreview-macos-arm64.zip`，打开 `iPreview.app`。
- Windows 11 x64：把 `iPreview-windows-x64.zip` 完整解压到本机，打开 `iPreview.exe`。
- 点击「导入文件夹」添加来源。选中媒体后按 Space 打开预览，方向键切换，Esc 退出。

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

[实机验收与样例](docs/project/acceptance.md) · [规格和路线图](docs/README.md)
