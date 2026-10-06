# Sonda para validar el clic a través y la barra de tareas sin tocar el mouse del usuario
# más de lo necesario.
#   -Action hit   -X -Y : qué ventana recibiría un clic en ese punto (WindowFromPoint ignora
#                         las ventanas WS_EX_TRANSPARENT, igual que el sistema al enrutar clics)
#   -Action move  -X -Y : mueve el cursor allí
#   -Action click -X -Y : mueve y hace clic izquierdo (SendInput)
#   -Action find  -Title T : lista ventanas visibles del proceso Godot (estilos y si están en Alt-Tab)
param(
    [ValidateSet("hit", "move", "click", "find")][string]$Action = "hit",
    [int]$X = 0, [int]$Y = 0,
    [string]$Title = "Taskbar"
)
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class W {
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X; public int Y; }
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
  [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint f);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
  [DllImport("user32.dll")] public static extern IntPtr GetWindowLongPtr(IntPtr h, int i);
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc p, IntPtr l);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
}
"@
[W]::SetProcessDPIAware() | Out-Null

function Describe([IntPtr]$h) {
    $root = [W]::GetAncestor($h, 2)
    $sb = New-Object System.Text.StringBuilder 256
    [W]::GetWindowText($root, $sb, 256) | Out-Null
    $cb = New-Object System.Text.StringBuilder 256
    [W]::GetClassName($root, $cb, 256) | Out-Null
    $procId = 0
    [W]::GetWindowThreadProcessId($root, [ref]$procId) | Out-Null
    $p = (Get-Process -Id $procId -ErrorAction SilentlyContinue).ProcessName
    $ex = [W]::GetWindowLongPtr($root, -20).ToInt64()
    "hwnd=0x{0:X} proc={1} class={2} title='{3}' exstyle=0x{4:X}" -f $root.ToInt64(), $p, $cb, $sb, $ex
}

switch ($Action) {
    "hit" {
        $pt = New-Object W+POINT; $pt.X = $X; $pt.Y = $Y
        Describe ([W]::WindowFromPoint($pt))
    }
    "move" { [W]::SetCursorPos($X, $Y) | Out-Null; "moved $X,$Y" }
    "click" {
        [W]::SetCursorPos($X, $Y) | Out-Null
        Start-Sleep -Milliseconds 120
        [W]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
        Start-Sleep -Milliseconds 40
        [W]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
        "clicked $X,$Y"
    }
    "find" {
        $script:out = @()
        $cb = [W+EnumProc] {
            param($h, $l)
            if ([W]::IsWindowVisible($h)) {
                $procId = 0
                [W]::GetWindowThreadProcessId($h, [ref]$procId) | Out-Null
                $p = (Get-Process -Id $procId -ErrorAction SilentlyContinue).ProcessName
                if ($p -like "Godot*") {
                    $ex = [W]::GetWindowLongPtr($h, -20).ToInt64()
                    $tool = ($ex -band 0x80) -ne 0
                    $app = ($ex -band 0x40000) -ne 0
                    $script:out += ("{0} toolwindow={1} appwindow={2} transparent={3} layered={4}" -f (Describe $h), $tool, $app, (($ex -band 0x20) -ne 0), (($ex -band 0x80000) -ne 0))
                }
            }
            return $true
        }
        [W]::EnumWindows($cb, [IntPtr]::Zero) | Out-Null
        $script:out
    }
}
