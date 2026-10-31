# 构建与测试

```sh
./scripts/test.sh
./scripts/build.sh
python3 tests/test_entrypoint_artifacts.py
```

`test.sh` 运行6项Python资源检查和308项原生Swift断言：145项核心/入口/设置，163项工具栏增量/引用/备份/事务/适配器。Shell测试只执行受控printf；自定义命令不在测试中执行。

工具栏单元测试使用内存配置和注入的同步/写入替身；文件测试限制在build/test-artifacts中。测试不写真实Finder偏好，不启动配置App/helper/终端，不申请系统权限。

`build.sh` 编译主App和独立helper、生成图标、先签helper再签主包。Finder/Terminal AppleScript仅编译，未执行。iTerm2字典仅在明确设置VALIDATE_ITERM=1时编译，需先安装iTerm2。

构建后的4项产物检查验证主App无自动化能力、只有helper包含脚本与权限、没有外部URL命令入口，以及移动到包含中文/空格/引号的路径后结构和签名有效。可用FOLDERTERM_APP_PATH指定其他构建路径。

旧Alias兼容API会产生已知弃用警告。某些受限执行环境不能完成图标打包或原子文件写入；应在正常本机构建环境运行，不要改变系统保护以绕过限制。

这些自动化检查不证明真实终端cwd、权限交互、多窗口/搜索视图、iTerm2、Intel或最低系统版本已经通过。
