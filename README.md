# 一级市场情绪指数

Windows桌面工具：下载DM一级市场招标附件，经Excel或WPS中的Wind插件补全条款，提交DQ批量定价，按有效样本生成情绪指数、五页数据表、文字和图片。

## 下载运行

从本仓库 **Releases** 下载 `BondSentiment-0.5.1-win-x64.zip`，完整解压后双击“一级市场情绪指数.exe”。不要下载Source code代替应用包，也不能只复制exe。无需另装Python、Node或Codex。

需要Windows 10/11 x64、.NET Framework 4.8、DM、DQ，以及Excel或WPS和对应版本的Wind插件。账号需有数据、DQ批量试算和下载权限。首次自动检测软件位置，可在设置里选择引擎并保存；只选Excel时不要求安装WPS。

选择DM附件所属交易日、输出目录，点击生成。原已开启的软件保留；程序核对独立表格实例及进程归属，只隐藏、关闭自己新增的后台进程。运行期间避免同时改动DQ批量试算方案。

## 输出与计算

工作簿包含“当日报告、样本及逐券得分、DQ结果、DM原始数据、历史底表”五页，另有TXT、PNG及本地过程数据。中文楷体、英文数字Times New Roman；第一张表附计算口径。

样本筛选四类券种，剔除空白和零票息。提交、返回按独立ID和全部条款校验，定价失败、空值及日期不一致不会混入有效得分。利差=(票面利率－DQ区间中枢)×100BP；逐券斜坡得分及新旧指数见 `src/core.mjs` 和报告公式。

0.5.1仅修正环比文字：变化显示为0.00点时写“较上一有效统计日基本持平”；评分与指数计算保持不变。

## 测试范围

WPS已做实际取数和报告回放验证。Excel分支已完成配置与模拟契约检查，**真实Excel、Excel版Wind与报表输出尚待Excel电脑验收**；不能据此保证所有客户端版本都可运行。按 [Excel测试说明](docs/EXCEL-TESTING.md) 完成验收。

程序调用已登录客户端的本机会话及内部接口；这不是DM或DQ官方通用SDK。客户端更新、账户权限或网络变化可能需要适配。登录及验证码在原软件完成，本工具不保存密码。

## 数据与配置

源码和测试包仅含空白模板、程序及随附许可，不含真实样本、历史汇报、账号、会话或网络配置。首次运行从空历史开始，本地安装路径、历史及最近成功结果保存在 `%LOCALAPPDATA%/BondSentimentAutomation`。业务数据写入所选输出目录，程序不会自动上传。反馈运行日志前请检查其中的本机路径和业务数据。

## 从源码构建

需要Windows、Node.js 24或更新版本、.NET Framework 4.8开发环境。项目不依赖npm包。

```powershell
node --test tests/core.test.mjs tests/office-config.test.mjs tests/narrative.test.mjs
powershell -NoProfile -ExecutionPolicy Bypass -File tests/office-contract.ps1 -OutputDirectory .\test-results\contract
powershell -NoProfile -ExecutionPolicy Bypass -File src/package-portable.ps1 -NodeBinDirectory 'C:\Program Files\nodejs'
```

输出在 `dist`，包含运行环境、字体及对应第三方许可。`release-files.json` 明确源码及运行时文件范围；构建要求目标目录为空，模板作者元数据会中性化。发布前可运行 `python tools/privacy_guard.py --root <发布目录>`，检查暂存区用 `--staged`，检查全部提交用 `--history`。扫描不能代替人工审阅。
