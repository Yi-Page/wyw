param(
  [Parameter(Mandatory=$true)][string]$Playlist,
  [Parameter(Mandatory=$true)][int]$AdFilter,
  [Parameter(Mandatory=$true)][string]$LogFile,
  [int]$TimeoutSec = 120,
  [switch]$WithAudio,
  [switch]$Timed,
  [string]$Ao = 'null',
  [string]$AoPcmFile = '',
  [switch]$NoForceDemuxer
)

$dll = 'D:\development\AndroidStudioProjects\wyw\build\windows\x64\libmpv\libmpv-2.dll'

if (-not ("MpvNative" -as [type])) {
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
[StructLayout(LayoutKind.Sequential)]
public struct MpvEvent { public int event_id; public int error; public ulong reply_userdata; public IntPtr data; }
public static class MpvNative {
  [DllImport(@"$dll", CallingConvention=CallingConvention.Cdecl)] public static extern IntPtr mpv_create();
  [DllImport(@"$dll", CallingConvention=CallingConvention.Cdecl)] public static extern int mpv_initialize(IntPtr h);
  [DllImport(@"$dll", CallingConvention=CallingConvention.Cdecl)] public static extern int mpv_set_option_string(IntPtr h, string name, string val);
  [DllImport(@"$dll", CallingConvention=CallingConvention.Cdecl)] public static extern int mpv_command_string(IntPtr h, string cmd);
  [DllImport(@"$dll", CallingConvention=CallingConvention.Cdecl)] public static extern IntPtr mpv_get_property_string(IntPtr h, string name);
  [DllImport(@"$dll", CallingConvention=CallingConvention.Cdecl)] public static extern void mpv_free(IntPtr p);
  [DllImport(@"$dll", CallingConvention=CallingConvention.Cdecl)] public static extern IntPtr mpv_wait_event(IntPtr h, double timeout);
  [DllImport(@"$dll", CallingConvention=CallingConvention.Cdecl)] public static extern void mpv_terminate_destroy(IntPtr h);
  [DllImport(@"$dll", CallingConvention=CallingConvention.Cdecl)] public static extern string mpv_error_string(int code);
}
"@
}

function Get-MpvProp([IntPtr]$h, [string]$name) {
  $p = [MpvNative]::mpv_get_property_string($h, $name)
  if ($p -eq [IntPtr]::Zero) { return $null }
  $s = [System.Runtime.InteropServices.Marshal]::PtrToStringAnsi($p)
  [MpvNative]::mpv_free($p)
  return $s
}

if (Test-Path $LogFile) { Remove-Item $LogFile -Force }
$h = [MpvNative]::mpv_create()
if ($h -eq [IntPtr]::Zero) { throw 'mpv_create failed' }

$ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36 Edg/134.0.0.0'
$lavf = "seg_max_retry=5,strict=experimental,allowed_extensions=ALL,hls_ad_filter=$AdFilter,protocol_whitelist=[file,http,https,tcp,tls,crypto,data]"
$opts = @{
  'config'          = 'no'
  'terminal'        = 'no'
  'vo'              = 'null'
  'ao'              = $Ao
  'audio'           = $(if ($WithAudio) { 'yes' } else { 'no' })
  'untimed'         = $(if ($Timed) { 'no' } else { 'yes' })
  'cache'           = 'no'
  'hr-seek'         = 'yes'
  'keep-open'       = 'yes'
  'load-scripts'    = 'no'
  'input-default-bindings' = 'no'
  'user-agent'      = $ua
  'referrer'        = ''
  'demuxer-lavf-o'  = $lavf
  'msg-level'       = 'all=v'
  'log-file'        = $LogFile
}
if (-not $NoForceDemuxer) { $opts['demuxer'] = 'lavf' }
if ($AoPcmFile -ne '') { $opts['ao-pcm-file'] = $AoPcmFile }
foreach ($k in $opts.Keys) {
  $rc = [MpvNative]::mpv_set_option_string($h, $k, [string]$opts[$k])
  if ($rc -lt 0) { Write-Output "set_option $k failed: $([MpvNative]::mpv_error_string($rc))" }
}
$rc = [MpvNative]::mpv_initialize($h)
Write-Output "init rc=$rc"
$playlistArg = $Playlist -replace '\\','/'
$rc = [MpvNative]::mpv_command_string($h, 'loadfile "' + $playlistArg + '"')
Write-Output "loadfile rc=$rc"

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$ended = $false
$lastPos = ''
while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
  $evPtr = [MpvNative]::mpv_wait_event($h, 0.2)
  if ($evPtr -ne [IntPtr]::Zero) {
    $ev = [System.Runtime.InteropServices.Marshal]::PtrToStructure($evPtr, [type][MpvEvent])
    if ($ev.event_id -eq 7) { $ended = $true; break }
  }
  $eof = Get-MpvProp $h 'eof-reached'
  $pos = Get-MpvProp $h 'time-pos'
  if ($pos) { $lastPos = $pos }
  if ($eof -eq 'yes') { $ended = $true; break }
}
$dur = Get-MpvProp $h 'duration'
Write-Output ("RESULT adfilter=$AdFilter ended=$ended elapsed={0:N1}s duration={1} lastTimePos={2}" -f $sw.Elapsed.TotalSeconds, $dur, $lastPos)
Start-Sleep -Milliseconds 300
[MpvNative]::mpv_terminate_destroy($h)
Write-Output "log=$LogFile size=$((Get-Item $LogFile -ErrorAction SilentlyContinue).Length)"
