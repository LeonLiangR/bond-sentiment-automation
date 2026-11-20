using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using System.Web.Script.Serialization;

namespace SentimentDesktop {
    internal static class DesktopSettings {
        public static readonly string Root = AppDomain.CurrentDomain.BaseDirectory;
        public static string DataDirectory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "BondSentimentAutomation");
        public static string FileName { get { return Path.Combine(DataDirectory, "settings.json"); } }
        public static JavaScriptSerializer Serializer() { return new JavaScriptSerializer { MaxJsonLength = 24000000 }; }
        public static string Quote(string value) {
            var result = new StringBuilder("\""); int slashes = 0;
            foreach (char c in value) {
                if (c == '\\') { slashes++; continue; }
                result.Append('\\', c == '"' ? slashes * 2 + 1 : slashes); result.Append(c); slashes = 0;
            }
            result.Append('\\', slashes * 2); result.Append('"'); return result.ToString();
        }
        public static string Get(IDictionary<string, object> values, string key) { object value; return values != null && values.TryGetValue(key, out value) && value != null ? Convert.ToString(value) : ""; }
        public static bool Flag(IDictionary<string, object> values, string key) { object value; return values != null && values.TryGetValue(key, out value) && value is bool && (bool)value; }
        public static double? Number(IDictionary<string, object> values, string key) {
            object value; double parsed;
            if (values == null || !values.TryGetValue(key, out value) || value == null || !Double.TryParse(Convert.ToString(value, System.Globalization.CultureInfo.InvariantCulture), System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out parsed)) return null;
            return Double.IsNaN(parsed) || Double.IsInfinity(parsed) ? (double?)null : parsed;
        }
        public static Dictionary<string, object> Read(string file) { try { return Serializer().Deserialize<Dictionary<string, object>>(System.IO.File.ReadAllText(file, Encoding.UTF8)); } catch { return new Dictionary<string, object>(); } }
        public static Dictionary<string, object> Read() { return Read(FileName); }
        public static string Engine(IDictionary<string, object> values) { string chosen = Get(values, "spreadsheetEngine"); return String.IsNullOrEmpty(chosen) ? (System.IO.File.Exists(Get(values, "wpsExe")) ? "wps" : System.IO.File.Exists(Get(values, "excelExe")) ? "excel" : "wps") : chosen; }
        public static bool Valid(IDictionary<string, object> values) {
            string engine = Engine(values); if (engine != "wps" && engine != "excel") return false;
            foreach (string key in new[] { "dmExe", "dqExe", engine == "excel" ? "excelExe" : "wpsExe" }) if (!System.IO.File.Exists(Get(values, key))) return false;
            return Path.GetFileName(Get(values, engine == "excel" ? "excelExe" : "wpsExe")).Equals(engine == "excel" ? "excel.exe" : "et.exe", StringComparison.OrdinalIgnoreCase);
        }
        public static void AtomicJson(string file, object value) {
            Directory.CreateDirectory(Path.GetDirectoryName(file)); string pending = file + ".pending-" + Guid.NewGuid().ToString("N");
            System.IO.File.WriteAllText(pending, Serializer().Serialize(value), new UTF8Encoding(false));
            if (System.IO.File.Exists(file)) System.IO.File.Replace(pending, file, null); else System.IO.File.Move(pending, file);
        }
        public static void Save(Dictionary<string, object> values) {
            values["version"] = 3; values["spreadsheetEngine"] = Engine(values);
            if (String.IsNullOrWhiteSpace(Get(values, "outputDir"))) values["outputDir"] = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
            if (System.IO.File.Exists(Get(values, "dqExe"))) {
                var match = Regex.Match(FileVersionInfo.GetVersionInfo(Get(values, "dqExe")).ProductVersion ?? "", @"\d+\.\d+\.\d+");
                if (match.Success) values["dqVersion"] = match.Value;
            }
            AtomicJson(FileName, values);
        }
        public static Dictionary<string, object> Detect(bool force) {
            var values = Read(); if (!force && Valid(values)) return values;
            string source = Path.Combine(Root, "src", "detect.ps1").Replace("'", "''");
            string code = "[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false);$OutputEncoding=[Console]::OutputEncoding;$p=[IO.File]::ReadAllText('" + source + "',[Text.Encoding]::UTF8);& ([scriptblock]::Create($p))";
            if (!force) code += " -SettingsFile '" + FileName.Replace("'", "''") + "'";
            var start = new ProcessStartInfo("powershell.exe", "-NoProfile -NonInteractive -EncodedCommand " + Convert.ToBase64String(Encoding.Unicode.GetBytes(code))) {
                UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true,
                StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8
            };
            Process process;
            try { process = Process.Start(start); }
            catch (Win32Exception ex) {
                if (ex.NativeErrorCode == 786 || ex.NativeErrorCode == 1260)
                    throw new InvalidOperationException("公司策略阻止了自动检测启动 PowerShell（Windows 错误 " + ex.NativeErrorCode + "）。可以手动选择程序文件并保存；日报能否启动需由 IT 确认。", ex);
                throw;
            }
            using (process) {
                var output = process.StandardOutput.ReadToEndAsync(); var errors = process.StandardError.ReadToEndAsync();
                if (!process.WaitForExit(30000)) { process.Kill(); throw new InvalidOperationException("软件位置检测超时，请手动选择安装位置。"); }
                if (process.ExitCode != 0) throw new InvalidOperationException("未完成软件位置检测，请手动选择安装位置。" + errors.Result);
                var found = Serializer().Deserialize<Dictionary<string, object>>(output.Result.Trim());
                string chosen = Get(values, "spreadsheetEngine");
                foreach (var item in found) if (item.Value != null) values[item.Key] = item.Value;
                if (chosen == "wps" || chosen == "excel") values["spreadsheetEngine"] = chosen;
            }
            return values;
        }
        static FileAttributes? ReadAttributes(string path) {
            try { return System.IO.File.GetAttributes(path); }
            catch (FileNotFoundException) { return null; }
            catch (DirectoryNotFoundException) { return null; }
        }
        public static string ResolveExecutable(string key, string input) {
            string label, expected;
            string[] relativeFiles;
            switch (key) {
                case "dmExe": label = "DM"; expected = "launcher.exe 或 DM-Native.exe"; relativeFiles = new[] { "launcher.exe", "DM-Native.exe" }; break;
                case "dqExe": label = "DQ"; expected = "中债 DQ 终端的 .exe"; relativeFiles = new string[0]; break;
                case "wpsExe": label = "WPS 表格"; expected = "office6 目录下的 et.exe"; relativeFiles = new[] { "et.exe", @"office6\et.exe" }; break;
                case "excelExe": label = "Excel"; expected = "Microsoft Office 目录下的 EXCEL.EXE"; relativeFiles = new[] { "EXCEL.EXE", @"root\Office16\EXCEL.EXE", @"Office16\EXCEL.EXE" }; break;
                default: throw new ArgumentOutOfRangeException("key");
            }
            string raw = Environment.ExpandEnvironmentVariables((input ?? "").Trim().Trim('"', '\u201c', '\u201d').Trim());
            string select = "请点击「选择…」，选中" + expected + "。";
            if (String.IsNullOrWhiteSpace(raw)) throw new InvalidOperationException(label + "：尚未填写路径。" + select);
            try {
                string candidate = Path.GetFullPath(raw);
                var attributes = ReadAttributes(candidate);
                if (!attributes.HasValue) throw new InvalidOperationException(label + "：找不到填写的路径。" + select);
                if ((attributes.Value & FileAttributes.Directory) != 0) {
                    string directory = candidate;
                    candidate = null;
                    if (key == "dqExe") {
                        foreach (string file in Directory.EnumerateFiles(directory, "*.exe")) {
                            if (!MatchesExecutable(key, Path.GetFileName(file))) continue;
                            if (candidate != null) throw new InvalidOperationException(label + "：目录内有多个 DQ 程序。" + select);
                            candidate = file;
                        }
                    } else {
                        foreach (string relative in relativeFiles) {
                            string file = Path.Combine(directory, relative);
                            var fileAttributes = ReadAttributes(file);
                            if (fileAttributes.HasValue && (fileAttributes.Value & FileAttributes.Directory) == 0) { candidate = file; break; }
                        }
                    }
                    if (candidate == null) throw new InvalidOperationException(label + "：此文件夹中没有找到对应程序。" + select);
                }
                if (!MatchesExecutable(key, Path.GetFileName(candidate))) throw new InvalidOperationException(label + "：选中的文件与此栏不符。" + select);
                return candidate;
            } catch (UnauthorizedAccessException ex) {
                throw new InvalidOperationException(label + "：Windows 拒绝访问此路径，请让 IT 核对权限。", ex);
            } catch (System.Security.SecurityException ex) {
                throw new InvalidOperationException(label + "：Windows 拒绝访问此路径，请让 IT 核对权限。", ex);
            } catch (IOException ex) {
                int code = ex.HResult & 0xffff;
                if (code == 786 || code == 1260) throw new InvalidOperationException(label + "：Windows 策略限制访问此路径（错误 " + code + "），请联系 IT。", ex);
                throw new InvalidOperationException(label + "：无法读取此路径。" + select, ex);
            } catch (ArgumentException ex) {
                throw new InvalidOperationException(label + "：路径格式不正确。" + select, ex);
            } catch (NotSupportedException ex) {
                throw new InvalidOperationException(label + "：路径格式不受支持。" + select, ex);
            }
        }
        static bool MatchesExecutable(string key, string name) {
            if (key == "dmExe") return name.Equals("launcher.exe", StringComparison.OrdinalIgnoreCase) || name.Equals("DM-Native.exe", StringComparison.OrdinalIgnoreCase);
            if (key == "wpsExe") return name.Equals("et.exe", StringComparison.OrdinalIgnoreCase);
            if (key == "excelExe") return name.Equals("EXCEL.EXE", StringComparison.OrdinalIgnoreCase);
            return name.EndsWith(".exe", StringComparison.OrdinalIgnoreCase) && name.IndexOf("DQ", StringComparison.OrdinalIgnoreCase) >= 0 && !name.StartsWith("Uninstall", StringComparison.OrdinalIgnoreCase);
        }
        public static Dictionary<string, object> LastSuccess() {
            var result = Read(Path.Combine(DataDirectory, "last-success.json"));
            if (Flag(result, "success") && Directory.Exists(Get(result, "output"))) return result;
            result = Read(Path.Combine(DataDirectory, "last-run.json"));
            if (Flag(result, "success") && Directory.Exists(Get(result, "output"))) { AtomicJson(Path.Combine(DataDirectory, "last-success.json"), result); return result; }
            return new Dictionary<string, object>();
        }
        public static void ApplyProxy(ProcessStartInfo start) {
            try {
                if (String.IsNullOrEmpty(start.EnvironmentVariables["HTTPS_PROXY"])) using (var registry = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Internet Settings")) {
                    if (registry != null && Convert.ToInt32(registry.GetValue("ProxyEnable", 0)) == 1) {
                        string server = Convert.ToString(registry.GetValue("ProxyServer", ""));
                        if (server.Contains("=")) { var m = Regex.Match(server, @"(?:^|;)https?=([^;]+)"); server = m.Success ? m.Groups[1].Value : ""; }
                        if (!String.IsNullOrWhiteSpace(server)) { if (!server.Contains("://")) server = "http://" + server; start.EnvironmentVariables["HTTP_PROXY"] = server; start.EnvironmentVariables["HTTPS_PROXY"] = server; }
                    }
                }
                start.EnvironmentVariables["NO_PROXY"] = (start.EnvironmentVariables["NO_PROXY"] ?? "") + ",localhost,127.0.0.1,::1";
            } catch { }
        }
    }
}
