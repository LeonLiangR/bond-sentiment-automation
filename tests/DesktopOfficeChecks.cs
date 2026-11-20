using System;
using System.Collections.Generic;
using System.IO;
using SentimentDesktop;
static class DesktopOfficeChecks {
    static void Require(bool value, string name) { if (!value) throw new Exception(name); }
    static void RequirePathError(string key, string input, string expected) {
        try { DesktopSettings.ResolveExecutable(key, input); }
        catch (InvalidOperationException ex) {
            Require(ex.Message.Contains(expected), "Unexpected path message: " + ex.Message); return;
        }
        throw new Exception("Invalid path accepted: " + key);
    }
    static int Main(string[] args) {
        var root = Path.GetFullPath(args[0]); Directory.CreateDirectory(root);
        foreach (string name in new[] { "EXCEL.EXE", "et.exe", "launcher.exe", "DQ.exe" }) File.WriteAllText(Path.Combine(root, name), "test fixture; never execute");
        var settings = new Dictionary<string, object> { { "dmExe", Path.Combine(root, "launcher.exe") }, { "dqExe", Path.Combine(root, "DQ.exe") }, { "excelExe", Path.Combine(root, "EXCEL.EXE") } };
        Require(DesktopSettings.Valid(settings) && DesktopSettings.Engine(settings) == "excel", "Excel-only configuration requires WPS");
        settings["wpsExe"] = Path.Combine(root, "et.exe"); settings["spreadsheetEngine"] = "wps";
        Require(DesktopSettings.Valid(settings), "WPS selection invalid");
        settings["spreadsheetEngine"] = "excel"; settings.Remove("wpsExe"); Require(DesktopSettings.Valid(settings), "Explicit Excel selection requires WPS");
        settings["excelExe"] = Path.Combine(root, "et.exe"); Require(!DesktopSettings.Valid(settings), "WPS accepted as Excel");
        settings["excelExe"] = Path.Combine(root, "missing", "EXCEL.EXE"); Require(!DesktopSettings.Valid(settings), "Missing Excel accepted");
        Require(DesktopSettings.ResolveExecutable("excelExe", root).EndsWith("EXCEL.EXE"), "Excel directory resolution failed");
        var office = Path.Combine(root, "Microsoft Office");
        var clickToRun = Path.Combine(office, "root", "Office16");
        Directory.CreateDirectory(clickToRun);
        var excelExe = Path.Combine(clickToRun, "EXCEL.EXE");
        File.WriteAllText(excelExe, "test fixture; never execute");
        Require(DesktopSettings.ResolveExecutable("excelExe", office) == excelExe, "Office installation root was rejected");
        Require(DesktopSettings.ResolveExecutable("excelExe", " \u201c" + excelExe + "\u201d ") == excelExe, "Pasted path quotation not supported");
        RequirePathError("wpsExe", "", "WPS 表格：尚未填写路径");
        RequirePathError("dmExe", Path.Combine(root, "not-installed"), "DM：找不到填写的路径");
        RequirePathError("excelExe", Path.Combine(root, "et.exe"), "Excel：选中的文件与此栏不符");
        var empty = Path.Combine(root, "empty-installation");
        Directory.CreateDirectory(empty);
        RequirePathError("dqExe", empty, "DQ：此文件夹中没有找到对应程序");
        DesktopSettings.DataDirectory = Path.Combine(root, "state"); settings["excelExe"] = Path.Combine(root, "EXCEL.EXE"); DesktopSettings.Save(settings);
        Require(DesktopSettings.Engine(DesktopSettings.Read()) == "excel" && DesktopSettings.Valid(DesktopSettings.Read()), "Excel preference not preserved");
        var cached = DesktopSettings.Detect(false);
        Require(DesktopSettings.Valid(cached) && DesktopSettings.Get(cached, "excelExe") == Path.Combine(root, "EXCEL.EXE"), "Saved paths should be used without running the detector");
        Console.WriteLine("Desktop Office and settings path checks passed (14; file fixtures, not native Excel)."); return 0;
    }
}
