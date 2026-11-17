# 键盘媒体预览

## PRE-001 图片与视频预览

- **要求** 选中媒体后用 Space 打开预览，方向键切换条目，Esc 停止播放并还原选中项。图片等比适配，暗背景上呈现弱化相邻图片。两端以系统框架播放 H.264/AAC MP4 和 MOV，并提供播放、暂停和进度控制。进度条焦点接管方向键微调。单文件失败可见，继续切换可用媒体。
- **来源** [需求 #1](https://github.com/AMindFlow/iPreview/issues/1)
- **验收** 两端运行相同图片和视频样例，覆盖键盘导航、焦点、进度拖动、损坏文件和原媒体只读。JPEG、PNG、WebP、GIF 为双端格式，macOS 支持 HEIC，Windows 由系统 HEIC 解码器决定。

## 设计决定

- macOS 使用 AVPlayer，Windows 使用 MediaPlayerElement。实际媒体暴露格式缺口时，优先用对应样例验证 LibVLC 双端嵌入、打包和许可证。libmpv 是备选，FFprobe 可用于元信息读取。新增随包分发的生产依赖需要批准，按具体二进制及组件核对许可与 codec 专利。
