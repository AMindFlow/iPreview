# LibVLC 播放运行时

iPreview 动态加载 VideoLAN LibVLC 3.0.24。LibVLC 核心与随包选择的 VLC 播放模块适用 GNU LGPL 2.1 或后续版本。版权由 VideoLAN 和各源文件列明的贡献者持有。许可证全文见同目录 `COPYING.LIB`，第三方保留声明见 `THIRD-PARTY-NOTICES.txt`。允许为自身使用修改库，以及为调试这些修改进行逆向工程。[VideoLAN 分发说明](https://docs.videolan.me/vlc-user/desktop/3.0/en/support/faq/legalconcerns.html) · [GNU LGPL 2.1](https://www.gnu.org/licenses/old-licenses/lgpl-2.1.en.html)

## 对应源码与构建配置

- VLC 3.0.24 对应提交为 `6de05adcbaf2e8b85fe86aad4169393098628119`。iPreview 的 GitHub Release 随标准安装包归档对应的 VLC 源码、相关 contrib 源码及校验表。上游也提供相同归档。具体二进制与源码归档校验值、平台构建参数见 `BUILD-CONFIG.txt`，已选文件见 `runtime-files.sha256`。[iPreview Release](https://github.com/AMindFlow/iPreview/releases) · [VideoLAN 源码包](https://download.videolan.org/videolan/vlc/3.0.24/vlc-3.0.24.tar.xz)
- 源码包的 `extras/package/macosx`、`extras/package/win32` 和 `contrib/src` 包含平台构建脚本、第三方归档校验、配置与补丁。官方构建以同一动态播放插件合并 FFmpeg Libavcodec 和 Libavformat。FFmpeg 8.1.2 适用 LGPL 2.1 或后续版本。配方位于 `contrib/src/ffmpeg/rules.mak`。[FFmpeg 8.1.2 对应源码](https://ffmpeg.org/releases/ffmpeg-8.1.2.tar.xz) · [FFmpeg 许可](https://ffmpeg.org/legal.html)
- Matroska 拆封使用 LGPL 2.1 的 libmatroska 1.7.2 和 libebml 1.4.6。Opus 1.6.1 使用 Xiph.Org 的 BSD 风格许可。mpg123 1.33.6 使用 LGPL 2.1。各版本及原始许可证在对应源码及 VLC 的 `contrib/src` 配方中。[libmatroska](https://dl.matroska.org/downloads/libmatroska/libmatroska-1.7.2.tar.xz) · [libebml](https://dl.matroska.org/downloads/libebml/libebml-1.4.6.tar.xz) · [Opus](https://ftp.osuosl.org/pub/xiph/releases/opus/opus-1.6.1.tar.gz) · [mpg123](https://downloads.sourceforge.net/project/mpg123/mpg123/1.33.6/mpg123-1.33.6.tar.bz2)

- 传递依赖的固定版本由源码包中各 `contrib/src/*/SHA512SUMS` 记录。VLC 构建配方展开后使用 libgsm 1.0.13、OpenJPEG 2.5.4、zlib 1.3.2、UTF CPP 3.2.5 以及 LAME 3.100。macOS OpenGL 输出包含 LGPL 2.1 或后续版本的 libplacebo 0.2.1。Windows 配方另包含 MinGW-w64 14.0.0 的线程库和 NLS 组件。对应条目含原始源码入口及构建补丁。[contrib 配方及校验](https://github.com/videolan/vlc/tree/6de05adcbaf2e8b85fe86aad4169393098628119/contrib/src)

## 使用修改后的兼容运行时

退出 iPreview，在隔离安装副本保留原运行时，把 ABI 兼容的替代库和插件放进同一目录再运行。macOS 库路径为应用内 `Contents/Frameworks/LibVLC`，许可证与构建信息位于 `Contents/Resources/LibVLC`。Windows 的库和许可证位于安装目录的 `LibVLC`。需要重新签名测试副本时，可在 macOS 上使用本地开发签名。标准安装器覆盖升级会恢复发行版随附的运行时文件。
