# 声刻 · Shengke

Native macOS audio editor built with SwiftUI, AppKit and AVFoundation. Open a file, edit its waveform, listen and save. **Version 0.4.0 — development preview.**

声刻是一款 Swift 原生 Mac 单文件音频编辑器。直接从 Finder 打开音频，完成剪辑和试听后保存；不使用工程文件。

## 使用方式

在 Finder 右键音频 →「打开方式」→「声刻」，或将文件拖入窗口 / Dock 图标。顶部保留三个文件动作：

1. **写入并覆盖原文件**（⌘S）：按源文件编码保存完整编辑结果。
2. **保存为副本**（⇧⌘S）：按源文件编码保存完整副本，源文件不变。
3. **删除源文件并保存为 WAV**：原目录写入完整 WAV 24-bit，回读验证通过后将源文件移入废纸篓。

三个按钮始终保存完整文件。需要独立片段时，选中后按住选区内部拖到 Finder 文件夹，输出 WAV **48 kHz / 24-bit / 立体声**，首尾各加 **15 ms** 淡入淡出；短片段自动缩短淡化长度。

## 编辑与交互

- 波形总览、样本级显示、时间/样本精确选区、剪切、复制、粘贴、删除、裁剪、撤销与重做。
- **滚轮以指针下的时间点为中心横向缩放**；Shift＋滚轮或横向滚动平移。
- 选区中上方的小旋钮用滚轮调音量，点击别处完成；边界以约 15 ms 平滑衔接，整次调节可一次撤销。
- 空格播放/停止；P 或逗号暂停/继续；Shift＋空格从光标到末尾。
- 淡入淡出、峰值归一化及预听、静音、倒放、反相和本次编辑内的临时标记。
- 双击标题栏最大化/还原；左右声道峰值、监听音量与静音。
- 右上角「！」记录使用建议，自动保存到 `~/Library/Application Support/WaveStudio/使用建议.md`。升级只更新版本号，保留旧建议；拖入 Markdown 可追加正文。该文件不随源码发布，也不会自动上传。

[详细使用说明](docs/使用说明.md) · [验证范围与已知限制](docs/VERIFICATION.md) · [参与开发](CONTRIBUTING.md)

## 构建

需要 macOS、Xcode 或 Apple Command Line Tools、Python 3。部署目标为 macOS 14；实际验证环境是 Apple Silicon / macOS 27.2.1 / Swift 6.4.2，其他组合尚未逐一验证。

```sh
git clone https://github.com/490003183-glitch/shengke.git
cd shengke
./scripts/build-app.sh
```

构建输出为 `dist/声刻.app`，使用本机 ad-hoc 签名，未经过 Apple 公证。LAME 3.100 的原始源码压缩包随仓库提供；首次构建校验 SHA-256、应用随附补丁并编译动态库，无需外装系统编解码器。

单独运行检查前先构建 LAME：

```sh
./scripts/build-lame.sh
swift run --build-system native CoreChecks
swift run --build-system native WorkflowChecks
```

`WorkflowChecks` 使用实际播放引擎并将监听静音，需要可用的系统音频输出设备。CI 只运行应用构建与核心检查，设备/GUI 交互需在本机验证。SwiftPM native 后端已被标记弃用，未来工具链升级时需复核构建选项。

## 当前限制

- 单/双声道联动编辑；粘贴要求采样率和声道相同。内部处理为 Float32。
- MP3/AAC 保存会重新编码；VBR 按原平均码率处理，不重现原编码器全部参数。
- **尚不保留原标签、封面、BWF 信息或文件内标记。** 源编码保存不等于元数据保真。
- 选区、缩放、撤销和临时标记只在本次编辑有效；无崩溃恢复。
- 跨窗口拖放的 Finder 落盘尚未完成 GUI 验收，文件承诺写入回调和输出格式/淡化已通过自动检查。
- 真实设备录音、主观音质和无缝循环未验收；多文档、独立声道编辑、跨格式粘贴、设备选择、EQ、压缩、变调变速、AU 插件尚未完成。
- 早期 60 分钟合成立体声测试峰值 RSS 约 1.33 GiB，大文件内存仍需优化。

## 源码结构

| 路径 | 内容 |
| --- | --- |
| `Sources/AudioCore/` | PCM 缓存、片段编辑、历史、峰值、编码与保存安全、选区增益/片段输出、建议存储 |
| `Sources/WaveStudio/` | SwiftUI/AppKit 界面、文件工作流、播放录音、波形、拖放、键盘与窗口 |
| `Tests/` | 自有合成信号的核心检查与实际编辑模型检查 |
| `Resources/` | 应用配置与独立绘制的图标 |
| `ThirdParty/lame/` | 上游源代码压缩包、许可、补丁及依赖说明 |
| `scripts/` | 构建脚本与图标生成器 |

本地开发台账、参考软件说明书/网页快照、测试音频、构建缓存、机器路径日志和个人使用建议均不包含在公开仓库中。

## 许可

项目原创代码和资源使用 [MIT License](LICENSE)。LAME 保留其 GNU Library General Public License v2 或更高版本；完整许可、对应源代码与补丁随附，见 [NOTICE](NOTICE.md) 和 [依赖说明](ThirdParty/lame/README.md)。

本项目独立实现，不隶属于 Felt Tip，也未获其背书。参考软件的手册、截图、图标和源代码不随仓库发布。
