using System;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;

namespace SentimentDesktop {
    internal static class NativeDialogs {
        public static string ImportHistory(Window owner) {
            var dialog = new Microsoft.Win32.OpenFileDialog { Title = "导入月度交接历史", Filter = "情绪指数历史文件 (*.json)|*.json", CheckFileExists = true, Multiselect = false };
            return dialog.ShowDialog(owner) == true ? dialog.FileName : null;
        }
        public static string ExportHistory(Window owner, string lastDate) {
            var dialog = new Microsoft.Win32.SaveFileDialog { Title = "导出完整历史交接文件", Filter = "情绪指数历史文件 (*.json)|*.json", DefaultExt = ".json", AddExtension = true, OverwritePrompt = true,
                InitialDirectory = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), FileName = "情绪指数历史交接_截至" + lastDate.Replace("-", "") + ".json" };
            return dialog.ShowDialog(owner) == true ? dialog.FileName : null;
        }
        public static string Folder(Window owner, string initial) {
            var dialog = (IFileOpenDialog)new FileOpenDialog(); IShellItem result = null;
            try {
                dialog.SetOptions(0x20 | 0x40 | 0x800 | 0x1000); dialog.SetTitle("选择报告保存目录"); dialog.SetOkButtonLabel("选择此文件夹");
                IShellItem folder; if (System.IO.Directory.Exists(initial) && SHCreateItemFromParsingName(initial, IntPtr.Zero, typeof(IShellItem).GUID, out folder) == 0) { try { dialog.SetFolder(folder); } finally { Marshal.ReleaseComObject(folder); } }
                int hr = dialog.Show(new WindowInteropHelper(owner).Handle); if (hr == unchecked((int)0x800704C7)) return null; Marshal.ThrowExceptionForHR(hr);
                dialog.GetResult(out result); IntPtr pointer; result.GetDisplayName(0x80058000, out pointer); try { return Marshal.PtrToStringUni(pointer); } finally { Marshal.FreeCoTaskMem(pointer); }
            } finally { if (result != null) Marshal.ReleaseComObject(result); Marshal.ReleaseComObject(dialog); }
        }
        [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = true)] static extern int SHCreateItemFromParsingName(string path, IntPtr context, [MarshalAs(UnmanagedType.LPStruct)] Guid id, out IShellItem item);
        [ComImport, Guid("DC1C5A9C-E88A-4DDE-A5A1-60F82A20AEF7")] class FileOpenDialog { }
        [ComImport, Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface IShellItem {
            void BindToHandler(IntPtr context, ref Guid handler, ref Guid id, out IntPtr output); void GetParent(out IShellItem parent); void GetDisplayName(uint name, out IntPtr text); void GetAttributes(uint mask, out uint attributes); void Compare(IShellItem other, uint hint, out int order);
        }
        [ComImport, Guid("D57C7288-D4AD-4768-BE02-9D969532D960"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface IFileOpenDialog {
            [PreserveSig] int Show(IntPtr parent);
            void SetFileTypes(uint count, IntPtr filters); void SetFileTypeIndex(uint index); void GetFileTypeIndex(out uint index); void Advise(IntPtr events, out uint cookie); void Unadvise(uint cookie); void SetOptions(uint options); void GetOptions(out uint options); void SetDefaultFolder(IShellItem folder); void SetFolder(IShellItem folder); void GetFolder(out IShellItem folder); void GetCurrentSelection(out IShellItem item); void SetFileName([MarshalAs(UnmanagedType.LPWStr)] string name); void GetFileName([MarshalAs(UnmanagedType.LPWStr)] out string name); void SetTitle([MarshalAs(UnmanagedType.LPWStr)] string title); void SetOkButtonLabel([MarshalAs(UnmanagedType.LPWStr)] string label); void SetFileNameLabel([MarshalAs(UnmanagedType.LPWStr)] string label); void GetResult(out IShellItem item); void AddPlace(IShellItem item, uint position); void SetDefaultExtension([MarshalAs(UnmanagedType.LPWStr)] string extension); void Close(int hr); void SetClientGuid(ref Guid guid); void ClearClientData(); void SetFilter(IntPtr filter); void GetResults(out IntPtr results); void GetSelectedItems(out IntPtr items);
        }
    }
}
