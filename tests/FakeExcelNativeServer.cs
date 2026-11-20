// Test-only native object-model server. Never include this in a colleague package.
using System;
using System.IO;
using System.Text;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows.Forms;

[ComVisible(true),ClassInterface(ClassInterfaceType.AutoDual)]
public class FakeNativeApplication : StandardOleMarshalObject {
 public long Hwnd { get; set; }
 public bool ScreenUpdating {get;set;}
 public bool Interactive {get;set;}
 public long RevealWindow(){return FakeExcelNativeServer.Reveal().ToInt64();}
 bool visible=true,alerts=true;
 public bool Visible { get{return visible;} set{visible=value;Snapshot();} }
 public bool DisplayAlerts { get{return alerts;} set{alerts=value;Snapshot();} }
 public void Quit(){Snapshot();FakeExcelNativeServer.Close();}
 public void Snapshot(){var directory=Environment.GetEnvironmentVariable("SENTIMENT_FAKE_EXCEL_STATE");if(!String.IsNullOrEmpty(directory))File.WriteAllText(Path.Combine(directory,Process.GetCurrentProcess().Id+".txt"),"visible="+visible+";alerts="+alerts);}
}
[ComVisible(true),ClassInterface(ClassInterfaceType.AutoDual)]
public class FakeNativeWindow : StandardOleMarshalObject { public object Application { get; set; } }
public static class FakeExcelNativeServer {
 delegate IntPtr Procedure(IntPtr hwnd,uint msg,IntPtr wParam,IntPtr lParam);
 [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)]struct WindowClass {public uint size,style;public Procedure proc;public int clsExtra,wndExtra;public IntPtr instance,icon,cursor,background;public string menu,name;public IntPtr smallIcon;}
 [DllImport("user32.dll",CharSet=CharSet.Unicode)]static extern ushort RegisterClassEx(ref WindowClass c);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)]static extern IntPtr CreateWindowEx(uint ex,string cls,string text,uint style,int x,int y,int w,int h,IntPtr parent,IntPtr menu,IntPtr instance,IntPtr param);
 [DllImport("user32.dll")]static extern IntPtr DefWindowProc(IntPtr hwnd,uint msg,IntPtr wParam,IntPtr lParam);
 [DllImport("user32.dll")]static extern bool PostMessage(IntPtr h,uint msg,IntPtr w,IntPtr l);
 [DllImport("user32.dll")]static extern void PostQuitMessage(int code);
 [DllImport("user32.dll")]static extern bool ShowWindow(IntPtr hwnd,int command);
 [DllImport("ole32.dll")]static extern int OleInitialize(IntPtr reserved);
 [DllImport("oleacc.dll")]static extern IntPtr LresultFromObject(ref Guid iid,IntPtr wParam,[MarshalAs(UnmanagedType.IUnknown)]object value);
 static Procedure procedure=Handle;static IntPtr root;static FakeNativeWindow window;
 public static void Close(){PostMessage(root,0x10,IntPtr.Zero,IntPtr.Zero);}
 public static IntPtr Reveal(){var h=CreateWindowEx(0,"XLMAIN","Test-only popup",0,-20000,-20000,100,100,IntPtr.Zero,IntPtr.Zero,IntPtr.Zero,IntPtr.Zero);ShowWindow(h,4);return h;}
 static IntPtr Handle(IntPtr h,uint msg,IntPtr w,IntPtr l){
  if(msg==0x3d&&unchecked((uint)l.ToInt64())==0xfffffff0){Guid iid=new Guid("00020400-0000-0000-C000-000000000046");return LresultFromObject(ref iid,w,window);}
  if(msg==0x10){PostQuitMessage(0);return IntPtr.Zero;}return DefWindowProc(h,msg,w,l);
 }
 static void Register(string name){var c=new WindowClass{size=(uint)Marshal.SizeOf(typeof(WindowClass)),proc=procedure,name=name};if(RegisterClassEx(ref c)==0)throw new Exception("RegisterClass failed");}
 [STAThread]public static void Main(){
  OleInitialize(IntPtr.Zero);Register("XLMAIN");Register("EXCEL7");
  root=CreateWindowEx(0,"XLMAIN","Test-only Excel model",0,-20000,-20000,100,100,IntPtr.Zero,IntPtr.Zero,IntPtr.Zero,IntPtr.Zero);
  var app=new FakeNativeApplication{Hwnd=root.ToInt64()};window=new FakeNativeWindow{Application=app};app.Snapshot();
  if(Environment.GetEnvironmentVariable("SENTIMENT_FAKE_EXCEL_MODE")!="no-window")CreateWindowEx(0,"EXCEL7","",0x40000000,0,0,20,20,root,IntPtr.Zero,IntPtr.Zero,IntPtr.Zero);
  Application.Run();
 }
}
