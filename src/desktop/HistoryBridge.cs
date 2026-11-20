using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Threading.Tasks;

namespace SentimentDesktop {
    internal static class HistoryBridge {
        public static async Task<Dictionary<string, object>> Run(string mode, string file) {
            string node = Path.Combine(DesktopSettings.Root, @"runtime\node\node.exe");
            string script = Path.Combine(DesktopSettings.Root, @"src\history-transfer.mjs");
            if (!File.Exists(node) || !File.Exists(script)) throw new InvalidOperationException("历史交接组件不完整，请检查程序文件。");
            string arguments = DesktopSettings.Quote(script) + " --mode " + mode +
                " --root " + DesktopSettings.Quote(DesktopSettings.Root) + " --data-dir " + DesktopSettings.Quote(DesktopSettings.DataDirectory);
            if (file != null) arguments += " --file " + DesktopSettings.Quote(file);
            var start = new ProcessStartInfo(node, arguments) {
                WorkingDirectory = DesktopSettings.Root, UseShellExecute = false, CreateNoWindow = true,
                RedirectStandardOutput = true, RedirectStandardError = true,
                StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8
            };
            using (var process = Process.Start(start)) {
                var output = process.StandardOutput.ReadToEndAsync(); var error = process.StandardError.ReadToEndAsync();
                bool exited = await Task.Run(() => process.WaitForExit(30000));
                if (!exited) { process.Kill(); throw new InvalidOperationException("历史文件处理超时，原文件已保留，请稍后重试。"); }
                string text = await output, message = await error;
                if (process.ExitCode != 0) throw new InvalidOperationException(String.IsNullOrWhiteSpace(message) ? "历史文件处理未完成。" : message.Trim());
                var result = DesktopSettings.Serializer().Deserialize<Dictionary<string, object>>(text.Trim());
                if (!DesktopSettings.Flag(result, "success")) throw new InvalidOperationException("历史交接未收到完成确认。");
                return result;
            }
        }
    }
}
