# FolderTerm

FolderTerm 是一个 macOS 原生工具：在 Finder 工具栏点击图标，在当前文件夹打开终端。主 App 始终显示中文配置界面；终端动作由内置的独立工具栏入口执行。

当前源码版本：**0.4.0**。此仓库只包含源码、构建脚本和测试，不提供已签名或公证的安装包。

## 构建

需要 macOS、Xcode Command Line Tools 和 Python 3，无额外第三方依赖。

```sh
./scripts/test.sh
./scripts/build.sh
python3 tests/test_entrypoint_artifacts.py
```

产物位于 `build/0.4.0/FolderTerm.app`。构建脚本只生成本机架构的 App，不安装、不启动、不修改 Finder 或系统权限。默认使用本地临时签名；这不是 Developer ID 签名或公证发行。

部署目标为 macOS 12；当前验证平台为 Apple Silicon、macOS 26.7。Intel、最低系统版本和 iTerm2 尚未实测。

## 使用

1. 将整个 `FolderTerm.app` 放到固定位置，保留内置 helper。
2. 打开主 App，选择终端、打开方式和命令，然后保存设置。
3. 点击 **添加到 Finder 工具栏**。已有自身入口时不会重复添加。
4. 查看 Finder；旧窗口可能缓存布局，可新开一个 Finder 窗口检查。
5. 在实际文件夹中点击工具栏图标，才会打开终端。

也可点击“显示 Finder 工具栏入口…”找到 `FolderTermToolbar.app`，按住 Command 将它拖到工具栏。不要拖主 App：主 App 只打开设置。移动整个 App 后，如原有入口无法解析，需重新添加。

Terminal 支持新窗口，iTerm2 支持新窗口和新标签页。工具栏 helper 需要 macOS 允许其控制 Finder 和所选终端。主配置 App 没有 Apple Events 权限和终端自动化实现。无需辅助功能、全磁盘访问或全盘 FinderSync。

## 命令与目录

默认命令为 `cd -- %PATH% && clear && pwd`。保留 `cd -- %PATH%` 前缀，只用一次占位符，不给占位符额外加引号；后续命令以 ` && ` 或 `; ` 接续。路径按 shell 单引号规则转义。路径和模板中的 ASCII 控制字符与 DEL 均被拒绝，包括换行、CR、Tab、ESC 和 Ctrl-U。

自定义命令会以当前用户身份执行，请只保存信任的命令。普通 Finder 窗口优先使用真实文件夹；最近使用或搜索等虚拟位置只有在明确单选一个有效项目时才尝试该项目目录，否则报错，不默认跳到主目录。

两入口共用用户 Application Support 目录下 `app.folderterm.FolderTerm/settings.json`，原子保存并设置为仅当前用户可读写。

## 工具栏兼容性与恢复边界

一键添加使用 Finder 的私有工具栏持久化结构与旧 Alias 兼容 API，未来系统可能改变。程序只修改当前用户 `com.apple.finder` 的 `NSToolbar Configuration Browser` 一个键，保留其他项目、记录、顺序与未知字段，按解析后的真实入口身份去重。

写入前保存 before/after 备份，临近写入时重新检查快照，同步后回读。CFPreferences 不提供跨进程 CAS，因此仍存在很短的并发窗口；结果未知时暂停后续写入，不自动重试、恢复或重启 Finder。备份存于应用的 Application Support 子目录 `ToolbarPlans`，不在仓库内。

事务层支持在当前完整配置严格匹配备份 after 时恢复 before。Finder 可能规范化新增引用，届时原 after 不再匹配；不能直接用旧快照覆盖当前布局。此版本没有配置恢复界面，手动恢复前需重新核对完整状态。

## 验证范围

308 项 Swift 断言、6 项 Python 资源检查和4项构建产物检查覆盖路径安全、入口分离、共享设置、增量布局、备份恢复、冲突和未知结果停止。测试只使用项目内临时文件与替身，不写真实 Finder 配置或启动终端。[测试说明](docs/TESTING.md)

工具栏添加、重复添加和原有项目保留在当前系统上经过交互验证。终端实际 cwd、helper 系统权限提示、多窗口与搜索视图的完整集成，以及 iTerm2 尚未全部验收。

## 许可证

项目目前未指定开源许可证；本次公开源码没有新增许可证授权。
