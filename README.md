# 一级市场情绪指数

Windows桌面工具：下载DM一级市场招标附件，经Excel或WPS中的Wind插件补全条款，提交DQ批量定价，按有效样本生成情绪指数、五页数据表、文字和图片。

## 下载运行

从 [GitHub 最新 Release](https://github.com/LeonLiangR/bond-sentiment-automation/releases/latest) 的 Assets 下载 Windows x64 免安装 ZIP。完整解压后双击“一级市场情绪指数.exe”。不要下载 Source code 代替应用包，也不能只复制 exe。无需另装 Python、Node 或 Codex。

需要Windows 10/11 x64、.NET Framework 4.8、DM、DQ，以及Excel或WPS和对应版本的Wind插件。账号需有数据、DQ批量试算和下载权限。首次自动检测软件位置，可在设置里选择引擎并保存；只选Excel时不要求安装WPS。

选择DM附件所属交易日、输出目录，点击生成。原已开启的软件保留；程序核对独立表格实例及进程归属，只隐藏、关闭自己新增的后台进程。运行期间避免同时改动DQ批量试算方案。

## 输出与计算

工作簿包含“当日报告、样本及逐券得分、DQ结果、DM原始数据、历史底表”五页，另有TXT、PNG及本地过程数据。中文楷体、英文数字Times New Roman；第一张表附计算口径。

样本筛选四类券种，剔除空白和零票息。提交、返回按独立ID和全部条款校验，定价失败、空值及日期不一致不会混入有效得分。利差=(票面利率－DQ区间中枢)×100BP；逐券分档得分及新旧指数见 `src/core.mjs` 和报告公式。

0.5.2补充会话等待、下载重试、进程空值保护、COM忙状态重试、Wind完成状态判断及DM原始字段类型保护。评分与指数公式保持不变。0.5.1已修正环比文字：变化显示为0.00点时写“较上一有效统计日基本持平”；评分与指数计算保持不变。

## 测试范围

WPS已做实际取数和报告回放验证。Excel 16.0及Excel版Wind已做独立隐藏实例取数、基础公式、保存重开和已有工作簿保护的实机验证。Excel使用自动计算和完整重算，并等待有效数据稳定，Fetching及Excel错误不会作为成功结果输出。**Excel完整五页报表及DM/DQ联动仍待实机验收**；不能据此保证所有客户端版本都可运行。按 [Excel测试说明](docs/EXCEL-TESTING.md) 完成验收。

程序调用已登录客户端的本机会话及内部接口；这不是DM或DQ官方通用SDK。客户端更新、账户权限或网络变化可能需要适配。登录及验证码在原软件完成，本工具不保存密码。

## 数据与配置

公开源码和 Release 不包含真实样本、历史汇报、账号、会话或本机配置。已有用户解压新版后仍使用本机历史；新电脑可以从团队内部渠道取得 JSON，在“历史交接”中导入。导入只补缺失日期，保留本机同日记录；回溯不含未来日期，历史不参与当日指数计算。本地配置与历史保存在 `%LOCALAPPDATA%/BondSentimentAutomation`。业务数据写入所选输出目录，程序不会自动上传。反馈运行日志前请移除本机路径和业务数据。

## 从源码构建

0.5.7增加界面中的“历史交接”：月末导出完整历史JSON文件，下月接手同事导入，自动补齐缺失日期；重复导入不重复记账，同日冲突保留本机记录并提示。导入前自动备份已有历史，不含软件配置、账号和逐券明细。历史只用于绘图及历史对照，不改变当日指数。详见[月度历史交接](docs/HISTORY-HANDOVER.md)。

需要Windows、Node.js 24或更新版本、.NET Framework 4.8开发环境。项目不依赖npm包。

```powershell
node --test tests/core.test.mjs tests/office-config.test.mjs tests/narrative.test.mjs
powershell -NoProfile -ExecutionPolicy Bypass -File tests/office-contract.ps1 -OutputDirectory .\test-results\contract
powershell -NoProfile -ExecutionPolicy Bypass -File src/package-portable.ps1 -NodeBinDirectory 'C:\Program Files\nodejs' -PublicRelease
```

输出在 `dist`，包含运行环境、字体及对应第三方许可。`release-files.json` 明确源码及运行时文件范围；构建要求目标目录为空，模板作者元数据会中性化。发布前可运行 `python tools/privacy_guard.py --root <发布目录>`，检查暂存区用 `--staged`，检查全部提交用 `--history`。扫描不能代替人工审阅。

0.5.3口径澄清：六档权重仅用于老指数（按只数累加）；新指数保留原斜坡逐券得分，±3BP均得0分，E15=50+25×当日平均得分。老指数统计时，−3BP归入低估值3—5BP，＋3BP归入高估值3—5BP；平估值档为−3<x<3。

维护者提交版本更新后，推送与 `package.json` 一致的版本标签（例如 `v0.5.8`）。GitHub Actions 会构建公开 ZIP、上传校验文件并发布 Release。日常源码推送不会发布版本。

内部交接如需随包预置已授权的历史，可以改用 `-HistorySeedFile`。该选项与 `-PublicRelease` 互斥，生成带 `-internal` 后缀的 ZIP，仅限团队内部使用。

0.5.4修复Excel.Application名称重定向：Excel改用固定CLSID激活，保留真实进程和安装路径核验，不改系统注册表。本次Excel启动修复尚需同事电脑实机验收。

0.5.5进一步绕过被重定向的Excel固定CLSID：直接启动选定EXCEL.EXE，用/x创建独立进程，从其EXCEL7窗口取得原生对象模型并验证进程身份。激活前登记新进程，绑定失败时清理本轮进程，已有应用不受影响。增加ExcelSelfTest.cmd用于不依赖DM/DQ的基础Excel诊断。Windows原生窗口模拟服务已验证绑定机制；真实Excel/Wind仍需同事实机验证。
