# Excel电脑测试

从Releases下载Windows x64测试包，完整解压到本机目录，双击“一级市场情绪指数.exe”。不需要安装Python、Node或Codex。

准备Windows 10/11 64位、.NET Framework 4.8，以及DM、DQ、Microsoft Excel和Excel版Wind插件。Excel模式不要求安装WPS。各账号需有相应数据、批量试算及下载权限。

2026-11-15已在Excel 16.0及Excel版Wind插件上验证独立隐藏实例取数、基础公式、保存重开及原有工作簿保护。Excel取数使用自动计算和完整重算，所有返回字段排除Fetching及Excel错误后连续两次一致才输出；默认等待120秒，超时报告样本ID及字段，不输出未完成数据。此验证不包含本机缺失的DM/DQ，也不代表完整五页报表已实机验收。

无需DM/DQ时，可只验收Excel/Wind。准备settings.json（spreadsheetEngine=excel、excelExe为本机Excel绝对路径，dmExe和dqExe可填不存在的占位路径）以及input.json（样本数组，每项含sampleId和债券简称name），执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/wind-wait.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests/native-office-worker.ps1 -SettingsFile <settings.json路径> -InputFile <input.json路径> -OutputDirectory <测试输出目录> -TimeoutSeconds 150
```

加-SkipWind可只测试基础Excel。native-verification.json的passed、windTested及preExistingWorkbookPreserved应为true，并核对wind-live.json中的逐项结果。

1. 先确认原客户端和Excel里的Wind函数能正常取数。
2. 首次启动自动检测路径。设置中选Microsoft Excel，核对EXCEL.EXE、DM和DQ位置并保存。重新打开后应保持选择，不反复检测。
3. 选择DM附件所属日期，并确保DQ当前估值日期与之相同。程序不使用最新估值冒充历史估值。
4. 选择输出目录，生成报告。观察DM、Wind、DQ和报表四阶段及运行记录。
5. 核对五页Excel、文字和PNG图片，第一页有计算口径说明。检查逐券票息、中枢、BP利差及有效样本数量，指数应与Excel公式一致。
6. 使用一个单独的测试工作簿检查保留行为：运行前在Excel中输入一个标记值，运行后确认原窗口、工作簿和标记值仍保留。程序只关闭自己新建的实例。
7. 再检查停止、日期不一致或未登录场景：应提示原因、执行新增后台清理，且最近成功报告仍能打开。

指数变化显示为0.00点时，文字应直接写“较上一有效统计日基本持平”。首次无历史记录时不写环比。

首次使用的历史图只包含已在这台机器积累的数据，测试包不带原开发机器的历史和样本。安装路径、历史和最近结果保存在当前用户本地配置目录；账号密码由原软件管理，工具不保存密码。

如遇问题，先查看当次过程数据中的运行日志及final-status.json。它们可能包含本机路径、样本和接口返回，请检查并去除敏感内容后再自行反馈。程序不会自动上传这些文件。
