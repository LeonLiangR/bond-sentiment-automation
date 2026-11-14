using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Threading.Tasks;

namespace SentimentDesktop {
    internal sealed class RunOutcome {
        public int ExitCode; public Dictionary<string, object> Receipt; public string Error; public string RequestId;
        public bool Success { get { return Receipt != null && DesktopSettings.Flag(Receipt, "success") && ExitCode == 0; } }
        public bool Cancelled { get { return Receipt != null && DesktopSettings.Flag(Receipt, "cancelled") && DesktopSettings.Flag(Receipt, "cleanup"); } }
    }
    internal sealed class TaskRunner {
        public event Action<string> Log;
        public event Action<Dictionary<string, object>> Event;
        Process process; string cancelFile; bool cancelRequested;
        public bool IsRunning { get { return process != null && !process.HasExited; } }
        public string CurrentRunDirectory { get; private set; }
        public async Task<RunOutcome> Start(DateTime date, string output, string replay) {
            if (IsRunning) throw new InvalidOperationException("本次任务还在执行，请稍候。");
            Directory.CreateDirectory(DesktopSettings.DataDirectory);
            string id = Guid.NewGuid().ToString("N");
            cancelFile = Path.Combine(DesktopSettings.DataDirectory, "cancel-" + id + ".request");
            string statusFile = Path.Combine(DesktopSettings.DataDirectory, "ui-status-" + id + ".json");
            cancelRequested = false; CurrentRunDirectory = "";
            string node = Path.Combine(DesktopSettings.Root, @"runtime\node\node.exe");
            if (!File.Exists(node)) throw new InvalidOperationException("程序运行环境不完整，请检查程序目录中的 runtime 文件夹。");
            string arguments = "--use-env-proxy " + DesktopSettings.Quote(Path.Combine(DesktopSettings.Root, @"src\portable-run.mjs")) +
                " --date " + date.ToString("yyyy-MM-dd") + " --settings " + DesktopSettings.Quote(DesktopSettings.FileName) +
                " --output-dir " + DesktopSettings.Quote(output) + " --request-id " + id + " --ui-status " + DesktopSettings.Quote(statusFile) +
                " --cancel-file " + DesktopSettings.Quote(cancelFile);
            if (!String.IsNullOrEmpty(replay)) arguments += " --replay " + DesktopSettings.Quote(replay);
            var start = new ProcessStartInfo(node, arguments) {
                WorkingDirectory = DesktopSettings.Root, UseShellExecute = false, CreateNoWindow = true,
                RedirectStandardOutput = true, RedirectStandardError = true,
                StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8
            };
            DesktopSettings.ApplyProxy(start); var errors = new StringBuilder();
            process = new Process { StartInfo = start, EnableRaisingEvents = true };
            try {
                if (!process.Start()) throw new InvalidOperationException("未能启动后台任务。");
                Task readOutput = ReadLines(process.StandardOutput, delegate(string line) {
                    if (line.StartsWith("@event ", StringComparison.Ordinal)) {
                        try {
                            var value = DesktopSettings.Serializer().Deserialize<Dictionary<string, object>>(line.Substring(7));
                            if (DesktopSettings.Get(value, "requestId") != id) return;
                            string run = DesktopSettings.Get(value, "run"); if (!String.IsNullOrEmpty(run)) CurrentRunDirectory = run;
                            if (Event != null) Event(value);
                        } catch (ArgumentException) { }
                    } else if (!line.StartsWith("{", StringComparison.Ordinal) && Log != null) Log(line);
                });
                Task readErrors = ReadLines(process.StandardError, delegate(string line) { lock (errors) { if (errors.Length < 12000) errors.AppendLine(line); } if (Log != null) Log(line); });
                await Task.Run(delegate { process.WaitForExit(); }); await Task.WhenAll(readOutput, readErrors);
                var receipt = DesktopSettings.Read(statusFile);
                if (DesktopSettings.Get(receipt, "requestId") != id) receipt = null;
                var result = new RunOutcome { ExitCode = process.ExitCode, Receipt = receipt, RequestId = id, Error = receipt == null ? errors.ToString() : DesktopSettings.Get(receipt, "error") };
                if (receipt == null && String.IsNullOrWhiteSpace(result.Error)) result.Error = "后台任务未返回结束确认，请查看运行记录。";
                return result;
            } finally {
                if (process != null) { process.Dispose(); process = null; }
                // These paths belong to this request, so a second window cannot cancel
                // another request or read its completion status.
                try { if (File.Exists(cancelFile)) File.Delete(cancelFile); } catch { }
            }
        }
        static async Task ReadLines(StreamReader reader, Action<string> receive) { string line; while ((line = await reader.ReadLineAsync()) != null) receive(line); }
        public void Cancel() {
            if (cancelRequested || String.IsNullOrEmpty(cancelFile)) return;
            File.WriteAllText(cancelFile, "stop", new UTF8Encoding(false)); cancelRequested = true;
        }
    }
}
