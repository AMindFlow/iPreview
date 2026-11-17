# 首版实机验收

在本机 Apple Silicon Mac 和 Windows 11 x64 的交互桌面各运行一次。使用同一个最终提交的应用包和同一份合成样例。记录提交 SHA、应用包 SHA-256、系统版本、每项结果及复现步骤。

## 样例

生成端需要 Python 3、带 `libx264` 的 FFmpeg、`cwebp` 和 macOS `sips`。在仓库根目录运行以下命令。验收端只需解压即可。

```sh
python3 scripts/generate-fixtures.py /tmp/iPreview-fixtures.zip
```

将 ZIP 解压到两台机器各自的本地测试目录。以解压后的 `iPreview-fixtures` 为工作目录，按下表选择子目录。样例由色条、图案和低音量测试音生成。

| 来源 | 选择结果 |
| --- | --- |
| 沿海创作者 | 单创作者、2 个来源专辑，共 8 个媒体条目，含 1 张坏图。`旅行摄影` 内的隐藏 PNG 和 TXT 被忽略。 |
| 多创作者 | 多创作者、2 个创作者及各自的来源专辑，共 4 个媒体条目。 |
| 层级歧义 | 显示单创作者与多创作者两种选择。任一选择索引对应分支的 1 个媒体条目。 |
| 直属媒体 | 单个来源专辑，共 2 个媒体条目。 |

## 多创作者浏览

按 [LIB-009](../specs/official/library.md#lib-009-多创作者来源的浏览层级) 检查同名专辑。将样例的 `多创作者` 复制到单独的测试位置，再将副本的 `海岛摄影/长岸` 改名为 `海岛摄影/Summer`。导入副本，确认来源首页显示两名创作者。依次进入 `北京摄影 → Summer` 和 `海岛摄影 → Summer`，应分别显示 3 个和 1 个媒体。用返回按钮从专辑回到所属创作者，再回到来源。重启后复查这条路径，并验证单创作者的 `沿海创作者` 入口。

## 两端检查

1. **启动与导入。** 从解压后的应用包打开 iPreview。依次导入表中的四个来源，核对预览或导入结果。重复导入第一项，核对来源与媒体条目保持唯一。
2. **图片与键盘。** 在 `旅行摄影` 预览 JPEG、PNG、WebP 和 GIF，确认 GIF 有动画。macOS 验证 HEIC，Windows 记录系统解码结果，无法解码时应提示并允许切换。核对主图按比例适配，相邻图片在可用方向弱化显示，方向键可导航。打开 `22-坏图.jpg`，核对错误提示及后续导航。按 Esc 回到进入预览时选中的条目。再按 Space 打开，切换到另一张图片并按 Space 关闭，核对图库选中最后查看的图片，且可立刻按 Space 再次打开。
3. **视频。** 用 Space 分别打开 `01-Sunset.MP4` 和 `Sea.mov`。确认约 6 秒的画面可以播放、暂停、调节进度。音频输出启用时听到测试音。焦点在画布时按 Space 退出，确认播放停止且图库选中最后查看的视频。点击进度条，将焦点从画布移到进度条，核对方向键从切换媒体变为微调进度。macOS 还应验证按 Tab 在画布和进度条之间切换，以及进度条获得焦点时可按 Esc 退出。
4. **搜索。** 仅选文件名并使用精确模式，`lantern_02.png` 唯一命中 `Lantern_02.PNG`。仅选目录并使用精确模式，`a夜景` 命中 `Ａ夜景` 的条目。仅选目录并使用模糊模式，`bj` 命中 `北京摄影`，`lvxing` 命中 `旅行摄影`，`sumer` 命中 `Summer`。仅选文件名时这些目录查询返回空结果。关闭两个范围，结果为空。
5. **虚拟专辑。** 创建一个虚拟专辑，分别添加 `01-港湾.jpg`、`Sea.mov` 和 `Morning.png`，重命名专辑并调整成员次序。移除其中一个引用，确认仍能在来源中打开该文件。完全退出并重新打开应用，核对四个来源、专辑名、成员和次序恢复。
6. **离线和重扫。** 仅将样例的 `多创作者` 临时改名，重新扫描，核对来源离线及虚拟专辑中的 `Sea.mov` 引用仍在。恢复文件夹原名并重新扫描，核对视频重新可播且成员位置保持。该步骤中，第 5 步移除的引用应选择另一项。

7. **应用图标。** 在 Finder、Dock、Windows 资源管理器和任务栏核对应用图标，确认在浅色与深色背景下，小尺寸仍可辨识眼睛。

## 比对源文件

在导入前和完成测试并恢复样例目录名称后，各记录一次路径、大小、修改时间和 SHA-256。比较两份快照，预期完全相同。校验文件以外的新增媒体及辅助文件也会出现在结果中。

macOS 在 `iPreview-fixtures` 目录运行。第一次将快照存为 `before`，第二次存为 `after`。

```sh
shasum -a 256 -c SHA256SUMS
ipreview_snapshot() {
  python3 - <<'PY'
import hashlib
import json
from pathlib import Path

for path in sorted(Path(".").rglob("*")):
    if path.is_file():
        info = path.stat()
        print(json.dumps(
            [path.as_posix(), info.st_size, info.st_mtime_ns, hashlib.sha256(path.read_bytes()).hexdigest()],
            ensure_ascii=False,
        ))
PY
}
ipreview_snapshot > /tmp/ipreview-before.jsonl
# 完成测试后执行以下两行
ipreview_snapshot > /tmp/ipreview-after.jsonl
diff -u /tmp/ipreview-before.jsonl /tmp/ipreview-after.jsonl
```

Windows 在同名解压目录用 PowerShell 运行。比较命令预期无输出。

```powershell
function Get-IPreviewSnapshot {
    $root = (Get-Location).Path
    Get-ChildItem -File -Recurse -Force | Sort-Object FullName | ForEach-Object {
        $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
        [PSCustomObject]@{
            Path = $_.FullName.Substring($root.Length + 1)
            Size = $_.Length
            Modified = $_.LastWriteTimeUtc.Ticks
            SHA256 = $hash
        } | ConvertTo-Json -Compress
    }
}
Get-IPreviewSnapshot | Set-Content -Encoding UTF8 "$env:TEMP\ipreview-before.jsonl"
# 完成测试后执行以下两行
Get-IPreviewSnapshot | Set-Content -Encoding UTF8 "$env:TEMP\ipreview-after.jsonl"
Compare-Object (Get-Content "$env:TEMP\ipreview-before.jsonl") (Get-Content "$env:TEMP\ipreview-after.jsonl")
```

## 视图切换与应用图标

用混合图片与视频的来源专辑及虚拟专辑在两端切换图标、列表和画廊。列表核对名称、修改日期、大小及种类。画廊用鼠标和方向键切换缩略图，检查大图或视频样张随之更新。切换布局前后选中项保持一致。在各布局按 Space 进入预览，再切项并用 Space 返回最后查看项。另用 Esc 验证回到进入独立预览时选中的媒体。

在 Windows 的默认窗口尺寸确认标题、文件数和视图切换控件可读。用有同名文件的搜索样例检查路径在三种布局中可获得。检查 Finder 与 Dock、资源管理器和任务栏的白底星光眼睛图标。只读比对步骤见[比对源文件](#比对源文件)。
