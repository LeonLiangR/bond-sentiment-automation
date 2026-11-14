using System;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Markup;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Shell;
using System.Runtime.InteropServices;

namespace SentimentDesktop {
    internal static class UiTheme {
        public static readonly Brush Ink = Brush("#EEEAE1"), Muted = Brush("#AAA89D"), Gold = Brush("#C6AB73"), Line = Brush("#30322B"), Deep = Brush("#151613"), Panel = Brush("#191A17"), Danger = Brush("#E39B8C");
        public static FontFamily Serif; public static string FontEvidence;
        public static Brush Brush(string color) { var value = (SolidColorBrush)new BrushConverter().ConvertFromString(color); value.Freeze(); return value; }
        public static void Initialize(Application app) {
            using (var input = File.OpenRead(Path.Combine(DesktopSettings.Root, @"src\desktop\Theme.xaml"))) app.Resources.MergedDictionaries.Add((ResourceDictionary)XamlReader.Load(input));
            string fontDirectory = new Uri(Path.Combine(DesktopSettings.Root, @"assets\fonts") + Path.DirectorySeparatorChar).AbsoluteUri;
            GlyphTypeface face;
            if (!new Typeface(new FontFamily(fontDirectory + "#Source Han Serif SC"), FontStyles.Normal, FontWeights.Normal, FontStretches.Normal).TryGetGlyphTypeface(out face)) throw new InvalidOperationException("界面字体文件不完整，请检查 assets/fonts 文件夹。");
            FontEvidence = face.FontUri.AbsoluteUri;
            Serif = new FontFamily();
            Serif.FamilyMaps.Add(new FontFamilyMap { Unicode = "0000-02FF", Target = "Times New Roman" });
            Serif.FamilyMaps.Add(new FontFamilyMap { Unicode = "0300-10FFFF", Target = fontDirectory + "#Source Han Serif SC" });
            // Explicit Window.FontFamily makes all child text and controls inherit the composite family.
        }
        public static void Chrome(Window window) {
            window.FontFamily = Serif; window.Foreground = Ink;
            window.Background = Brush("#111210");
            WindowChrome.SetWindowChrome(window, new WindowChrome { CaptionHeight = 39, ResizeBorderThickness = new Thickness(6), CornerRadius = new CornerRadius(12), GlassFrameThickness = new Thickness(0), UseAeroCaptionButtons = false });
            window.SourceInitialized += delegate {
                try { int enabled = 1, round = 2; var handle = new WindowInteropHelper(window).Handle; DwmSetWindowAttribute(handle, 20, ref enabled, 4); DwmSetWindowAttribute(handle, 33, ref round, 4); } catch { }
            };
            var drawing = new DrawingGroup();
            using (DrawingContext dc = drawing.Open()) {
                dc.DrawRoundedRectangle(Brush("#191A17"), null, new Rect(0, 0, 64, 64), 14, 14);
                dc.DrawRoundedRectangle(Gold, null, new Rect(15, 34, 6, 15), 2, 2);
                dc.DrawRoundedRectangle(Gold, null, new Rect(29, 25, 6, 24), 2, 2);
                dc.DrawRoundedRectangle(Gold, null, new Rect(43, 15, 6, 34), 2, 2);
            }
            window.Icon = new DrawingImage(drawing);
        }
        [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);
        public static TextBlock Text(string text, double size, Brush foreground) { return new TextBlock { Text = text, FontSize = size, Foreground = foreground, TextWrapping = TextWrapping.Wrap }; }
        public static Button Button(string text, RoutedEventHandler action) { var button = new Button { Content = text }; if (action != null) button.Click += action; return button; }
        public static Border Divider() { return new Border { Height = 1, Background = Line, Margin = new Thickness(0, 18, 0, 18) }; }
        public static Window Dialog(Window owner, string title, double width, double height, out StackPanel body) {
            var window = new Window { Owner = owner, Title = title, Width = width, Height = Math.Min(height, SystemParameters.WorkArea.Height - 40), WindowStartupLocation = owner == null ? WindowStartupLocation.CenterScreen : WindowStartupLocation.CenterOwner, WindowStyle = WindowStyle.None, ResizeMode = ResizeMode.NoResize, ShowInTaskbar = false, UseLayoutRounding = true };
            Chrome(window);
            var grid = new Grid(); grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(40) }); grid.RowDefinitions.Add(new RowDefinition());
            var close = Button("×", delegate { window.Close(); }); close.Width = 38; close.FontFamily = new FontFamily("Times New Roman"); close.FontSize = 24; close.Padding = new Thickness(0); close.HorizontalAlignment = HorizontalAlignment.Right; close.Margin = new Thickness(0, 2, 7, 0); WindowChrome.SetIsHitTestVisibleInChrome(close, true); grid.Children.Add(close);
            body = new StackPanel { Margin = new Thickness(28, 5, 28, 25) };
            var scroll = new ScrollViewer { Content = body, VerticalScrollBarVisibility = ScrollBarVisibility.Auto }; Grid.SetRow(scroll, 1); grid.Children.Add(scroll);
            window.Content = new Border { Child = grid, Background = Panel, BorderBrush = Line, BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(16) };
            window.PreviewKeyDown += delegate(object sender, System.Windows.Input.KeyEventArgs e) { if (e.Key == System.Windows.Input.Key.Escape) window.Close(); };
            return window;
        }
        public static void Snapshot(Window window, string path, double scale) {
            window.UpdateLayout(); var target = new RenderTargetBitmap((int)Math.Ceiling(window.ActualWidth * scale), (int)Math.Ceiling(window.ActualHeight * scale), 96 * scale, 96 * scale, PixelFormats.Pbgra32); target.Render(window);
            Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))); var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(target)); using (var output = File.Create(path)) encoder.Save(output);
        }
    }
}
