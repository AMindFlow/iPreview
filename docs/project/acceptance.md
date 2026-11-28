# 双端验收步骤

各版本实际执行的项目、提交、产物 SHA-256、系统版本和未验证项以对应的发布与验收登记为准，见 [0.2.0](releases/0.2.0.md)、[0.3.0](releases/0.3.0.md) 和 [0.3.1](releases/0.3.1.md)。用同一最终源码和相同的合成样例在 Apple Silicon Mac 与 Windows 11 x64 实机验证。功能测试使用隔离 QA 资料库，复用样例集中于各自 `~/Temporary/iPreview/`。

## 样例和保护边界

生成端需要 Python3、带 libx264 的 FFmpeg、cwebp 和 macOS sips；验收端只需解压。运行：

```sh
python3 scripts/generate-fixtures.py /tmp/iPreview-fixtures.zip
```

该脚本生成四类基础目录和 `视频作品` 下的有样张、无样张及旧目录命名的 [LIB-006](../specs/official/library.md#lib-006-两种视频作品结构)样例。0.1.0 的 `samples/iPreview-fixtures.zip` 还保留损坏视频补例，`samples/supplement.zip` 提供长视频15秒跳转、同名不同后缀、长名称、`@` 字面量及多行层级导航等样例。两端解压到各自 `~/Temporary/iPreview/` 复用，按版本清单核对哈希并记录实际使用的样例。

| 来源 | 预期导入结果 |
| --- | --- |
| 沿海创作者 | 单创作者、2个专辑、8个媒体（含坏图）；隐藏 PNG 和 TXT 忽略。 |
| 多创作者 | 2名创作者及各自专辑、4个媒体。 |
| 层级歧义 | 显示单创作者／多创作者摘要选择，任一选择索引对应分支的1个媒体。 |
| 直属媒体 | 单个专辑、2个媒体。 |

功能验收前退出全部 iPreview 进程，只给 QA 启动进程设置 `IPREVIEW_DATA_DIR`，不要写入全局环境。它是测试隔离入口，不代表已提供多工作区产品功能。Mac 例如：

```sh
IPREVIEW_DATA_DIR="$HOME/Temporary/iPreview/qa-catalog" /Applications/iPreview.app/Contents/MacOS/iPreview
```

Windows 使用实际安装目录；默认安装位置的例子：

```powershell
$env:IPREVIEW_DATA_DIR = Join-Path $env:USERPROFILE 'Temporary\iPreview\qa-catalog'
& "$env:LOCALAPPDATA\Programs\iPreview\iPreview.exe"
$env:IPREVIEW_DATA_DIR = $null
```

QA 结束后退出应用，从正常安装入口启动并按该次交付口径核对首页。需要交付正式空库时，确认首页为空并截图。测试来源和测试库保留在 Temporary 供复用。

更名和离线测试仅操作可丢弃副本。先记录源文件快照；结束时恢复样例目录名，再比较路径、大小、修改时间与 SHA-256。集合引用操作不应写入或删除真实文件。

## 安装与恢复

按 [PLAT-005](../specs/official/platforms.md#plat-005-首版标准安装包)验证：Mac 挂载 DMG、检查应用和 Applications 入口、拖入安装并从安装位置打开；Windows 运行 EXE，确认语言／目录／进度／完成及开始菜单、系统卸载项。安装目录选专用应用目录，覆盖现有安装前退出应用。

用隔离测试资料库检查安装、覆盖升级、卸载后数据保留和再安装后的索引与合集恢复。Windows 另检查自选目录内非安装器文件保留，以及 XAML、PRI、图标、.NET 与 WinUI 运行时齐全。正式包的发布、旧安装与资料库处理、重装及证据归档按[版本发布流程](../workflow/release.md)执行。签名方式见安装规格。

干净 Windows11 x64 离线测试必须记录系统版本、运行时预装状态和断网证据；只在已有运行时的 gigabit 断网启动不替代该项。此项尤其是独立瘦身 [PLAT-004](../specs/spike/platforms.md#plat-004-windows-组件包瘦身)的合入条件。

## 图库与层级

1. **导入／重启。** 依次导入四类来源，核对摘要与计数，重复导入不重复记录。退出重启，源、索引与合集仍存在。用来源重新扫描按钮核对可用状态。
2. **多创作者。** 将多创作者副本的 `海岛摄影/长岸` 改为 `海岛摄影/Summer`，核对首页先显示2名创作者；分别进入两位作者的 Summer，媒体数量3和1。方向键按可见网格选第二项，Space 逐层进入，Esc 返回并选中刚离开的子项；改变窗口宽度再测列数。单创作者来源直接显示专辑。[LIB-009、010](../specs/official/library.md)。
3. **真实重命名。** Enter 打开媒体／目录编辑，取消后再提交；双击打开的目录标题行内改名，点击外部提交，Esc 取消。核对扩展名保留、同名／无效名称／符号链接拒绝、已加入合集的媒体身份和次序不变。重扫和重启后路径一致。恢复副本名称后比较只读快照。[LIB-011、012](../specs/official/library.md)。
4. **三视图。** 图标、Finder式列表、画廊切换，检查小缩略图／名称／修改时间／大小／种类列及画廊更新。⌘1列表、⌘2画廊、⌘3图标，Windows用Ctrl。切换均保留选择。鼠标快速点不同媒体后立即Space，打开最后点击项。[BRW-001–003](../specs/official/browsing.md)。

## 独立预览

1. **图片。** JPEG、PNG、WebP、动画GIF；Mac HEIC，Windows记录系统解码结果。横竖图等比自适应，弱化相邻图；坏图显示错误且可切换。Space打开和关闭，分别用Space／Esc／关闭按钮退出均选中最后查看媒体。[PRE-001、007](../specs/official/preview.md)。
2. **方向与过渡。** 列表仅上下、画廊仅左右；两行且末行有空位的图标网格按实际行列移动，行端、边界和缺格不跳转。改变宽度再测。从缩略图大小／位置连续放大，关闭缩回最后媒体位置。原面板、侧栏和顶栏不移动；毛玻璃覆盖整个应用内容，背后控件不可操作。[PRE-008、009](../specs/official/preview.md)。
3. **顶栏。** 关闭在左、名称居中，四向按钮扁平且无边框，媒体占主要区域。双击文件名复制完整名称含后缀，切换媒体后再测，退出应用后仍可粘贴。[PRE-010](../specs/official/preview.md#pre-010-预览顶栏与媒体适配)。
4. **视频。** MP4／MOV画面、播放暂停、拖进度；未锁定时画布方向键切文件，进度条焦点接管微调。另用超过50秒的合成视频验证前后15秒按钮与边界，Enter锁定后Space播放／暂停、左右跳转、上下不切文件；再Enter解锁，Esc仍可退出并停止播放。音频输出实际听音单独记录，不由画面推断。[PRE-011](../specs/official/preview.md#pre-011-视频跳转与播放锁定)。

### 漫画双页与图片自动播放

1. 导入分别有六页和七页的合成专辑。在图片独立预览打开「漫画双页」。默认首页单独，第 2、3 页并排。切换「首页双页」后第 1、2 页并排。通过左右键和箭头正反翻页到边界，核对末页及减少动态效果。用 Esc 或 Space 退出并复查活动媒体选中。[PRE-003](../specs/official/preview.md#pre-003-漫画双页翻页)
2. 从第一张开始自动播放，观察默认 2 秒间隔。暂停、继续、停止，切换预设并输入自定义间隔；手动翻页可继续按所设间隔播放。复验单页和双页，核对末页停止。另在混排专辑手动切到视频，中途关闭预览并重开，核对自动播放停止。[PRE-012](../specs/official/preview.md#pre-012-图片自动播放)

### 视频作品索引与预览

1. 解压合成样例，从侧栏「源」添加 `iPreview-fixtures/视频作品`。从父目录选中 `album` 按 Space，或进入作品文件页后点「沉浸模式」。在 macOS 分别从卡片和作品页按 ⌘↩，核对都打开同一作品的总览。另在普通专辑按一次。也可直接把 `album` 作为来源导入。
2. 检查总览分区与窗口中轴对齐。左区的透明录像带盒为 9:16 竖式，盒脊与封面可辨。右区展示略错开的真实照片堆。两边略向中轴靠拢，常用窗宽各占半区面积约四成。悬停照片堆，触控板双指向左和向右各翻一张。按 Space 检查开盒、当前照片向前放大和其他照片缩小后退。用 `album-17` 在播放时按 Tab，核对极光轮廓从视频移到图片区。按左右翻图，按 Tab 切回视频来暂停或定位。
3. 在「完整结构」复验样张及多册，在 `full-with-stills` 播放期间打开 `2-broken.jpg`，观察另一边继续播放。检查两区键鼠焦点、窗口缩放、深浅外观与关闭动态效果。用 Esc 停播、回总览，再退出到图库。点击其他区域时入口按钮仍无残留边框。
4. 打开沉浸总览，在录像带焦点按方向键，焦点仍在录像带。按 Tab 切到照片再用左右键翻图，Shift+Tab 切回。进入双区时应默认控制视频。暂停后直接试左右方向键前进或后退 15 秒，再试时间轴微调。切到照片翻图后，核对视频仍停在同一位置。连续按两次 Esc，应先停播回总览，再退出到图库并恢复选中项。另试长按一次 Esc 和菜单打开时的 Esc。
5. 已导入旧来源先分别重扫、重启，核对旧结构、普通图片专辑及命名无关的作品归组。对照源文件快照。普通图片专辑仍以 Space 打开单媒体。[LIB-006](../specs/official/library.md#lib-006-两种视频作品结构) · [PRE-004](../specs/official/preview.md#pre-004-视频作品的沉浸模式)
6. 用颜色不同的官方样张、影片帧和普通图片核对录像带盒封面。完整结构从样张目录取图，简化结构从根目录的样张取图；视频同层的普通图片不参与封面选择。去掉或损坏样张后，从主视频取帧。核对盒下显示当前主视频的文件名及扩展名，长文件名保持单行，悬停可查看全名。点击开盒，核对显示主视频。已导入的索引可直接复验。

## 搜索

1. ⌘F／Ctrl+F打开当前范围，⇧⌘F／Ctrl+Shift+F或侧栏放大镜打开全局，光标直接在居中框；右上角无常驻搜索。分别在源、创作者、专辑、合集验证范围；⌘0／Ctrl+0来回切换当前／全局，保留关键词、精确及分类。
2. 默认两者，⌘1／Ctrl+1仅文件，⌘2／Ctrl+2仅目录，重复按当前类别恢复两者。选择结果Enter进入目录或文件所在目录，Space预览，退出后结果仍选中最后查看项。
3. 输入 `@` 单字符不激活；再空格后触发字符消失、精确标签出现。`lantern_02`精确命中文件主名，`lantern_02.png`精确指定后缀；目录 `a夜景` 命中规范化的 `Ａ夜景`。带普通点号文件名保持完整主名语义。Esc先取消精确并保留词，再Esc关闭面板，回归全角／输入法。
4. 模糊搜索 `bj`、`lvxing`、`sumer` 验证首字母、拼音和容错。只搜文件时目录词不跨入文件结果，路径及分类可辨。
5. 搜索单创作者来源根、多创作者来源中的创作者及其同名专辑，核对图标、类别和父路径。按目录／文件筛选核对类别和排序，用 Enter 定位所选创作者或专辑。

以 [SRCH-001–003](../specs/official/search.md)为准。搜索中的分类快捷键不得改变背后图库布局，重命名和预览应保留自身键位。

## 合集与离线

1. 创建合集，空图标加号进入选片器，跨两源选图片与视频、全选某专辑再撤回一项；底部胶片条按选择顺序暂存。确认后去重追加，再开时已有／离线项不可选；取消保持原引用。
2. 双击标题改名，外部点击／Enter提交、Esc取消。点有框「调整」，未选项无默认白圈，单击才在右下显示勾选；跨布局保持数量与状态，取消或离开退出。
3. 仅调整态按住拖动排序，无常驻手柄；检查插入提示、滚动后投放、取消顺序不变。移除多项引用后，剩余相对顺序、另一合集与真实文件不变。两类页面均无多余 `···` 和真实文件单项加入合集入口。
4. 退出重启核对名称、引用与次序。临时改名样例源并重扫，离线标记和引用保留；恢复名称重扫后可播，位置不变。
5. 创建两个共享跨来源成员的合集。点删除图标，核对确认界面的名称并取消，原合集及选中项保留。再次打开并确认，界面回到媒体库且侧栏移除该合集。重启核对剩余合集和次序，随后用同名新建并再次删除，核对源文件快照。

对应 [ALB-001、003–006](../specs/official/virtual-albums.md)。

## 外观与布局

两端对照同源／同合集、相近窗口大小核对侧栏、标题、摘要、操作区、列表列与媒体网格。Mac 侧栏按钮在红绿灯右侧，导入与主题另成一组。展开、收起和调整侧栏宽度时核对两个按钮组的位置、间隔与过渡。侧栏切换、导入、搜索和合集加号均有悬停反馈，概览玻璃胶囊的当前项中性圆底、其余项柔和悬停。源结构图标区分文件夹／单人／多人，离线可见。

Mac26+原生玻璃、15系统材质，Windows保留原生窗框并使用系统材质回退。按实际环境切换浅深外观、减少动态效果、Windows高对比和透明效果；不能测试的组合明确记为未验证。Finder／Dock及Windows资源管理器／任务栏核对最终白底星云轨道图标。见 [UI-001–006](../specs/official/appearance.md)。

### 主题选择与恢复

在 macOS 标题栏核对三档主题的显示器、太阳、月亮图标，以及悬停时斜线分隔的半个太阳和半个月亮。导入和主题按钮的点击区域同为 26 × 26 点，主题图标切换时按边缘仍在同一范围内生效。在已悬停时按 Option，或按住 Option 再移入，核对菜单打开、当前选中状态与「跟随系统」「浅色」「深色」三种选项及对应图标。分别在系统浅色、深色时启用「跟随系统」，连续普通点击三次，均应依次选中「浅色」「深色」「跟随系统」。Windows 从侧栏「媒体库」行打开主题菜单。

双端依次检查三种模式即时生效、重启恢复与系统明暗切换。自动模式随系统外观调整，两种显式模式保持所选外观。

在浅色和深色分别打开搜索、图片与视频预览、合集选片器，核对标签、文字、控件及原生标题栏。用 macOS 15 的系统材质和 macOS 26 及以上的玻璃检查可读性。Windows 关闭透明效果、切换系统对比度主题后复验。分别开启 macOS 减少动态效果和关闭 Windows 动画，检查侧栏和预览仍遵循相应设置。见 [UI-007](../specs/official/appearance.md#ui-007-主题选择与恢复)。

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
