using System;
using System.Collections.Generic;
using System.IO;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace SentimentDesktop {
    internal sealed class SettingsDialog {
        public Window Window; public bool Saved;
        readonly Dictionary<string, TextBox> boxes = new Dictionary<string, TextBox>();
        readonly Dictionary<string, object> values;
        readonly TextBlock note; readonly Button detect, save;
        readonly Dictionary<string, StackPanel> officeRows = new Dictionary<string, StackPanel>();
        readonly Dictionary<string, Button> engineButtons = new Dictionary<string, Button>();
        string selectedEngine;
        public SettingsDialog(Window owner, Dictionary<string, object> settings) {
            values = new Dictionary<string, object>(settings); selectedEngine = DesktopSettings.Engine(values); StackPanel body;
            Window = UiTheme.Dialog(owner, "软件设置", 740, 640, out body);
            body.Children.Add(UiTheme.Text("软件设置", 25, UiTheme.Ink));
            var intro = UiTheme.Text("安装位置仅首次检测；保存后直接使用。软件升级或移动后，可重新检测。", 13, UiTheme.Muted); intro.Margin = new Thickness(0, 9, 0, 23); body.Children.Add(intro);
            var engineLabel = UiTheme.Text("选择表格软件。Wind 插件须已在所选软件中安装，无需填写插件路径。", 13, UiTheme.Muted); engineLabel.Margin = new Thickness(0, 0, 0, 9); body.Children.Add(engineLabel);
            var engines = new System.Windows.Controls.Primitives.UniformGrid { Columns = 2, Margin = new Thickness(0, 0, 0, 19) };
            foreach (string engine in new[] { "wps", "excel" }) { string choice = engine; var button = UiTheme.Button(engine == "wps" ? "WPS 表格" : "Microsoft Excel", delegate { SelectEngine(choice); }); button.Margin = new Thickness(0, 0, 8, 0); engineButtons[engine] = button; engines.Children.Add(button); } body.Children.Add(engines);
            string[] keys = { "dmExe", "dqExe", "wpsExe", "excelExe" };
            string[] names = { "DM 数据终端", "DQ 中债终端", "WPS 表格程序（et.exe）", "Microsoft Excel 程序（EXCEL.EXE）" };
            for (int i = 0; i < keys.Length; i++) {
                string key = keys[i], name = names[i]; var group = new StackPanel(); if (key == "wpsExe" || key == "excelExe") officeRows[key] = group; body.Children.Add(group);
                var label = UiTheme.Text(name, 13, UiTheme.Muted); label.Margin = new Thickness(0, 0, 0, 7); group.Children.Add(label);
                var row = new Grid { Margin = new Thickness(0, 0, 0, 16) }; row.ColumnDefinitions.Add(new ColumnDefinition()); row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                var box = new TextBox { Text = DesktopSettings.Get(values, key), ToolTip = "请选择 " + name + " 的完整路径", VerticalContentAlignment = VerticalAlignment.Center }; boxes[key] = box; row.Children.Add(box);
                var browse = UiTheme.Button("选择…", delegate { var dialog = new Microsoft.Win32.OpenFileDialog { Filter = "程序文件 (*.exe)|*.exe", Title = "选择 " + name }; if (dialog.ShowDialog(Window) == true) box.Text = dialog.FileName; }); browse.Margin = new Thickness(10, 0, 0, 0); Grid.SetColumn(browse, 1); row.Children.Add(browse); group.Children.Add(row);
            }
            note = UiTheme.Text("已开启的软件保持原状；仅隐藏和释放本次新增的后台实例。", 12, UiTheme.Muted); note.Margin = new Thickness(0, 2, 0, 14); body.Children.Add(note);
            var actions = new DockPanel { LastChildFill = false }; detect = UiTheme.Button("重新检测", async delegate { await Detect(); }); actions.Children.Add(detect);
            var cancel = UiTheme.Button("取消", delegate { Window.Close(); }); cancel.Margin = new Thickness(0, 0, 10, 0); DockPanel.SetDock(cancel, Dock.Right);
            save = UiTheme.Button("保存设置", delegate { Save(); }); save.Style = (Style)Application.Current.FindResource("Primary"); save.MinHeight = 40; save.MinWidth = 116; DockPanel.SetDock(save, Dock.Right); actions.Children.Add(save); actions.Children.Add(cancel); body.Children.Add(actions);
            SelectEngine(selectedEngine);
        }
        public void SelectEngine(string engine) {
            selectedEngine = engine; foreach (var pair in engineButtons) { bool selected = pair.Key == engine; pair.Value.Foreground = selected ? UiTheme.Gold : UiTheme.Muted; pair.Value.Background = selected ? UiTheme.Brush("#2C2A20") : UiTheme.Deep; pair.Value.BorderBrush = selected ? UiTheme.Gold : UiTheme.Line; }
            officeRows["wpsExe"].Visibility = engine == "wps" ? Visibility.Visible : Visibility.Collapsed; officeRows["excelExe"].Visibility = engine == "excel" ? Visibility.Visible : Visibility.Collapsed;
            note.Text = engine == "excel" ? "已选择 Excel，保存时请确认 DM、DQ 和 EXCEL.EXE 三项。" : "已选择 WPS 表格，保存时请确认 DM、DQ 和 et.exe 三项。"; note.Foreground = UiTheme.Muted;
        }
        async Task Detect() {
            detect.IsEnabled = save.IsEnabled = false; note.Foreground = UiTheme.Muted; note.Text = "正在检查安装位置…";
            try { var found = await Task.Run(() => DesktopSettings.Detect(true)); foreach (var pair in boxes) { string path = DesktopSettings.Get(found, pair.Key); if (File.Exists(path)) pair.Value.Text = path; } note.Text = "检测完成。请确认路径，未找到时可手动选择。"; }
            catch (Exception ex) { note.Text = ex.Message; note.Foreground = UiTheme.Danger; }
            finally { detect.IsEnabled = save.IsEnabled = true; }
        }
        void Save() {
            try { foreach (string key in new[] { "dmExe", "dqExe", selectedEngine == "excel" ? "excelExe" : "wpsExe" }) values[key] = DesktopSettings.ResolveExecutable(key, boxes[key].Text); values["spreadsheetEngine"] = selectedEngine; DesktopSettings.Save(values); Saved = true; Window.Close(); }
            catch (Exception ex) { note.Text = ex.Message; note.Foreground = UiTheme.Danger; }
        }
    }
    internal sealed class CalendarDialog {
        public Window Window; public DateTime? Selection;
        DateTime month; readonly DateTime selected; readonly TextBlock heading; readonly Grid days;
        public CalendarDialog(Window owner, DateTime date) {
            selected = date.Date; month = new DateTime(date.Year, date.Month, 1); StackPanel body;
            Window = UiTheme.Dialog(owner, "选择数据日期", 398, 450, out body);
            var top = new DockPanel { Margin = new Thickness(0, 0, 0, 16) };
            var previous = UiTheme.Button("‹", delegate { month = month.AddMonths(-1); Paint(); }); previous.FontSize = 22; previous.Width = 38; previous.Padding = new Thickness(0); top.Children.Add(previous);
            var next = UiTheme.Button("›", delegate { if (month < new DateTime(DateTime.Today.Year, DateTime.Today.Month, 1)) month = month.AddMonths(1); Paint(); }); next.FontSize = 22; next.Width = 38; next.Padding = new Thickness(0); DockPanel.SetDock(next, Dock.Right); top.Children.Add(next);
            heading = UiTheme.Text("", 19, UiTheme.Ink); heading.HorizontalAlignment = HorizontalAlignment.Center; heading.VerticalAlignment = VerticalAlignment.Center; top.Children.Add(heading); body.Children.Add(top);
            var weekdays = new System.Windows.Controls.Primitives.UniformGrid { Columns = 7, Margin = new Thickness(0, 0, 0, 5) }; foreach (char day in "一二三四五六日") { var label = UiTheme.Text(day.ToString(), 12, UiTheme.Muted); label.HorizontalAlignment = HorizontalAlignment.Center; weekdays.Children.Add(label); } body.Children.Add(weekdays);
            days = new Grid(); for (int i = 0; i < 7; i++) days.ColumnDefinitions.Add(new ColumnDefinition()); for (int i = 0; i < 6; i++) days.RowDefinitions.Add(new RowDefinition { Height = new GridLength(40) }); body.Children.Add(days);
            var hint = UiTheme.Text("选择DM文件所属日期，非简报发送日期。", 12, UiTheme.Muted); hint.Margin = new Thickness(0, 16, 0, 0); body.Children.Add(hint); Paint();
        }
        void Paint() {
            heading.Text = month.ToString("yyyy 年 M 月"); days.Children.Clear(); int offset = ((int)month.DayOfWeek + 6) % 7;
            for (int d = 1; d <= DateTime.DaysInMonth(month.Year, month.Month); d++) {
                var day = new DateTime(month.Year, month.Month, d); var button = UiTheme.Button(d.ToString(), delegate { Selection = day; Window.Close(); }); button.FontFamily = new FontFamily("Times New Roman"); button.FontSize = 16; button.MinHeight = 0; button.Padding = new Thickness(0); button.Margin = new Thickness(2); button.IsEnabled = day <= DateTime.Today;
                if (day == selected) { button.Background = UiTheme.Gold; button.Foreground = UiTheme.Deep; } else if (day == DateTime.Today) { button.Foreground = UiTheme.Gold; button.BorderBrush = UiTheme.Gold; }
                Grid.SetRow(button, (d - 1 + offset) / 7); Grid.SetColumn(button, (d - 1 + offset) % 7); days.Children.Add(button);
            }
        }
    }
}
