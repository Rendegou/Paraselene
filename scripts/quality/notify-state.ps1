$code = @'
using System;
using System.Runtime.InteropServices;
public class Ns {
  [DllImport("shell32.dll")]
  public static extern int SHQueryUserNotificationState(out int state);
}
'@
Add-Type -TypeDefinition $code -ReferencedAssemblies System
$state = 0
[Ns]::SHQueryUserNotificationState([ref]$state) | Out-Null
Write-Output "NOTIFY_STATE=$state"
