using System;
using System.Collections.Generic;
using System.IO;
using SentimentDesktop;
static class DesktopOfficeChecks {
    static void Require(bool value, string name) { if (!value) throw new Exception(name); }
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
        DesktopSettings.DataDirectory = Path.Combine(root, "state"); settings["excelExe"] = Path.Combine(root, "EXCEL.EXE"); DesktopSettings.Save(settings);
        Require(DesktopSettings.Engine(DesktopSettings.Read()) == "excel" && DesktopSettings.Valid(DesktopSettings.Read()), "Excel preference not preserved");
        Console.WriteLine("Desktop Office configuration checks passed (7; file fixtures, not native Excel)."); return 0;
    }
}
