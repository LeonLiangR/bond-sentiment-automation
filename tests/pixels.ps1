param([string]$Expected,[string]$Actual)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;using System.Drawing;using System.Drawing.Imaging;using System.Runtime.InteropServices;
public static class Pixels {
 public static int Compare(string x,string y){
  using(var a=new Bitmap(x))using(var b=new Bitmap(y)){
   if(a.Size!=b.Size)throw new Exception("Image dimensions differ");
   var r=new Rectangle(0,0,a.Width,a.Height);
   var aa=a.LockBits(r,ImageLockMode.ReadOnly,PixelFormat.Format32bppArgb);
   var bb=b.LockBits(r,ImageLockMode.ReadOnly,PixelFormat.Format32bppArgb);
   try{
    int size=Math.Abs(aa.Stride)*a.Height;byte[] p=new byte[size],q=new byte[size];
    Marshal.Copy(aa.Scan0,p,0,size);Marshal.Copy(bb.Scan0,q,0,size);int n=0;
    for(int i=0;i<size;i+=4)if(p[i]!=q[i]||p[i+1]!=q[i+1]||p[i+2]!=q[i+2]||p[i+3]!=q[i+3])n++;
    return n;
   }finally{a.UnlockBits(aa);b.UnlockBits(bb);}
  }
 }
}
'@
$different=[Pixels]::Compare([IO.Path]::GetFullPath($Expected),[IO.Path]::GetFullPath($Actual))
Write-Output ($different.ToString()+' different pixels')
if($different -ne 0){throw 'Chart pixels changed'}
