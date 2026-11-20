using System;
using System.IO;
using System.Text;
using System.Windows;
using System.Windows.Threading;

namespace SentimentDesktop {
    internal static class Program {
        static string Option(string[] args, string key) { int i = Array.IndexOf(args, key); return i >= 0 && i < args.Length - 1 ? args[i + 1] : null; }
        [STAThread] static int Main(string[] args) {
            string diagnostic = Option(args, "--diagnostic");
            try {
                if (args.Length == 3 && args[0] == "--plot") { SentimentPlot.Render(args[1], args[2]); return 0; }
                string dataDirectory = Option(args, "--data-dir"); if (dataDirectory != null) DesktopSettings.DataDirectory = Path.GetFullPath(dataDirectory);
                if (args.Length == 2 && args[0] == "--detect") { var values = DesktopSettings.Detect(false); if (DesktopSettings.Valid(values)) DesktopSettings.Save(values); DesktopSettings.AtomicJson(args[1], values); return DesktopSettings.Valid(values) ? 0 : 2; }
                var app = new Application { ShutdownMode = ShutdownMode.OnMainWindowClose }; UiTheme.Initialize(app);
                var controller = new MainController(); var window = controller.Window;
                string preview = Option(args, "--preview"), test = Option(args, "--ui-test"), snapshot = Option(args, "--snapshot");
                bool offscreen = preview != null || test != null;
                if (offscreen) { window.WindowStartupLocation = WindowStartupLocation.Manual; window.Left = -20000; window.Top = -20000; window.ShowInTaskbar = false; }
                string width = Option(args, "--width"), height = Option(args, "--height"); if (width != null) window.Width = Double.Parse(width, System.Globalization.CultureInfo.InvariantCulture); if (height != null) window.Height = Double.Parse(height, System.Globalization.CultureInfo.InvariantCulture);
                window.ContentRendered += async delegate {
                    try {
                        if (preview != null) {
                            Window target = window;
                            if (Array.IndexOf(args, "--settings-view") >= 0) { var settingsView = new SettingsDialog(window, DesktopSettings.Read()); if (Array.IndexOf(args, "--excel-view") >= 0) settingsView.SelectEngine("excel"); target = settingsView.Window; }
                            if (Array.IndexOf(args, "--calendar-view") >= 0) target = new CalendarDialog(window, controller.SelectedDate).Window;
                            if (target != window) { target.WindowStartupLocation = WindowStartupLocation.Manual; target.Left = -20000; target.Top = -20000; target.Show(); }
                            double scale = Option(args, "--scale") == null ? 1 : Double.Parse(Option(args, "--scale"), System.Globalization.CultureInfo.InvariantCulture);
                            await Dispatcher.Yield(DispatcherPriority.ApplicationIdle); UiTheme.Snapshot(target, preview, scale);
                            if (diagnostic != null) DesktopSettings.AtomicJson(diagnostic, controller.TestState()); if (target != window) target.Close(); window.Close(); return;
                        }
                        await controller.Initialize();
                        if (test == "history") {
                            controller.HistoryFileSelection = importing => Option(args, importing ? "--history-input" : "--history-output");
                            string conflictNotice = null; controller.HistoryConflictDisplay = message => { conflictNotice = message; };
                            controller.Control<System.Windows.Controls.Button>("ExportHistoryButton").RaiseEvent(new RoutedEventArgs(System.Windows.Controls.Button.ClickEvent)); await controller.HistoryTransferTask;
                            controller.Control<System.Windows.Controls.Button>("ImportHistoryButton").RaiseEvent(new RoutedEventArgs(System.Windows.Controls.Button.ClickEvent)); await controller.HistoryTransferTask;
                            await Dispatcher.Yield(DispatcherPriority.ApplicationIdle);
                            if (snapshot != null) UiTheme.Snapshot(window, snapshot, 1);
                            if (diagnostic != null) DesktopSettings.AtomicJson(diagnostic, new { ui = controller.TestState(), history = controller.Control<System.Windows.Controls.TextBlock>("HistorySummary").Text, conflictNotice });
                            window.Close(); return;
                        }
                        if (test != null) {
                            controller.ReplayDirectory = Option(args, "--replay"); string date = Option(args, "--date"); if (date != null) controller.SetDate(DateTime.ParseExact(date, "yyyy-MM-dd", System.Globalization.CultureInfo.InvariantCulture));
                            controller.SetDestination(Option(args, "--output-dir"));
                            var task = controller.Generate();
                            if (test == "cancel") { await System.Threading.Tasks.Task.Delay(Option(args, "--cancel-after-ms") == null ? 30 : Int32.Parse(Option(args, "--cancel-after-ms"))); controller.Stop(); }
                            await task; await Dispatcher.Yield(DispatcherPriority.ApplicationIdle);
                            if (snapshot != null) UiTheme.Snapshot(window, snapshot, 1); if (diagnostic != null) DesktopSettings.AtomicJson(diagnostic, controller.TestState()); window.Close();
                        }
                    } catch (Exception ex) { if (diagnostic != null) DesktopSettings.AtomicJson(diagnostic, new { error = ex.ToString() }); else MessageBox.Show(window, ex.Message, "未能完成", MessageBoxButton.OK, MessageBoxImage.Error); if (offscreen) window.Close(); }
                };
                app.Run(window); return 0;
            } catch (Exception ex) {
                if (diagnostic != null) { try { DesktopSettings.AtomicJson(diagnostic, new { error = ex.ToString() }); } catch { } }
                else if (args.Length == 0) MessageBox.Show(ex.Message, "启动失败", MessageBoxButton.OK, MessageBoxImage.Error);
                return 1;
            }
        }
    }
}
