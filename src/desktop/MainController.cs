using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Markup;
using System.Windows.Media;
using System.Windows.Shell;

namespace SentimentDesktop {
    internal sealed class MainController {
        public readonly Window Window;
        public DateTime SelectedDate;
        public string ReplayDirectory;
        public RunOutcome LastOutcome;
        public Func<bool, string> HistoryFileSelection;
        public Action<string> HistoryConflictDisplay;
        public Task HistoryTransferTask = Task.FromResult(0);
        Dictionary<string, object> lastHistoryTransfer;
        Dictionary<string, object> settings, latest;
        readonly TaskRunner runner = new TaskRunner();
        readonly List<TextBlock> stepNumbers = new List<TextBlock>(), stepLabels = new List<TextBlock>();
        readonly List<Border> stepCircles = new List<Border>();
        readonly Queue<string> lines = new Queue<string>();
        string destination, state = "idle", logDirectory;
        bool busy, historyBusy, closeAfter, stopping, failed; int currentStep = -1;
        string historyLastDate;
        public MainController() {
            using (var input = File.OpenRead(Path.Combine(DesktopSettings.Root, @"src\desktop\MainWindow.xaml"))) Window = (Window)XamlReader.Load(input);
            UiTheme.Chrome(Window); Window.Width = Math.Min(1080, SystemParameters.WorkArea.Width - 40); Window.Height = Math.Min(780, SystemParameters.WorkArea.Height - 40);
            Window.MinHeight = Math.Min(560, SystemParameters.WorkArea.Height - 40); Window.MinWidth = Math.Min(800, SystemParameters.WorkArea.Width - 40);
            foreach (string key in new[] { "MinimizeButton", "MaximizeButton", "CloseButton" }) WindowChrome.SetIsHitTestVisibleInChrome(Control<Button>(key), true);
            Control<Button>("MinimizeButton").Click += delegate { Window.WindowState = WindowState.Minimized; };
            Control<Button>("MaximizeButton").Click += delegate { Window.WindowState = Window.WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized; };
            Control<Button>("CloseButton").Click += delegate { Window.Close(); };
            Control<Button>("SettingsButton").Click += delegate { EditSettings(); };
            Control<Button>("ImportHistoryButton").Click += async delegate { HistoryTransferTask = TransferHistory(true); await HistoryTransferTask; };
            Control<Button>("ExportHistoryButton").Click += async delegate { HistoryTransferTask = TransferHistory(false); await HistoryTransferTask; };
            Control<Button>("DateButton").Click += delegate { var dialog = new CalendarDialog(Window, SelectedDate); dialog.Window.ShowDialog(); if (dialog.Selection.HasValue) { SelectedDate = dialog.Selection.Value; RefreshDate(); } };
            Control<Button>("FolderButton").Click += delegate { try { string folder = NativeDialogs.Folder(Window, destination); if (folder != null) { destination = folder; settings["outputDir"] = folder; DesktopSettings.Save(settings); RefreshDestination(); } } catch (Exception ex) { SetStatus("无法选择目录：" + ex.Message, true); } };
            Control<Button>("GenerateButton").Click += async delegate { await Generate(); };
            Control<Button>("StopButton").Click += delegate { Stop(); };
            Control<Button>("ExcelButton").Click += delegate { OpenReport("当日报告_", ".xlsx"); };
            Control<Button>("TextButton").Click += delegate { OpenReport("汇报文字_", ".txt"); };
            Control<Button>("ImageButton").Click += delegate { OpenReport("汇报图片_", ".png"); };
            Control<Button>("OpenFolderButton").Click += delegate { Open(DesktopSettings.Get(latest, "output")); };
            Control<Button>("LogFolderButton").Click += delegate { Open(logDirectory); };
            Control<Button>("CopyLogButton").Click += delegate { try { Clipboard.SetText(Control<TextBox>("LogBox").Text); SetStatus("运行记录已复制。", false); } catch { SetStatus("剪贴板暂时不可用，请稍后重试。", true); } };
            var steps = Control<System.Windows.Controls.Primitives.UniformGrid>("Steps");
            string[] captions = { "获取DM数据", "补齐Wind条款", "DQ批量定价", "计算并出报告" };
            for (int i = 0; i < 4; i++) {
                var number = UiTheme.Text((i + 1).ToString(), 13, UiTheme.Muted); number.FontFamily = new FontFamily("Times New Roman"); number.HorizontalAlignment = HorizontalAlignment.Center; number.VerticalAlignment = VerticalAlignment.Center;
                var circle = new Border { Background = UiTheme.Brush("#292B24"), CornerRadius = new CornerRadius(12), Width = 24, Height = 24, Child = number, HorizontalAlignment = HorizontalAlignment.Left, Margin = new Thickness(0, 0, 0, 10) };
                var label = UiTheme.Text(captions[i], 11.5, UiTheme.Muted); var item = new StackPanel { Margin = new Thickness(0, 0, 4, 0) }; item.Children.Add(circle); item.Children.Add(label); steps.Children.Add(item); stepNumbers.Add(number); stepCircles.Add(circle); stepLabels.Add(label);
            }
            runner.Log += line => Window.Dispatcher.BeginInvoke(new Action(() => Append(line)));
            runner.Event += value => Window.Dispatcher.BeginInvoke(new Action(() => Receive(value)));
            Window.Closing += delegate(object sender, System.ComponentModel.CancelEventArgs e) { if (historyBusy) { e.Cancel = true; closeAfter = true; } else if (busy) { e.Cancel = true; closeAfter = true; Stop(); } };
            Window.SizeChanged += delegate { Responsive(); };
            settings = DesktopSettings.Read(); destination = DesktopSettings.Get(settings, "outputDir"); if (String.IsNullOrWhiteSpace(destination)) destination = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
            SelectedDate = DateTime.Today.AddDays(-1); while (SelectedDate.DayOfWeek == DayOfWeek.Saturday || SelectedDate.DayOfWeek == DayOfWeek.Sunday) SelectedDate = SelectedDate.AddDays(-1);
            RefreshDate(); RefreshDestination(); latest = DesktopSettings.LastSuccess(); ShowResult(); SetBusy(false); Control<Button>("LogFolderButton").IsEnabled = false; Responsive();
        }
        public T Control<T>(string name) where T : FrameworkElement { return (T)Window.FindName(name); }
        public async Task Initialize() {
            await RefreshHistory();
            if (DesktopSettings.Valid(settings)) return;
            Control<Button>("GenerateButton").IsEnabled = false; SetStatus("首次使用，正在检测软件安装位置…", false);
            try { settings = await Task.Run(() => DesktopSettings.Detect(false)); if (DesktopSettings.Valid(settings)) { DesktopSettings.Save(settings); SetStatus("软件位置已记录，运行时验证数据与插件。", false); } else SetStatus("请在设置中补全DM、DQ及所选表格引擎的位置。", true); }
            catch (Exception ex) { SetStatus(ex.Message, true); }
            finally { Control<Button>("GenerateButton").IsEnabled = !busy && !historyBusy; }
        }
        async Task RefreshHistory() {
            try {
                var result = await HistoryBridge.Run("summary", null); historyLastDate = DesktopSettings.Get(result, "lastDate");
                double count = DesktopSettings.Number(result, "count") ?? 0;
                Control<TextBlock>("HistorySummary").Text = count == 0 ? "尚无历史，接手时可先导入交接文件。" : "已收录 " + count.ToString("0") + " 个日期  ·  " + DesktopSettings.Get(result, "firstDate") + " 至 " + historyLastDate;
            } catch (Exception ex) { Control<TextBlock>("HistorySummary").Text = "历史读取未完成：" + ex.Message; }
        }
        async Task TransferHistory(bool import) {
            if (busy || historyBusy) return;
            string file;
            try { file = HistoryFileSelection != null ? HistoryFileSelection(import) : import ? NativeDialogs.ImportHistory(Window) : NativeDialogs.ExportHistory(Window, String.IsNullOrEmpty(historyLastDate) ? DateTime.Today.ToString("yyyy-MM-dd") : historyLastDate); }
            catch (Exception ex) { SetStatus("无法选择历史文件：" + ex.Message, true); return; }
            if (file == null) return;
            historyBusy = true; SetBusy(false); Control<TextBlock>("HistorySummary").Text = import ? "正在校验并合并交接历史…" : "正在导出完整汇总历史…";
            try {
              try {
                var result = await HistoryBridge.Run(import ? "import" : "export", file);
                lastHistoryTransfer = result;
                if (import) {
                    string note = "历史导入完成：新增 " + Format(result, "added", "0") + " 个日期，已有一致 " + Format(result, "identical", "0") + " 个。";
                    double conflicts = DesktopSettings.Number(result, "conflictCount") ?? 0;
                    if (conflicts > 0) {
                        note += "同日冲突 " + conflicts.ToString("0") + " 个，已保留本机记录。";
                        string message = note + "\n\n冲突日期：" + DesktopSettings.Get(result, "conflictPreview") + (conflicts > 12 ? "等" : "");
                        if (HistoryConflictDisplay != null) HistoryConflictDisplay(message); else MessageBox.Show(Window, message, "历史交接完成", MessageBoxButton.OK, MessageBoxImage.Information);
                    }
                    Append(note); SetStatus(note, false);
                } else { string note = "已导出 " + Format(result, "count", "0") + " 个日期的完整历史，可交接给下月同事。"; Append(note); SetStatus(note, false); }
              } catch (Exception ex) { Append("历史交接失败：" + ex.Message); SetStatus("历史交接失败：" + ex.Message, true); }
              await RefreshHistory();
            } finally { historyBusy = false; SetBusy(false); if (closeAfter) Window.Close(); }
        }
        void EditSettings() { var dialog = new SettingsDialog(Window, settings); dialog.Window.ShowDialog(); if (dialog.Saved) { settings = DesktopSettings.Read(); SetStatus("软件位置已保存，后续打开直接使用。", false); } }
        void RefreshDate() { Control<Button>("DateButton").Content = SelectedDate.ToString("yyyy-MM-dd") + "   ⌄"; }
        void RefreshDestination() { string desktop = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory); Control<TextBlock>("FolderLabel").Text = String.Equals(destination.TrimEnd('\\'), desktop.TrimEnd('\\'), StringComparison.OrdinalIgnoreCase) ? "桌面" : new DirectoryInfo(destination).Name; Control<Button>("FolderButton").ToolTip = destination; }
        public void SetDestination(string folder) { destination = folder; RefreshDestination(); }
        public void SetDate(DateTime date) { SelectedDate = date.Date; RefreshDate(); }
        void Responsive() {
            bool narrow = Window.Width < 950; var card = Control<Border>("ResultCard"); var grid = Control<Grid>("Cards");
            Grid.SetColumn(card, narrow ? 0 : 2); Grid.SetRow(card, narrow ? 1 : 0); Grid.SetColumnSpan(Control<Border>("TaskCard"), narrow ? 3 : 1); Grid.SetColumnSpan(card, narrow ? 3 : 1); card.Margin = narrow ? new Thickness(0, 18, 0, 0) : new Thickness(0);
            grid.ColumnDefinitions[0].Width = new GridLength(1.18, GridUnitType.Star); Control<StackPanel>("Page").Margin = new Thickness(narrow ? 24 : 32, 17, narrow ? 24 : 32, 21);
        }
        void Append(string line) {
            if (String.IsNullOrWhiteSpace(line)) return;
            lines.Enqueue(DateTime.Now.ToString("HH:mm:ss") + "  " + line); while (lines.Count > 350) lines.Dequeue();
            var box = Control<TextBox>("LogBox"); box.Text = String.Join(Environment.NewLine, lines.ToArray()); box.ScrollToEnd();
        }
        void SetStatus(string text, bool error) { Control<TextBlock>("Status").Text = text; Control<TextBlock>("Status").Foreground = error ? UiTheme.Danger : UiTheme.Muted; }
        void SetBusy(bool value) {
            busy = value; foreach (string key in new[] { "GenerateButton", "DateButton", "FolderButton", "SettingsButton", "ImportHistoryButton", "ExportHistoryButton" }) Control<Button>(key).IsEnabled = !value && !historyBusy;
            Control<Button>("StopButton").Visibility = value ? Visibility.Visible : Visibility.Collapsed; Control<Button>("StopButton").IsEnabled = value;
            Control<TextBlock>("GenerateLabel").Text = value ? "正在生成报告…" : "生成当日报告";
        }
        void PaintSteps(int step, bool complete, bool error) {
            for (int i = 0; i < 4; i++) {
                bool done = complete || i < step, active = i == step && !complete;
                stepNumbers[i].Text = done ? "✓" : (i + 1).ToString(); stepNumbers[i].Foreground = active && !error ? UiTheme.Deep : done ? UiTheme.Gold : active && error ? UiTheme.Danger : UiTheme.Muted;
                stepCircles[i].Background = active && !error ? UiTheme.Gold : done ? UiTheme.Brush("#2C2A20") : active && error ? UiTheme.Brush("#362620") : UiTheme.Brush("#292B24");
                stepLabels[i].Foreground = active || done ? UiTheme.Ink : UiTheme.Muted;
            }
        }
        void Receive(Dictionary<string, object> value) {
            string type = DesktopSettings.Get(value, "type");
            if (type == "stage") {
                int stage = (int)(DesktopSettings.Number(value, "stage") ?? 0); if (!failed && !stopping) { currentStep = stage <= 2 ? 0 : stage == 3 ? 1 : stage <= 5 ? 2 : 3; PaintSteps(currentStep, false, false); }
                if (!failed && !stopping) SetStatus(stage == 8 ? "报告已生成，正在释放本轮后台实例…" : DesktopSettings.Get(value, "message") + "…", false);
            } else if (type == "service") {
                string service = DesktopSettings.Get(value, "service"); string key = service == "dm" ? "DmState" : service == "dq" ? "DqState" : "WindState"; string name = service == "wind" ? "Wind" : service.ToUpperInvariant();
                Control<TextBlock>(key).Text = "●  " + name + " · " + (DesktopSettings.Get(value, "state") == "replay" ? "历史回放" : "本次已验证"); Control<TextBlock>(key).Foreground = UiTheme.Gold;
            } else if (type == "failure") { failed = true; PaintSteps(currentStep, false, true); SetStatus("当前步骤未完成，正在释放本轮后台实例…", true); }
            string run = DesktopSettings.Get(value, "run"); if (!String.IsNullOrEmpty(run)) { logDirectory = run; Control<Button>("LogFolderButton").IsEnabled = true; }
        }
        public async Task Generate() {
            if (busy || historyBusy) return;
            if (!DesktopSettings.Valid(settings)) { SetStatus("请先在设置中确认DM、DQ及Excel或WPS安装位置。", true); return; }
            try { destination = Path.GetFullPath(destination); Directory.CreateDirectory(destination); settings["outputDir"] = destination; DesktopSettings.Save(settings); }
            catch (Exception ex) { SetStatus("无法使用保存目录：" + ex.Message, true); return; }
            lines.Clear(); Control<TextBox>("LogBox").Clear(); failed = stopping = false; currentStep = 0; state = "running"; LastOutcome = null; SetBusy(true); PaintSteps(0, false, false);
            Control<TextBlock>("TaskBadge").Text = "进行中"; SetStatus("正在准备任务…", false);
            foreach (string key in new[] { "DmState", "DqState", "WindState" }) { Control<TextBlock>(key).Text = "●  " + (key == "DmState" ? "DM" : key == "DqState" ? "DQ" : "Wind") + " · 待验证"; Control<TextBlock>(key).Foreground = UiTheme.Muted; }
            try {
                LastOutcome = await runner.Start(SelectedDate, destination, ReplayDirectory);
                if (LastOutcome.Success) {
                    state = "done"; latest = LastOutcome.Receipt; ShowResult(); PaintSteps(3, true, false); Control<TextBlock>("TaskBadge").Text = "已完成"; SetStatus("五页数据表、汇报文字及图片已保存。", false);
                    Control<TextBlock>("Footer").Text = "本轮新增后台已释放，原有软件保持开启。";
                } else if (LastOutcome.Cancelled) {
                    state = "stopped"; Control<TextBlock>("TaskBadge").Text = "已停止"; SetStatus("任务已停止，本轮新增后台已释放。", false); PaintSteps(-1, false, false);
                } else { Fail(LastOutcome.Error, LastOutcome.Receipt != null && DesktopSettings.Flag(LastOutcome.Receipt, "cleanup")); }
            } catch (Exception ex) { Append(ex.ToString()); Fail(ex.Message, false); }
            finally { SetBusy(false); }
            await RefreshHistory(); if (closeAfter) Window.Close();
        }
        void Fail(string message, bool cleanup) {
            state = "error"; failed = true; Control<TextBlock>("TaskBadge").Text = "未完成"; PaintSteps(currentStep, false, true);
            string friendly = String.IsNullOrWhiteSpace(message) ? "未收到后台完成确认，请展开运行记录查看。" : message.Trim();
            if (friendly.Contains("已有任务正在运行")) friendly = "已有任务正在运行，请在原窗口等待结束。";
            if (friendly.Length > 180) friendly = friendly.Substring(0, 180) + "…（详见运行记录）";
            SetStatus(friendly, true); Control<Expander>("LogExpander").IsExpanded = true;
            Control<TextBlock>("Footer").Text = cleanup ? "本轮新增后台已释放，原有软件保持开启。最近成功报告仍可查看。" : "请查看运行记录确认任务状态。最近成功报告仍可查看。";
        }
        public void Stop() {
            if (!busy || stopping) return; try { runner.Cancel(); stopping = true; state = "stopping"; Control<Button>("StopButton").IsEnabled = false; Control<TextBlock>("GenerateLabel").Text = "正在结束任务…"; Control<TextBlock>("TaskBadge").Text = "结束中"; SetStatus("已请求停止，当前步骤结束后释放本轮新增后台。", false); } catch (Exception ex) { SetStatus("停止请求未写入：" + ex.Message, true); }
        }
        void ShowResult() {
            bool valid = DesktopSettings.Flag(latest, "success") && Directory.Exists(DesktopSettings.Get(latest, "output"));
            Dictionary<string, object> summary = null; object raw; if (valid && latest.TryGetValue("summary", out raw)) summary = raw as Dictionary<string, object>;
            Control<TextBlock>("IndexValue").Text = Format(summary, "index", "0.00"); Control<TextBlock>("SampleCount").Text = Format(summary, "n", "0"); Control<TextBlock>("OldIndex").Text = Format(summary, "oldIndex", "0.0");
            string date = DesktopSettings.Get(latest, "date"); Control<TextBlock>("ResultDate").Text = valid ? date.Replace('-', '.') : "尚无报告";
            Control<TextBlock>("ResultNote").Text = valid ? "包含当日报告、逐券得分、DQ结果、DM原始数据及历史底表。" : "完成后可查看五页数据表、汇报文字及图片。";
            Control<TextBlock>("ResultKind").Text = valid ? (DesktopSettings.Flag(latest, "replay") ? "真实数据回放验证" : "已完成") : "等待首次生成";
            foreach (string key in new[] { "ExcelButton", "TextButton", "ImageButton", "OpenFolderButton" }) Control<Button>(key).IsEnabled = valid;
        }
        static string Format(Dictionary<string, object> values, string key, string format) { double? value = DesktopSettings.Number(values, key); return value.HasValue ? value.Value.ToString(format, System.Globalization.CultureInfo.InvariantCulture) : "—"; }
        void OpenReport(string prefix, string suffix) { string file = Path.Combine(DesktopSettings.Get(latest, "output"), prefix + DesktopSettings.Get(latest, "date").Replace("-", "") + suffix); Open(file); }
        void Open(string target) { try { if (String.IsNullOrWhiteSpace(target) || !Directory.Exists(target) && !File.Exists(target)) { SetStatus("文件已移动或不存在，请检查报告保存目录。", true); return; } Process.Start(new ProcessStartInfo(target) { UseShellExecute = true }); } catch (Exception ex) { SetStatus("无法打开文件：" + ex.Message, true); } }
        public object TestState() { return new { state, busy, historyBusy, historySummary = Control<TextBlock>("HistorySummary").Text, lastHistoryTransfer, canImportHistory = Control<Button>("ImportHistoryButton").IsEnabled, canExportHistory = Control<Button>("ExportHistoryButton").IsEnabled, canStart = Control<Button>("GenerateButton").IsEnabled, canStop = Control<Button>("StopButton").IsEnabled, status = Control<TextBlock>("Status").Text, index = Control<TextBlock>("IndexValue").Text, sampleCount = Control<TextBlock>("SampleCount").Text, latestOutput = DesktopSettings.Get(latest, "output"), lastOutcome = LastOutcome == null ? null : new { LastOutcome.Success, LastOutcome.Cancelled, LastOutcome.ExitCode, LastOutcome.RequestId, LastOutcome.Error }, font = UiTheme.FontEvidence }; }
    }
}
