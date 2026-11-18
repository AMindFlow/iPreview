# 双端验收步骤

这是可重复执行的验收入口；各版本实际执行了哪些项目、提交与产物 SHA-256、系统版本和未验证项，以[一期登记册](releases/0.1.0.md)及对应版本报告为准。用同一最终源码、相同合成样例在本机 Apple Silicon Mac 与 gigabit Windows11 x64 验证，不把旧提交的结果冒充新包结果。

## 样例和保护边界

生成端需要 Python3、带 libx264 的 FFmpeg、cwebp 和 macOS sips；验收端只需解压。运行：

```sh
python3 scripts/generate-fixtures.py /tmp/iPreview-fixtures.zip
```

| 来源 | 预期导入结果 |
| --- | --- |
| 沿海创作者 | 单创作者、2个专辑、8个媒体（含坏图）；隐藏 PNG 和 TXT 忽略。 |
| 多创作者 | 2名创作者及各自专辑、4个媒体。 |
| 层级歧义 | 显示单创作者／多创作者摘要选择，任一选择索引对应分支的1个媒体。 |
| 直属媒体 | 单个专辑、2个媒体。 |

更名和离线测试仅操作可丢弃副本。先记录源文件快照；结束时恢复样例目录名，再比较路径、大小、修改时间与 SHA-256。集合引用操作不应写入或删除真实文件。

## 安装与恢复

按 [PLAT-005](../specs/official/platforms.md#plat-005-首版标准安装包)验证：Mac 挂载 DMG、检查应用和 Applications 入口、拖入安装并从安装位置打开；Windows 运行 EXE，确认语言／目录／进度／完成及开始菜单、系统卸载项。安装目录选专用应用目录，覆盖现有安装前退出应用。

用隔离测试资料库检查安装、同版本覆盖升级、卸载后数据保留，再安装后索引与合集恢复。Windows 另检查自选目录内非安装器文件保留，XAML、PRI、图标、.NET及WinUI运行时齐全。最终正常启动核对原用户库可读。首版签名限制见安装规格；不绕过系统安全提示来声称已通过认证。

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

## 搜索

1. ⌘F／Ctrl+F打开当前范围，⇧⌘F／Ctrl+Shift+F或侧栏放大镜打开全局，光标直接在居中框；右上角无常驻搜索。分别在源、创作者、专辑、合集验证范围；⌘0／Ctrl+0来回切换当前／全局，保留关键词、精确及分类。
2. 默认两者，⌘1／Ctrl+1仅文件，⌘2／Ctrl+2仅目录，重复按当前类别恢复两者。选择结果Enter进入目录或文件所在目录，Space预览，退出后结果仍选中最后查看项。
3. 输入 `@` 单字符不激活；再空格后触发字符消失、精确标签出现。`lantern_02`精确命中文件主名，`lantern_02.png`精确指定后缀；目录 `a夜景` 命中规范化的 `Ａ夜景`。带普通点号文件名保持完整主名语义。Esc先取消精确并保留词，再Esc关闭面板，回归全角／输入法。
4. 模糊搜索 `bj`、`lvxing`、`sumer` 验证首字母、拼音和容错。只搜文件时目录词不跨入文件结果，路径及分类可辨。

以 [SRCH-001、002](../specs/official/search.md)为准。搜索中的分类快捷键不得改变背后图库布局，重命名和预览应保留自身键位。

## 合集与离线

1. 创建合集，空图标加号进入选片器，跨两源选图片与视频、全选某专辑再撤回一项；底部胶片条按选择顺序暂存。确认后去重追加，再开时已有／离线项不可选；取消保持原引用。
2. 双击标题改名，外部点击／Enter提交、Esc取消。点有框「调整」，未选项无默认白圈，单击才在右下显示勾选；跨布局保持数量与状态，取消或离开退出。
3. 仅调整态按住拖动排序，无常驻手柄；检查插入提示、滚动后投放、取消顺序不变。移除多项引用后，剩余相对顺序、另一合集与真实文件不变。两类页面均无多余 `···` 和真实文件单项加入合集入口。
4. 退出重启核对名称、引用与次序。临时改名样例源并重扫，离线标记和引用保留；恢复名称重扫后可播，位置不变。

对应 [ALB-001、004–006](../specs/official/virtual-albums.md)。

## 外观与布局

两端对照同源／同合集、相近窗口大小核对侧栏、标题、摘要、操作区、列表列与媒体网格。Mac 两标题栏按钮与红绿灯同高、展开时靠侧栏右侧、收起仍在红绿灯右侧；紧凑无常驻圆底，源旁无重复加号。收放顺滑且图标互换。四个入口（侧栏切换、导入、搜索、合集加号）均有 hover；概览玻璃胶囊的当前项中性圆底、其余项柔和 hover。源结构图标区分文件夹／单人／多人，离线可见。

Mac26+原生玻璃、15系统材质，Windows保留原生窗框并使用系统材质回退。按实际环境切换浅深外观、减少动态效果、Windows高对比和透明效果；不能测试的组合明确记为未验证。Finder／Dock及Windows资源管理器／任务栏核对最终白底星云轨道图标。见 [UI-001–006](../specs/official/appearance.md)。

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
