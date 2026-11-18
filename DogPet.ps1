# =====================================================================
#  DogPet.ps1  -  animated desktop dog + AI assistant (Windows)
#  No install needed (uses the PowerShell built into Windows).
#
#  DogPet\DogPet.bat       double-click this to start
#  DogPet\DogPet.ps1       this file
#  DogPet\knowledge.txt    optional offline coding notes
#  DogPet\sounds\bark.wav  optional real bark sound
#
#  AI brain: right-click the dog > "AI brain setup..." (Google Gemini key is free)
# =====================================================================
$PartCheck = @{}

try {
  Add-Type -TypeDefinition 'using System.Runtime.InteropServices; public class DpiFix { [DllImport("user32.dll")] public static extern bool SetProcessDPIAware(); }'
  $null = [DpiFix]::SetProcessDPIAware()
} catch { }

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing, Microsoft.VisualBasic

# NOTE: PowerShell variable names are NOT case sensitive ($H and $h are the same!)

$AppDir = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($AppDir)) { $AppDir = (Get-Location).Path }
$ImgDir = Join-Path $AppDir 'images'
$SndDir = Join-Path $AppDir 'sounds'
$KbFile = Join-Path $AppDir 'knowledge.txt'

function Emj($code) { return [char]::ConvertFromUtf32($code) }
$EM = @{
  water = (Emj 0x1F4A7); dog = (Emj 0x1F436); paw = (Emj 0x1F43E); heart = (Emj 0x2764)
  eyes = (Emj 0x1F440); bell = (Emj 0x1F514); bone = (Emj 0x1F356); cookie = (Emj 0x1F36A)
  ball = (Emj 0x26BD); sleepy = (Emj 0x1F4A4); star = (Emj 0x2B50); clock = (Emj 0x23F0)
  book = (Emj 0x1F4D6); think = (Emj 0x1F914); muscle = (Emj 0x1F4AA); wave = (Emj 0x1F44B)
}

# ---------- saved settings ----------
$dataDir  = Join-Path $env:APPDATA 'DogPet'
$dataFile = Join-Path $dataDir 'data.json'
$logFile  = Join-Path $dataDir 'error.log'
if (-not (Test-Path $dataDir)) { New-Item -ItemType Directory -Path $dataDir | Out-Null }

$cfg = @{
  dogName = 'Buddy'; userName = ''; waterMinutes = 45; waterGoal = 8; breakMinutes = 60; breakOn = $true
  follow = $false; talk = $false; sounds = $true; notify = $true; size = 'medium'
  glasses = 0; glassesDate = (Get-Date).ToString('yyyy-MM-dd'); fullness = 80.0; happiness = 80.0
  todos = @(); reminders = @()
}
$cfgKeys = @('dogName','userName','waterMinutes','waterGoal','breakMinutes','breakOn','follow','talk','sounds','notify','size','glasses','glassesDate','fullness','happiness')
if (Test-Path $dataFile) {
  try {
    $saved = Get-Content $dataFile -Raw | ConvertFrom-Json
    foreach ($key in $cfgKeys) { if ($null -ne $saved.$key) { $cfg[$key] = $saved.$key } }
    if ($null -ne $saved.todos) { $cfg.todos = @($saved.todos) }
    if ($null -ne $saved.reminders) { $cfg.reminders = @($saved.reminders) }
  } catch { }
}

$script:logCount = 0
function Write-Log($err) {
  $script:logCount++
  if ($script:logCount -gt 40) { return }
  $msg = '[' + (Get-Date) + '] ' + ($err | Out-String)
  try { Add-Content -Path $logFile -Value $msg } catch { }
  try { Write-Host $msg } catch { }
}
function Save-Cfg {
  try {
    if ($null -ne $PET) {
      $list = @()
      foreach ($rem in $PET.reminders) { $list += @{ at = $rem.at.ToString('o'); text = [string]$rem.text } }
      $cfg.reminders = $list
    }
    $cfg | ConvertTo-Json -Depth 5 | Set-Content -Path $dataFile -Encoding UTF8
  } catch { Write-Log $_ }
}
function Update-DayCounter {
  $today = (Get-Date).ToString('yyyy-MM-dd')
  if ($cfg.glassesDate -ne $today) { $cfg.glassesDate = $today; $cfg.glasses = 0 }
}
Update-DayCounter

# ---------- first run: ask the user's name ----------
if ([string]::IsNullOrWhiteSpace($cfg.userName)) {
  $answer = [Microsoft.VisualBasic.Interaction]::InputBox('What is your name? (I will use it when I talk to you)', 'Dog Pet - Hello!', '')
  if ([string]::IsNullOrWhiteSpace($answer)) { $cfg.userName = 'friend' } else { $cfg.userName = $answer.Trim() }
  Save-Cfg
}

# ---------- C# helper (makes the bark sound) ----------
$DogAudioCode = @'
using System;
using System.IO;
public static class DogAudio {
  public static byte[] MakeBark(int seed) {
    int rate = 22050;
    Random rnd = new Random(seed);
    int n = (int)(rate * 0.48);
    short[] data = new short[n];
    double[] starts = new double[] { 0.0, 0.24 };
    for (int b = 0; b < starts.Length; b++) {
      int s0 = (int)(starts[b] * rate);
      int len = (int)(0.17 * rate);
      double phase = 0.0;
      for (int i = 0; i < len && s0 + i < n; i++) {
        double p = (double)i / len;
        double f = (b == 0 ? 560.0 : 500.0) - 320.0 * p;
        phase += 2.0 * Math.PI * f / rate;
        double env = (p < 0.06) ? p / 0.06 : Math.Pow(1.0 - (p - 0.06) / 0.94, 2.0);
        double tone = Math.Sin(phase) + 0.6 * Math.Sin(2.0 * phase) + 0.3 * Math.Sin(3.0 * phase) + 0.15 * Math.Sin(5.0 * phase);
        double noise = rnd.NextDouble() * 2.0 - 1.0;
        double v = (tone * 0.5 + noise * 0.45 * (1.0 - p)) * env;
        v = Math.Tanh(v * 1.8) * 0.85;
        data[s0 + i] = (short)(v * 32000.0);
      }
    }
    using (MemoryStream ms = new MemoryStream()) {
      BinaryWriter w = new BinaryWriter(ms);
      w.Write(new char[] { 'R', 'I', 'F', 'F' });
      w.Write(36 + n * 2);
      w.Write(new char[] { 'W', 'A', 'V', 'E', 'f', 'm', 't', ' ' });
      w.Write(16);
      w.Write((short)1);
      w.Write((short)1);
      w.Write(rate);
      w.Write(rate * 2);
      w.Write((short)2);
      w.Write((short)16);
      w.Write(new char[] { 'd', 'a', 't', 'a' });
      w.Write(n * 2);
      for (int k = 0; k < n; k++) { w.Write(data[k]); }
      w.Flush();
      return ms.ToArray();
    }
  }
}
'@

# ---------- bark sound ----------
$BarkPlayer = $null
try {
  $wavFile = Join-Path $SndDir 'bark.wav'
  if (Test-Path $wavFile) {
    $BarkPlayer = New-Object System.Media.SoundPlayer $wavFile
  } else {
    Add-Type -TypeDefinition $DogAudioCode -IgnoreWarnings
    $barkBytes = [DogAudio]::MakeBark(7)
    $barkStream = [System.IO.MemoryStream]::new($barkBytes)
    $BarkPlayer = [System.Media.SoundPlayer]::new($barkStream)
  }
  $BarkPlayer.Load()
} catch { $BarkPlayer = $null; Write-Log $_ }

# ---------- talking (Windows text-to-speech) ----------
$Voice = $null
try {
  Add-Type -AssemblyName System.Speech
  $Voice = New-Object System.Speech.Synthesis.SpeechSynthesizer
  $Voice.Volume = 100
  $Voice.Rate = 1
} catch { $Voice = $null }

# ---------- the dog window ----------
[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Dog Pet" Width="260" Height="280"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Topmost="True" ShowInTaskbar="False" ResizeMode="NoResize"
        ShowActivated="False" WindowStartupLocation="Manual">
  <Grid>
    <Border x:Name="Bubble" Visibility="Collapsed" VerticalAlignment="Top" HorizontalAlignment="Center"
            Margin="0,4,0,0" MaxWidth="240" Background="White" BorderBrush="#333333" BorderThickness="2"
            CornerRadius="12" Padding="10,5">
      <TextBlock x:Name="BubbleText" TextWrapping="Wrap" FontSize="14" FontWeight="SemiBold"
                 Foreground="#222222" TextAlignment="Center"/>
    </Border>

    <Grid x:Name="DogHost" Width="200" Height="170" VerticalAlignment="Bottom" HorizontalAlignment="Center"
          Background="#01FFFFFF">
      <Ellipse x:Name="Shadow" Width="110" Height="14" Fill="Black" Opacity="0.22"
               VerticalAlignment="Bottom" HorizontalAlignment="Center" Margin="0,0,0,-4" RenderTransformOrigin="0.5,0.5">
        <Ellipse.RenderTransform><ScaleTransform x:Name="ShadowScale" ScaleX="1" ScaleY="1"/></Ellipse.RenderTransform>
      </Ellipse>

      <Grid x:Name="Actor" RenderTransformOrigin="0.5,1">
        <Grid.RenderTransform>
          <TransformGroup>
            <ScaleTransform x:Name="ActScale" ScaleX="1" ScaleY="1"/>
            <TranslateTransform x:Name="ActMove" X="0" Y="0"/>
          </TransformGroup>
        </Grid.RenderTransform>
        <Grid x:Name="Spinner" RenderTransformOrigin="0.5,0.55">
          <Grid.RenderTransform><RotateTransform x:Name="ActRot" Angle="0"/></Grid.RenderTransform>

          <!-- REAL DOG PHOTO -->
          <Image x:Name="DogPhoto" Visibility="Collapsed" Stretch="Uniform"
                 VerticalAlignment="Bottom" HorizontalAlignment="Center"
                 RenderOptions.BitmapScalingMode="HighQuality"/>

          <!-- REALISTIC DRAWN GOLDEN RETRIEVER -->
          <Viewbox x:Name="DrawnDog" Width="190" Height="148" VerticalAlignment="Bottom" HorizontalAlignment="Center" Stretch="Uniform">
            <Viewbox.Resources>
              <LinearGradientBrush x:Key="DFur" StartPoint="0,0" EndPoint="0,1">
                <GradientStop Color="#F0C27F" Offset="0"/><GradientStop Color="#E3A85E" Offset="0.45"/><GradientStop Color="#CF9248" Offset="1"/>
              </LinearGradientBrush>
              <LinearGradientBrush x:Key="DFurL" StartPoint="0,0" EndPoint="1,1">
                <GradientStop Color="#F6D29A" Offset="0"/><GradientStop Color="#EBB66C" Offset="1"/>
              </LinearGradientBrush>
              <LinearGradientBrush x:Key="DCream" StartPoint="0,0" EndPoint="0,1">
                <GradientStop Color="#FBE9C6" Offset="0"/><GradientStop Color="#EFCF98" Offset="1"/>
              </LinearGradientBrush>
            </Viewbox.Resources>
            <Canvas Width="210" Height="164">
              <Canvas>
                <Canvas.RenderTransform><TranslateTransform Y="20"/></Canvas.RenderTransform>
            <Canvas>
              <Canvas.RenderTransform>
                <TransformGroup>
                  <RotateTransform x:Name="DBodyR" CenterX="62" CenterY="92" Angle="0"/>
                  <TranslateTransform x:Name="DBodyT" X="0" Y="0"/>
                </TransformGroup>
              </Canvas.RenderTransform>
              <Canvas>
                <Canvas.RenderTransform>
                  <RotateTransform x:Name="DFBUR" CenterX="68" CenterY="68" Angle="0"/>
                </Canvas.RenderTransform>
                <Path Data="M52,62 C46,78 54,96 68,100 C78,100 86,92 86,80 C86,68 78,58 66,58 C58,58 54,60 52,62 Z" Fill="#B07636"/>
                <Canvas>
                  <Canvas.RenderTransform>
                    <RotateTransform x:Name="DFBLR" CenterX="74" CenterY="98" Angle="0"/>
                  </Canvas.RenderTransform>
                  <Path Data="M70,94 C76,92 82,96 80,102 L72,120 C71,126 72,132 74,136 L64,137 C63,130 63,124 64,118 L66,102 C66,98 67,95 70,94 Z" Fill="#B07636"/>
                  <Path Data="M61,137 C61,135.067 64.5816,133.5 69,133.5 C73.4184,133.5 77,135.067 77,137 C77,138.933 73.4184,140.5 69,140.5 C64.5816,140.5 61,138.933 61,137 Z" Fill="#C98B47"/>
                </Canvas>
              </Canvas>
              <Canvas>
                <Canvas.RenderTransform>
                  <RotateTransform x:Name="DFFUR" CenterX="138" CenterY="62" Angle="0"/>
                </Canvas.RenderTransform>
                <Path Data="M129,58 C125,72 127,86 131,96 L145,96 C149,84 151,70 147,60 C143,54 133,54 129,58 Z" Fill="#B07636"/>
                <Canvas>
                  <Canvas.RenderTransform>
                    <RotateTransform x:Name="DFFLR" CenterX="137" CenterY="94" Angle="0"/>
                  </Canvas.RenderTransform>
                  <Path Data="M131,92 L143,92 C144,106 143,122 143,132 C144,135 146,136 148,137 L133,137 C132,124 132,106 131,92 Z" Fill="#B07636"/>
                  <Path Data="M131.5,137 C131.5,135.067 135.305,133.5 140,133.5 C144.695,133.5 148.5,135.067 148.5,137 C148.5,138.933 144.695,140.5 140,140.5 C135.305,140.5 131.5,138.933 131.5,137 Z" Fill="#C98B47"/>
                </Canvas>
              </Canvas>
              <Canvas>
                <Canvas.RenderTransform>
                  <RotateTransform x:Name="DTailR" CenterX="46" CenterY="56" Angle="0"/>
                </Canvas.RenderTransform>
                <Path Data="M48,60 C36,52 26,42 22,30 C21,23 24,19 28,22 C31,34 40,44 52,50 Z" Fill="#C98B47"/>
                <Path Data="M47,61 C35,63 25,56 18,46 C21,47 22,46 20,42 C23,43 24,42 22,37 C25,38 27,38 27,37 C31,46 39,52 50,54 Z" Fill="{StaticResource DFurL}" Opacity="0.95"/>
                <Path Data="M30,40 C27,34 25,28 26,24 C28,30 30,35 33,39 Z" Fill="{StaticResource DFurL}" Opacity="0.7"/>
              </Canvas>
              <Path x:Name="DTorso" Data="M44,66 C42,50 62,40 92,40 C120,40 140,44 150,58 C158,72 154,92 140,98 C128,102 116,96 104,90 C92,86 80,86 70,88 C54,90 46,80 44,66 Z" Fill="{StaticResource DFur}"/>
              <Path Data="M58,46 C80,40 110,40 132,46 C116,44 90,44 60,50 Z" Fill="{StaticResource DFurL}" Opacity="0.9"/>
              <Path Data="M60,84 C80,80 110,84 140,96 C120,92 92,88 64,90 Z" Fill="#A86E30" Opacity="0.35"/>
              <Path Data="M120,52 C132,58 140,70 142,84 C136,72 128,62 118,56 Z" Fill="#A86E30" Opacity="0.25"/>
              <Path Data="M100,88 C104,96 106,96 108,93 C110,99 113,99 116,95 C118,101 122,101 124,97 C126,103 130,103 132,99 C134,104 138,103 140,98 L143,93 C130,98 114,94 100,88 Z" Fill="#EBC88E"/>
              <Path Data="M70,86 C72,92 75,92 77,89 C79,93 82,93 85,88 C80,88 75,88 70,86 Z" Fill="#EBC88E" Opacity="0.8"/>
              <Canvas>
                <Canvas.RenderTransform>
                  <RotateTransform x:Name="DNBUR" CenterX="60" CenterY="70" Angle="0"/>
                </Canvas.RenderTransform>
                <Path Data="M44,64 C38,80 46,98 60,102 C70,102 78,94 78,82 C78,70 70,60 58,60 C50,60 46,62 44,64 Z" Fill="{StaticResource DFur}"/>
                <Path Data="M46,72 C40,84 41,96 50,104 C49,100 47,100 45,96 C43,95 42,91 42,87 C42,81 44,76 46,72 Z" Fill="{StaticResource DFur}" Opacity="0.95"/>
                <Path Data="M60,64 C70,66 76,74 76,84 C72,76 66,70 58,68 Z" Fill="{StaticResource DFurL}" Opacity="0.35"/>
                <Canvas>
                  <Canvas.RenderTransform>
                    <RotateTransform x:Name="DNBLR" CenterX="66" CenterY="100" Angle="0"/>
                  </Canvas.RenderTransform>
                  <Path Data="M62,96 C68,94 74,98 72,104 L64,122 C63,128 64,134 66,138 L56,139 C55,132 55,126 56,120 L58,104 C58,100 59,97 62,96 Z" Fill="{StaticResource DFur}"/>
                  <Path Data="M57,106 C54,112 54,118 56,122 C57,118 58,114 58,110 Z" Fill="{StaticResource DFur}" Opacity="0.9"/>
                  <Path Data="M53,139 C53,137.06695 56.5816,135.5 61,135.5 C65.4184,135.5 69,137.06695 69,139 C69,140.93305 65.4184,142.5 61,142.5 C56.5816,142.5 53,140.93305 53,139 Z" Fill="#EBC88E"/>
                </Canvas>
              </Canvas>
              <Canvas>
                <Canvas.RenderTransform>
                  <RotateTransform x:Name="DNFUR" CenterX="131" CenterY="64" Angle="0"/>
                </Canvas.RenderTransform>
                <Path Data="M122,60 C118,74 120,88 124,98 L138,98 C142,86 144,72 140,62 C136,56 126,56 122,60 Z" Fill="{StaticResource DFur}"/>
                <Path Data="M124,64 C122,76 122,88 125,96 C126,86 126,74 128,64 Z" Fill="{StaticResource DFurL}" Opacity="0.35"/>
                <Canvas>
                  <Canvas.RenderTransform>
                    <RotateTransform x:Name="DNFLR" CenterX="130" CenterY="96" Angle="0"/>
                  </Canvas.RenderTransform>
                  <Path Data="M124,94 L136,94 C137,108 136,124 136,134 C137,137 139,138 141,139 L126,139 C125,126 125,108 124,94 Z" Fill="{StaticResource DFur}"/>
                  <Path Data="M124,98 C119,104 119,114 121,121 C122,118 122,116 121,114 C123,112 124,108 124,104 Z" Fill="{StaticResource DFur}" Opacity="0.95"/>
                  <Path Data="M133,98 C135,110 135,122 135,132 C133,122 133,110 131,98 Z" Fill="#EBC88E" Opacity="0.7"/>
                  <Path Data="M124.5,139 C124.5,137.06695 128.30545,135.5 133,135.5 C137.69455,135.5 141.5,137.06695 141.5,139 C141.5,140.93305 137.69455,142.5 133,142.5 C128.30545,142.5 124.5,140.93305 124.5,139 Z" Fill="#EBC88E"/>
                </Canvas>
              </Canvas>
              <Path Data="M138,50 C156,58 160,82 148,99 C147,97 146,98 145,99 C143,100 141,99 140,97 C139,99 137,99 136,98 C142,86 142,66 132,56 Z" Fill="{StaticResource DCream}"/>
              <Path Data="M124,54 C126,38 136,26 150,22 C160,20 168,28 168,38 C166,52 156,64 146,70 C136,72 126,66 124,54 Z" Fill="{StaticResource DFurL}"/>
              <Path Data="M150,26 C156,30 160,40 158,52 C156,44 152,34 146,30 Z" Fill="#A86E30" Opacity="0.2"/>
              <Path Data="M138,32 C146,40 152,52 152,64 L146,66 C145,54 140,42 132,36 Z" Fill="#3A3A46"/>
              <Path Data="M146.4,64 C146.4,62.23264 147.56402,60.8 149,60.8 C150.43598,60.8 151.6,62.23264 151.6,64 C151.6,65.76736 150.43598,67.2 149,67.2 C147.56402,67.2 146.4,65.76736 146.4,64 Z" Fill="#D9B23A"/>
              <Canvas>
                <Canvas.RenderTransform>
                  <TransformGroup>
                    <RotateTransform x:Name="DHeadR" CenterX="152" CenterY="36" Angle="0"/>
                    <TranslateTransform x:Name="DHeadT" X="0" Y="0"/>
                  </TransformGroup>
                </Canvas.RenderTransform>
                <Path Data="M147,26 C146,14 154,6 166,6 C176,6 183,12 183,22 C183,32 175,38 164,38 C154,38 148,34 147,26 Z" Fill="{StaticResource DFurL}"/>
                <Path Data="M153,12 C159,8 168,8 175,12 C167,10 159,10 153,14 Z" Fill="#F9DDA8" Opacity="0.8"/>
                <Path x:Name="DMouthIn" Data="M174,34 C180,44 190,44 194,35 C192,42 184,48 176,45 Z" Fill="#5E2424" Visibility="Collapsed"/>
                <Path x:Name="DTongue" Data="M178,39 C179,54 186,57 190,44 C189,40 183,38 178,39 Z" Fill="#E57A8A" Visibility="Collapsed"/>
                <Canvas>
                  <Canvas.RenderTransform>
                    <RotateTransform x:Name="DJawR" CenterX="172" CenterY="34" Angle="0"/>
                  </Canvas.RenderTransform>
                  <Path Data="M170,34 C176,40 186,42 193,37 C191,43 184,46 176,45 C172,44 169,40 170,34 Z" Fill="#EBC88E"/>
                </Canvas>
                <Path Data="M170,15 C182,12 194,16 198,24 C200,32 195,37 187,38 C180,39 174,38 170,34 C168,28 168,20 170,15 Z" Fill="{StaticResource DCream}"/>
                <Path Data="M178,34.5 C183,37 189,37 195,33 L195,34.5 C189,38.5 183,38.5 178,36 Z" Fill="#8A5A2E" Opacity="0.7"/>
                <Path Data="M168,12 C172,9 176,9 179,12 C176,11.5 172,11.5 168,13.5 Z" Fill="#C98B47" Opacity="0.9"/>
                <Path Data="M190.5,24.5 C190.5,22.2908 192.738,20.5 195.5,20.5 C198.262,20.5 200.5,22.2908 200.5,24.5 C200.5,26.7092 198.262,28.5 195.5,28.5 C192.738,28.5 190.5,26.7092 190.5,24.5 Z" Fill="#2B1D17"/>
                <Path Data="M195.9,25.6 C195.9,25.0477 196.482,24.6 197.2,24.6 C197.918,24.6 198.5,25.0477 198.5,25.6 C198.5,26.1523 197.918,26.6 197.2,26.6 C196.482,26.6 195.9,26.1523 195.9,25.6 Z" Fill="#000000" Opacity="0.8"/>
                <Path Data="M192.4,23 C192.4,22.5029 193.116,22.1 194,22.1 C194.884,22.1 195.6,22.5029 195.6,23 C195.6,23.4971 194.884,23.9 194,23.9 C193.116,23.9 192.4,23.4971 192.4,23 Z" Fill="#FFFFFF" Opacity="0.45"/>
                <Path Data="M168.8,17.5 C169.5,14.6 172,13.6 174.6,14.2 C176.6,14.8 177.2,17 176.2,19 C175,20.6 172.4,21.2 170.4,20.2 C169.3,19.6 168.7,18.6 168.8,17.5 Z" Fill="#3B2414"/>
                <Canvas>
                  <Canvas.RenderTransform>
                    <TranslateTransform x:Name="DPupilT" X="0" Y="0"/>
                  </Canvas.RenderTransform>
                  <Path x:Name="DEye" Data="M170.6,17.4 C170.6,15.9088 171.764,14.7 173.2,14.7 C174.636,14.7 175.8,15.9088 175.8,17.4 C175.8,18.8912 174.636,20.1 173.2,20.1 C171.764,20.1 170.6,18.8912 170.6,17.4 Z" Fill="#24160F"/>
                  <Path x:Name="DEyeShine" Data="M173.2,16.3 C173.2,15.7477 173.648,15.3 174.2,15.3 C174.752,15.3 175.2,15.7477 175.2,16.3 C175.2,16.8523 174.752,17.3 174.2,17.3 C173.648,17.3 173.2,16.8523 173.2,16.3 Z" Fill="#FFFFFF" Opacity="0.95"/>
                </Canvas>
                <Path x:Name="DLid" Data="M168.4,17.6 C169,14 172.4,13 175,13.8 C177.4,14.6 177.8,17.2 176.6,19.4 C175,18.4 171.4,18 168.4,17.6 Z" Fill="{StaticResource DFurL}" Visibility="Collapsed"/>
                <Canvas>
                  <Canvas.RenderTransform>
                    <RotateTransform x:Name="DEarR" CenterX="158" CenterY="12" Angle="0"/>
                  </Canvas.RenderTransform>
                  <Path Data="M155,9 C146,10 140,22 141,36 C141,44 146,50 152,49 C157,48 160,42 161,34 C163,24 164,16 162,11 C160,8 158,8 155,9 Z" Fill="#C98B47"/>
                  <Path Data="M143,34 C141,38 141,42 144,44 C145,47 147,49 149,48 C145,44 143,40 143,34 Z" Fill="#C98B47"/>
                  <Path Data="M151,14 C146,22 145,32 147,42 C149,32 150,23 154,15 Z" Fill="#B07636" Opacity="0.55"/>
                  <Path Data="M157,12 C159,20 159,30 157,40 C156,30 156,21 155,13 Z" Fill="{StaticResource DFurL}" Opacity="0.35"/>
                </Canvas>
              </Canvas>
            </Canvas>
              </Canvas>
            </Canvas>
          </Viewbox>
        </Grid>
      </Grid>

      <TextBlock x:Name="ZzzText" Text="Zzz" FontSize="22" FontWeight="Bold" Foreground="#6B7BD6"
                 Visibility="Collapsed" HorizontalAlignment="Right" VerticalAlignment="Top" Margin="0,6,18,0"/>
    </Grid>
  </Grid>
</Window>
'@

$win = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
$W = @{}
foreach ($nm in @('Bubble','BubbleText','DogHost','Shadow','ShadowScale','Actor','ActScale','ActMove','ActRot','DogPhoto','DrawnDog','ZzzText',
                  'DBodyR','DBodyT','DFBUR','DFBLR','DFFUR','DFFLR','DNBUR','DNBLR','DNFUR','DNFLR','DTailR','DHeadR','DHeadT',
                  'DJawR','DEarR','DMouthIn','DTongue','DEye','DEyeShine','DLid','DPupilT')) {
  $W[$nm] = $win.FindName($nm)
}

$PartCheck['1'] = $true   # ===== end of PART 1 of 7 =====

# ---------- dog look: the realistic drawn dog (no picture files needed) ----------
$Imgs = @{}
$ImgPaths = @{}
$Gifs = @{}
$GifMode = $false
$PhotoMode = $false
$MainKey = $null
function Pick-Img($first, $second) { return $null }
function Get-PhotoFor($stateName, $actName, $tm) { return $null }

# ---------- realistic drawn dog: poses (legs, head, tail, ears, mouth) ----------
function Set-Legs($p, $wv, $phNF, $phFF, $phNB, $phFB, $aUp, $aLo, $bUp, $bLo) {
  $p.NFU = -$aUp * [Math]::Sin($wv + $phNF); $p.NFL = $aLo * [Math]::Max(0.0, [Math]::Sin($wv + $phNF + 1.6))
  $p.FFU = -$aUp * [Math]::Sin($wv + $phFF); $p.FFL = $aLo * [Math]::Max(0.0, [Math]::Sin($wv + $phFF + 1.6))
  $p.NBU = $bUp * [Math]::Sin($wv + $phNB);  $p.NBL = -$bLo * [Math]::Max(0.0, [Math]::Sin($wv + $phNB - 1.6))
  $p.FBU = $bUp * [Math]::Sin($wv + $phFB);  $p.FBL = -$bLo * [Math]::Max(0.0, [Math]::Sin($wv + $phFB - 1.6))
}
function Set-Tucked($p) {
  $p.NFU = -45.0; $p.FFU = -45.0; $p.NFL = 70.0; $p.FFL = 70.0
  $p.NBU = 40.0; $p.FBU = 40.0; $p.NBL = -50.0; $p.FBL = -50.0
}
function Get-DogPose($stateName, $tm, $actName, $prog) {
  $p = @{ FBU = 0.0; FBL = 0.0; FFU = 0.0; FFL = 0.0; NBU = 0.0; NBL = 0.0; NFU = 0.0; NFL = 0.0
          Tail = 10.0; Body = 0.0; BX = 0.0; BY = 0.0; Head = 0.0; HY = 0.0; Ear = 0.0; Jaw = 0.0; tongue = $false; eyes = 'open' }
  $pi = [Math]::PI
  switch ($stateName) {
    'walk' {
      $wv = $tm * 8
      Set-Legs $p $wv ($pi / 2) (3 * $pi / 2) 0.0 $pi 14 32 13 26
      $p.BY = -1.2 * [Math]::Abs([Math]::Sin($wv)); $p.Body = [Math]::Sin(2 * $wv) * 0.8
      $p.Head = 2 + [Math]::Sin(2 * $wv + 0.6) * 3; $p.Tail = 12 + [Math]::Sin($wv) * 10; $p.Ear = [Math]::Sin(2 * $wv + 1.0) * 5
    }
    'run' {
      $wv = $tm * 10
      Set-Legs $p $wv 0.0 0.5 $pi ($pi + 0.5) 30 48 28 40
      $p.Body = [Math]::Sin($wv) * 4; $p.BY = -4 * [Math]::Abs([Math]::Sin($wv)); $p.Tail = -15 + [Math]::Sin($wv) * 8
      $p.Ear = -10 + [Math]::Sin($wv) * 10; $p.Jaw = 10.0; $p.tongue = $true
    }
    'sit' {
      $p.Body = -16.0; $p.BY = 14.0; $p.NFU = 14.0; $p.FFU = 14.0; $p.NFL = 2.0; $p.FFL = 2.0
      $p.NBU = -95.0; $p.NBL = 120.0; $p.FBU = -95.0; $p.FBL = 120.0
      $p.Tail = 60 + [Math]::Sin($tm * 3) * 4; $p.Head = -6.0 + [Math]::Sin($tm * 1.3) * 2; $p.HY = 2.0
    }
    'sleep' {
      $p.BY = 36 + [Math]::Sin($tm * 1.6) * 0.8; $p.NFU = 70.0; $p.NFL = -150.0; $p.FFU = 70.0; $p.FFL = -150.0
      $p.NBU = -80.0; $p.NBL = 125.0; $p.FBU = -80.0; $p.FBL = 125.0
      $p.Tail = 70.0; $p.Head = 28.0; $p.HY = 16.0; $p.Ear = 6.0; $p.eyes = 'closed'
    }
    'held' {
      $p.NFU = [Math]::Sin($tm * 6) * 15; $p.FFU = [Math]::Sin($tm * 6 + 1) * 15
      $p.NBU = [Math]::Sin($tm * 6 + 2) * 15; $p.FBU = [Math]::Sin($tm * 6 + 3) * 15
      $p.Tail = 60.0; $p.Ear = 10.0; $p.Jaw = 8.0
    }
    'fall' { Set-Tucked $p; $p.Ear = -20.0; $p.Tail = -30.0; $p.Jaw = 10.0 }
    default {
      $p.BY = [Math]::Sin($tm * 2.2) * 0.5; $p.Head = [Math]::Sin($tm * 1.3) * 2; $p.Tail = 10 + [Math]::Sin($tm * 4) * 6
    }
  }
  switch ($actName) {
    'happy'   { $p.Tail = [Math]::Sin($tm * 24) * 35; $p.Jaw = 12.0; $p.tongue = $true; $p.Ear = [Math]::Sin($tm * 20) * 8; $p.eyes = 'happy'; $p.BY += -3 * [Math]::Abs([Math]::Sin($tm * 12)) }
    'bark'    { $o = [Math]::Max(0.0, [Math]::Sin($tm * 22)); $p.Jaw = 22 * $o; $p.Head += -8; $p.Ear = -6 * $o; $p.Tail = [Math]::Sin($tm * 20) * 25 }
    'talk'    { $p.Jaw = 12 * [Math]::Max(0.0, [Math]::Sin($tm * 16)); $p.Tail = [Math]::Sin($tm * 14) * 20 }
    'eat'     { $p.Head = 38.0; $p.HY = 10.0; $p.Jaw = 10 * [Math]::Max(0.0, [Math]::Sin($tm * 16)); $p.NFU = -6.0; $p.FFU = -6.0 }
    'shake'   { $p.NFU = -75.0; $p.NFL = 25.0; $p.Body = -3.0; $p.Tail = [Math]::Sin($tm * 20) * 25; $p.eyes = 'happy' }
    'stretch' {
      $k = [Math]::Sin($prog * $pi)
      $p.Body = 18 * $k; $p.BY += -6 * $k; $p.NFU = -30 * $k; $p.FFU = -30 * $k; $p.NFL = -60 * $k; $p.FFL = -60 * $k
      $p.NBU = -14 * $k; $p.FBU = -14 * $k; $p.Head = -22 * $k; $p.Tail = -30 * $k + [Math]::Sin($tm * 18) * 10; $p.Jaw = 18 * $k
      if ($k -gt 0.6) { $p.eyes = 'closed' }
    }
    'sniff'   { $p.Head = 26 + [Math]::Sin($tm * 18) * 2; $p.HY = 6.0; $p.Ear = 6.0 }
    'scratch' { $p.NBU = -45 + [Math]::Sin($tm * 40) * 14; $p.NBL = 60.0; $p.Head = 12.0; $p.eyes = 'happy'; $p.Body = -4.0 }
    'jump'    { Set-Tucked $p; $p.Jaw = 10.0; $p.tongue = $true; $p.Tail = -20.0 }
    'play'    { Set-Tucked $p; $p.Jaw = 12.0; $p.tongue = $true; $p.Tail = [Math]::Sin($tm * 24) * 35; $p.eyes = 'happy' }
    'dance'   { $p.NFU = -40 * [Math]::Abs([Math]::Sin($tm * 8)); $p.NFL = 50 * [Math]::Abs([Math]::Sin($tm * 8)); $p.Jaw = 12.0; $p.tongue = $true; $p.Tail = [Math]::Sin($tm * 24) * 35; $p.eyes = 'happy' }
    'spin'    { $p.Tail = [Math]::Sin($tm * 24) * 35; $p.Jaw = 10.0; $p.tongue = $true }
    'roll'    { Set-Tucked $p; $p.Jaw = 10.0; $p.tongue = $true }
    'playdead'{ Set-Tucked $p; $p.eyes = 'closed'; $p.tongue = $true; $p.Jaw = 8.0; $p.Tail = 0.0 }
    'wag'     { $p.Tail = [Math]::Sin($tm * 22) * 30; $p.eyes = 'happy' }
  }
  # curious head tilt when your mouse comes close (like a real dog listening)
  $want = 0.0
  if ($PET.near -and -not $actName -and ($stateName -eq 'idle' -or $stateName -eq 'sit')) { $want = -9.0 }
  if ($null -eq $PET.tilt) { $PET.tilt = 0.0 }
  $PET.tilt = $PET.tilt + ($want - $PET.tilt) * 0.08
  $p.Head += $PET.tilt
  $p.Ear += -0.8 * $PET.tilt
  # little ear twitch now and then
  if (($stateName -eq 'idle' -or $stateName -eq 'sit') -and ([Math]::Sin($tm * 0.7) -gt 0.97)) { $p.Ear += [Math]::Sin($tm * 30) * 6 }
  return $p
}
function Apply-DogPose($p, $blink) {
  $W.DFBUR.Angle = $p.FBU; $W.DFBLR.Angle = $p.FBL; $W.DFFUR.Angle = $p.FFU; $W.DFFLR.Angle = $p.FFL
  $W.DNBUR.Angle = $p.NBU; $W.DNBLR.Angle = $p.NBL; $W.DNFUR.Angle = $p.NFU; $W.DNFLR.Angle = $p.NFL
  $W.DTailR.Angle = $p.Tail; $W.DBodyR.Angle = $p.Body; $W.DBodyT.X = $p.BX; $W.DBodyT.Y = $p.BY
  $W.DHeadR.Angle = $p.Head; $W.DHeadT.Y = $p.HY; $W.DEarR.Angle = $p.Ear; $W.DJawR.Angle = $p.Jaw
  if ($p.Jaw -gt 3) { $W.DMouthIn.Visibility = 'Visible' } else { $W.DMouthIn.Visibility = 'Collapsed' }
  if ($p.tongue -and $p.Jaw -gt 3) { $W.DTongue.Visibility = 'Visible' } else { $W.DTongue.Visibility = 'Collapsed' }
  # eyes follow your mouse
  if (($PET.frame % 2) -eq 0) {
    $gp = Get-MouseDip
    if ($null -ne $gp) {
      $eyeX = $PET.x + $LAY.winW / 2 + 55 * $LAY.scale * $PET.dir
      $eyeY = $PET.y + $LAY.winH - $LAY.hostH * 0.85
      $gx = [Math]::Max(-1.0, [Math]::Min(1.0, ($gp.X - $eyeX) / 250.0)) * $PET.dir
      $gy = [Math]::Max(-1.0, [Math]::Min(1.0, ($gp.Y - $eyeY) / 250.0))
      $W.DPupilT.X = $gx * 1.1
      $W.DPupilT.Y = $gy * 0.8
    }
  }
  if ($blink -or $p.eyes -ne 'open') {
    $W.DLid.Visibility = 'Visible'; $W.DEye.Visibility = 'Collapsed'; $W.DEyeShine.Visibility = 'Collapsed'
  } else {
    $W.DLid.Visibility = 'Collapsed'; $W.DEye.Visibility = 'Visible'; $W.DEyeShine.Visibility = 'Visible'
  }
}

# ---------- size + the area the dog can walk on (above the taskbar) ----------
$LAY = @{ scale = 1.0; hostW = 200; hostH = 170; winW = 260; winH = 280; minX = 0.0; maxX = 500.0; ground = 0.0 }
$SizeMap = @{ small = 0.7; medium = 1.0; large = 1.35; huge = 1.75 }
function Apply-Size {
  $sc = 1.0
  if ($SizeMap.ContainsKey([string]$cfg.size)) { $sc = [double]$SizeMap[[string]$cfg.size] }
  $LAY.scale = $sc
  $LAY.hostW = [Math]::Round(200 * $sc)
  $LAY.hostH = [Math]::Round(170 * $sc)
  $LAY.winW = [Math]::Max(260, $LAY.hostW + 60)
  $LAY.winH = $LAY.hostH + 110
  $win.Width = $LAY.winW
  $win.Height = $LAY.winH
  $W.DogHost.Width = $LAY.hostW
  $W.DogHost.Height = $LAY.hostH
  $W.DrawnDog.Width = 190 * $sc
  $W.DrawnDog.Height = 148 * $sc
  $W.Shadow.Width = 110 * $sc
  $W.Shadow.Height = 14 * $sc
  $W.Bubble.MaxWidth = $LAY.winW - 16
  $area = [System.Windows.SystemParameters]::WorkArea
  $pad = ($LAY.winW - $LAY.hostW) / 2
  $LAY.minX = $area.Left - $pad
  $LAY.maxX = $area.Right - $LAY.winW + $pad
  $LAY.ground = $area.Bottom - $LAY.winH + 5
}
Apply-Size

# ---------- pet state ----------
$PET = @{
  x = 300.0; y = 0.0; vy = 0.0; dir = 1; face = 1.0
  state = 'idle'; target = 300.0; nextChange = [datetime]::Now.AddSeconds(3)
  t = 0.0; frame = 0; dragging = $false; near = $false; hidden = $false
  action = $null; actionStart = [datetime]::Now; actionUntil = [datetime]::MinValue
  pending = $null; pendingExpire = [datetime]::MaxValue
  sticky = $false; bubbleUntil = [datetime]::MinValue
  blinkUntil = [datetime]::MinValue; nextBlink = [datetime]::Now.AddSeconds(3)
  nextNag = [datetime]::Now.AddMinutes(10); saveTicks = 0
  nextWater = [datetime]::Now.AddMinutes([double]$cfg.waterMinutes)
  nextBreak = [datetime]::Now.AddMinutes([double]$cfg.breakMinutes)
  focusOn = $false; focusUntil = [datetime]::MinValue
  showAt = [datetime]::MaxValue; lateNag = ''
  reminders = New-Object System.Collections.ArrayList
}
if ($LAY.maxX - $LAY.minX -gt 220) { $PET.x = [double](Get-Random -Minimum ([int]$LAY.minX + 100) -Maximum ([int]$LAY.maxX - 100)) }
$PET.target = $PET.x
$PET.y = $LAY.ground
foreach ($rem in @($cfg.reminders)) {
  try {
    $when = [datetime]::Parse([string]$rem.at, $null, [System.Globalization.DateTimeStyles]::RoundtripKind).ToLocalTime()
    $null = $PET.reminders.Add(@{ at = $when; text = [string]$rem.text })
  } catch { }
}

$UI = @{ chat = $null; chatList = $null; chatScroll = $null; chatInput = $null; chatTitle = $null; chatStatus = $null; avatar = $null; quitting = $false }
$Tray = $null

# ---------- helpers ----------
function Say($text, $secs) {
  $W.BubbleText.Text = [string]$text
  $W.Bubble.Visibility = 'Visible'
  if ($secs -le 0) { $PET.sticky = $true } else { $PET.sticky = $false; $PET.bubbleUntil = [datetime]::Now.AddSeconds($secs) }
}
function Hide-Bubble { $W.Bubble.Visibility = 'Collapsed'; $PET.sticky = $false }
function Set-State($newState, $secs) { $PET.state = $newState; $PET.nextChange = [datetime]::Now.AddSeconds($secs) }
function Bark-Sound {
  if (-not [bool]$cfg.sounds) { return }
  try { if ($null -ne $BarkPlayer) { $BarkPlayer.Play() } else { [System.Media.SystemSounds]::Exclamation.Play() } } catch { }
}
function Speak-Text($text, $force) {
  if ($null -eq $Voice) { return }
  if (-not $force -and -not [bool]$cfg.talk) { return }
  try {
    $plain = [string]$text
    $fence = $plain.IndexOf('```')
    if ($fence -ge 0) { $plain = $plain.Substring(0, $fence) }
    $plain = ($plain -replace '[^\x20-\x7E]', ' ') -replace '\s+', ' '
    if ($plain.Length -gt 220) { $plain = $plain.Substring(0, 220) }
    if ([string]::IsNullOrWhiteSpace($plain)) { return }
    $Voice.SpeakAsyncCancelAll()
    $ssml = '<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xml:lang="en-US"><prosody pitch="x-high">' + [System.Security.SecurityElement]::Escape($plain) + '</prosody></speak>'
    try { $null = $Voice.SpeakSsmlAsync($ssml) } catch { $null = $Voice.SpeakAsync($plain) }
  } catch { Write-Log $_ }
}
function Notify-User($text) {
  if (-not [bool]$cfg.notify -or $null -eq $Tray) { return }
  try { $Tray.ShowBalloonTip(6000, ('Dog Pet - ' + $cfg.dogName), [string]$text, [System.Windows.Forms.ToolTipIcon]::Info) } catch { }
}
function Do-Action($name, $secs) {
  $now = [datetime]::Now
  $PET.action = $name
  $PET.actionStart = $now
  $PET.actionUntil = $now.AddSeconds([double]$secs)
  if ($PET.state -eq 'sleep' -or $PET.state -eq 'walk' -or $PET.state -eq 'run') { $PET.state = 'idle' }
  if ($PET.state -eq 'sit' -and (@('eat','play','jump','spin','roll','dance','playdead','shake','happy','bark') -contains $name)) { $PET.state = 'idle' }
  $PET.nextChange = $now.AddSeconds([double]$secs + 1)
}
function Get-MouseDip {
  try {
    $pt = [System.Windows.Forms.Cursor]::Position
    $src = [System.Windows.PresentationSource]::FromVisual($win)
    $pnt = New-Object System.Windows.Point($pt.X, $pt.Y)
    if ($null -ne $src) { return $src.CompositionTarget.TransformFromDevice.Transform($pnt) }
    return $pnt
  } catch { return $null }
}
function Clamp-X($val) { return [Math]::Min($LAY.maxX, [Math]::Max($LAY.minX, [double]$val)) }
function Start-Walk($speedState) {
  if ($LAY.maxX - $LAY.minX -lt 20) { Set-State 'idle' 3; return }
  $PET.target = [double](Get-Random -Minimum ([int]$LAY.minX) -Maximum ([int]$LAY.maxX))
  $PET.state = $speedState
  $PET.nextChange = [datetime]::Now.AddSeconds(40)
}
function Pick-Behavior {
  $hr = [datetime]::Now.Hour
  $r = Get-Random -Minimum 0 -Maximum 100
  if ($PET.focusOn) {
    if ($r -lt 15) { Start-Walk 'walk' } elseif ($r -lt 55) { Set-State 'sit' (Get-Random -Minimum 8 -Maximum 16) } else { Set-State 'sleep' (Get-Random -Minimum 15 -Maximum 30) }
    return
  }
  if (($hr -ge 22 -or $hr -lt 6) -and $r -lt 40) { Set-State 'sleep' (Get-Random -Minimum 20 -Maximum 40); return }
  if ($r -lt 33) { Start-Walk 'walk' }
  elseif ($r -lt 40) { Start-Walk 'run' }
  elseif ($r -lt 52) { Set-State 'idle' (Get-Random -Minimum 2 -Maximum 5) }
  elseif ($r -lt 65) { Set-State 'sit' (Get-Random -Minimum 4 -Maximum 9) }
  elseif ($r -lt 73) { Set-State 'sleep' (Get-Random -Minimum 8 -Maximum 17) }
  else {
    $fid = Get-Random -InputObject @('sniff','sniff','scratch','stretch','look','look','wag','jump','spin')
    $dur = 1.6
    if ($fid -eq 'sniff') { $dur = 2.2 } elseif ($fid -eq 'scratch') { $dur = 1.4 } elseif ($fid -eq 'jump') { $dur = 0.9 }
    Set-State 'idle' 1
    Do-Action $fid $dur
  }
}

# ---------- pet care + tricks ----------
function Add-Happy($amount) { $cfg.happiness = [Math]::Min(100, [double]$cfg.happiness + $amount) }
function Feed-Dog($kind) {
  if ($kind -eq 'bone') { $addFull = 30; $icon = $EM.bone } else { $addFull = 15; $icon = $EM.cookie }
  $cfg.fullness = [Math]::Min(100, [double]$cfg.fullness + $addFull)
  Add-Happy 12
  Save-Cfg
  Set-State 'idle' 6
  Do-Action 'eat' 3.2
  Say ('Nom nom nom! ' + $icon) 3.5
}
function Play-WithDog {
  Add-Happy 20
  $cfg.fullness = [Math]::Max(0, [double]$cfg.fullness - 5)
  Save-Cfg
  Set-State 'idle' 6
  Do-Action 'play' 4
  Say ('Wheee! ' + $EM.ball) 4
}
function Make-Bark { Set-State 'idle' 3; Do-Action 'bark' 1.3; Bark-Sound; Say 'Woof woof!' 2 }
function Take-Nap { Set-State 'sleep' 30; Say ('Zzz... ' + $EM.sleepy) 4 }
function Do-Trick($trick) {
  Set-State 'idle' 4
  Add-Happy 4
  switch ($trick) {
    'sit'      { Set-State 'sit' 12; Say 'Sitting like a good dog!' 3 }
    'roll'     { Do-Action 'roll' 1.4; Say 'Rolling over!' 2 }
    'jump'     { Do-Action 'jump' 0.9; Bark-Sound; Say 'Boing!' 2 }
    'spin'     { Do-Action 'spin' 1.6; Say 'Chasing my tail!' 2 }
    'shake'    { Do-Action 'shake' 1.8; Say ('Here is my paw! ' + $EM.paw) 3 }
    'dance'    { Do-Action 'dance' 3.0; Say 'Dance party!' 3 }
    'playdead' { Do-Action 'playdead' 3.0; Say 'x_x' 3 }
    'bark'     { Make-Bark }
  }
}
function Show-Dog {
  if ($PET.hidden) { $win.Show(); $PET.hidden = $false }
  $PET.showAt = [datetime]::MaxValue
}
function Hide-Dog($mins) {
  $win.Hide()
  $PET.hidden = $true
  if ($mins -gt 0) { $PET.showAt = [datetime]::Now.AddMinutes($mins) } else { $PET.showAt = [datetime]::MaxValue }
  Notify-User 'I am hiding. Click my tray icon (near the clock) to chat or bring me back.'
}
function Call-Dog {
  Show-Dog
  $mp = Get-MouseDip
  if ($null -ne $mp) { $PET.target = Clamp-X ($mp.X - $LAY.winW / 2) } else { $PET.target = Clamp-X (($LAY.minX + $LAY.maxX) / 2) }
  $PET.state = 'run'
  $PET.nextChange = [datetime]::Now.AddSeconds(30)
}

# ---------- assistant: water, reminders, to-dos, focus ----------
function Get-WaterText {
  Update-DayCounter
  $msg = 'Water today: ' + $cfg.glasses + ' of ' + $cfg.waterGoal + ' glasses ' + $EM.water
  if ([int]$cfg.glasses -ge [int]$cfg.waterGoal) { $msg += '  Goal reached, great job!' }
  return $msg
}
function Drink-Water {
  Update-DayCounter
  $cfg.glasses = [int]$cfg.glasses + 1
  if ($PET.pending -eq 'water') { $PET.pending = $null }
  $PET.nextWater = [datetime]::Now.AddMinutes([double]$cfg.waterMinutes)
  Save-Cfg
  Do-Action 'happy' 2
  $msg = 'Good job, ' + $cfg.userName + '! Glass ' + $cfg.glasses + ' of ' + $cfg.waterGoal + ' today ' + $EM.water
  if ([int]$cfg.glasses -eq [int]$cfg.waterGoal) { $msg = 'You reached your water goal today! ' + $EM.star }
  Say $msg 5
}
function Start-Alert($kind, $text, $expireMins) {
  $PET.pending = $kind
  if ($expireMins -gt 0) { $PET.pendingExpire = [datetime]::Now.AddMinutes($expireMins) } else { $PET.pendingExpire = [datetime]::MaxValue }
  Set-State 'idle' 60
  Say $text 0
  Bark-Sound
  Notify-User ($text -replace '[^\x20-\x7E]', '')
  Speak-Text $text $false
}
function Start-WaterReminder {
  $PET.nextWater = [datetime]::Now.AddMinutes(5)   # ask again in 5 min if ignored
  $txt = $EM.water + ' ' + $cfg.userName + ', time to drink water! Click me when you have had a glass.'
  if ($PET.hidden) { Notify-User 'Time to drink water!'; return }
  Start-Alert 'water' $txt 0
}
function Start-BreakReminder {
  $PET.nextBreak = [datetime]::Now.AddMinutes([double]$cfg.breakMinutes)
  if ($PET.hidden) { Notify-User 'Break time! Stand up and stretch.'; return }
  Start-Alert 'break' ($EM.eyes + ' Break time! Stand up, stretch and rest your eyes. Click me when done.') 3
}
function Add-ReminderAt($at, $what, $quiet) {
  $txt = ([string]$what).Trim().TrimEnd('.', '!')
  if ($txt -eq '') { $txt = 'Your reminder' }
  $null = $PET.reminders.Add(@{ at = $at; text = $txt })
  Save-Cfg
  $whenText = $at.ToString('h:mm tt')
  if ($at.Date -ne [datetime]::Today) { $whenText = $at.ToString('ddd h:mm tt') }
  if (-not $quiet) { Say ('Okay! I will remind you at ' + $whenText + ' ' + $EM.paw) 4 }
  return ('Got it! I will remind you: "' + $txt + '" at ' + $whenText + ' ' + $EM.clock)
}
function Add-ReminderIn($num, $unit, $what) {
  $mins = [double]$num
  if ($unit -match '^s') { $mins = $mins / 60 } elseif ($unit -match '^h') { $mins = $mins * 60 }
  if ($mins -le 0) { return 'Please give me a time bigger than zero.' }
  return (Add-ReminderAt ([datetime]::Now.AddMinutes($mins)) $what $false)
}
function Get-RemindersText {
  if ($PET.reminders.Count -eq 0) { return 'You have no reminders. Try: remind me to call mom in 10 minutes' }
  $out = 'Your reminders:'
  $i = 1
  foreach ($rem in @($PET.reminders | Sort-Object { $_.at })) {
    $out += "`n" + $i + '. ' + $rem.at.ToString('ddd h:mm tt') + '  -  ' + $rem.text
    $i++
  }
  return $out
}
function Add-TodoText($what) {
  $txt = ([string]$what).Trim()
  if ($txt -eq '') { return 'What should I add? Example: todo send the report' }
  $cfg.todos = @($cfg.todos) + $txt
  Save-Cfg
  Say 'Added to your to-do list!' 3
  return ('Added to your to-do list: ' + $txt + '  (you have ' + @($cfg.todos).Count + ')')
}
function Get-TodosText {
  $list = @($cfg.todos)
  if ($list.Count -eq 0) { return 'Your to-do list is empty! Add one with: todo buy milk' }
  $out = 'Your to-dos:'
  for ($i = 0; $i -lt $list.Count; $i++) { $out += "`n" + ($i + 1) + '. ' + $list[$i] }
  return ($out + "`n`nType  done 1  to tick one off.")
}
function Remove-TodoAt($num) {
  $list = @($cfg.todos)
  if ($num -lt 1 -or $num -gt $list.Count) { return ('There is no to-do number ' + $num + '. Type  todos  to see the list.') }
  $gone = $list[$num - 1]
  $kept = @()
  for ($i = 0; $i -lt $list.Count; $i++) { if ($i -ne ($num - 1)) { $kept += $list[$i] } }
  $cfg.todos = $kept
  Save-Cfg
  Do-Action 'happy' 1.5
  return ('Done! Removed: ' + $gone + ' ' + $EM.star)
}
function Set-WaterInterval($mins) {
  $cfg.waterMinutes = [int]$mins
  $PET.nextWater = [datetime]::Now.AddMinutes([double]$mins)
  Save-Cfg
  Say ('Okay! I will remind you every ' + $mins + ' minutes ' + $EM.water) 4
}
function Start-Focus($mins) {
  $m = [int]$mins
  if ($m -lt 1) { $m = 1 }
  if ($m -gt 240) { $m = 240 }
  $PET.focusOn = $true
  $PET.focusUntil = [datetime]::Now.AddMinutes($m)
  Set-State 'sit' 10
  Say ('Focus mode: ' + $m + ' min. I will stay quiet ' + $EM.muscle) 4
  return ('Focus session started for ' + $m + ' minutes. I will keep quiet (water reminders stay on). Type  stop focus  to end early.')
}
function Stop-Focus {
  if (-not $PET.focusOn) { return 'There is no focus session running. Type  focus  to start one.' }
  $PET.focusOn = $false
  return 'Focus session stopped.'
}
function Get-FocusText {
  if (-not $PET.focusOn) { return 'No focus session running. Type  focus  (25 min) or  focus 50.' }
  $left = [Math]::Ceiling(($PET.focusUntil - [datetime]::Now).TotalMinutes)
  return ('Focus session: ' + $left + ' minutes left. You can do it! ' + $EM.muscle)
}
function Get-MoodText {
  $full = [int]$cfg.fullness
  $happy = [int]$cfg.happiness
  $feel = 'great'
  if ($full -lt 30) { $feel = 'hungry (give me a bone?)' } elseif ($happy -lt 30) { $feel = 'a bit bored (play with me?)' } elseif ($happy -gt 80 -and $full -gt 60) { $feel = 'super happy' }
  return ('I feel ' + $feel + '! Fullness ' + $full + '%, happiness ' + $happy + '%. ' + $EM.paw)
}

# ---------- InputBox versions (for the right-click menu) ----------
function Ask-Reminder {
  $mins = [Microsoft.VisualBasic.Interaction]::InputBox('In how many minutes should I remind you?', 'Dog Pet - Reminder', '30')
  if ([string]::IsNullOrWhiteSpace($mins)) { return }
  $num = 0.0
  if (-not [double]::TryParse($mins, [ref]$num) -or $num -le 0) { Say 'Please type a number of minutes.' 4; return }
  $what = [Microsoft.VisualBasic.Interaction]::InputBox('What should I remind you about?', 'Dog Pet - Reminder', '')
  $null = Add-ReminderIn $num 'm' $what
}
function Ask-Todo {
  $what = [Microsoft.VisualBasic.Interaction]::InputBox('What do you need to do?', 'Dog Pet - New to-do', '')
  if (-not [string]::IsNullOrWhiteSpace($what)) { $null = Add-TodoText $what }
}

$PartCheck['2'] = $true   # ===== end of PART 2 of 7 =====
# ---------- coding knowledge (knowledge.txt) ----------
$KB = New-Object System.Collections.ArrayList
function Simplify-Text($text) {
  $s1 = ([string]$text).ToLower()
  $s1 = $s1 -replace 'c#', ' csharp ' -replace 'c\+\+', ' cpp ' -replace '\.net', ' dotnet ' -replace 'node\.js', ' nodejs '
  $s1 = $s1 -replace '[^a-z0-9]+', ' '
  $words = @()
  foreach ($wd in ($s1.Trim() -split ' ')) {
    if ($wd -eq '') { continue }
    if ($wd.Length -gt 4 -and $wd.EndsWith('ies')) { $wd = $wd.Substring(0, $wd.Length - 3) + 'y' }
    elseif ($wd.Length -gt 3 -and $wd.EndsWith('s') -and -not $wd.EndsWith('ss')) { $wd = $wd.Substring(0, $wd.Length - 1) }
    $words += $wd
  }
  return ($words -join ' ')
}
function Load-Knowledge {
  $KB.Clear()
  if (-not (Test-Path $KbFile)) { return }
  try {
    $cur = $null
    $inAns = $false
    $buf = New-Object System.Collections.Generic.List[string]
    foreach ($ln in (Get-Content -Path $KbFile -Encoding UTF8)) {
      if (-not $inAns) {
        if ($ln -match '^\s*#') { continue }
        if ($ln -match '^\s*Q:\s*(.+)$') {
          $keyList = @()
          foreach ($kw in ($Matches[1] -split ',')) { $sk = Simplify-Text $kw; if ($sk -ne '') { $keyList += $sk } }
          $cur = @{ keys = $keyList; title = ''; answer = '' }
        } elseif ($ln -match '^\s*T:\s*(.+)$' -and $null -ne $cur) { $cur.title = $Matches[1].Trim() }
        elseif ($ln -match '^\s*A:\s*$' -and $null -ne $cur) { $inAns = $true; $buf.Clear() }
      } else {
        if ($ln -match '^\s*---\s*$') {
          $cur.answer = ($buf -join "`n").Trim()
          $null = $KB.Add($cur)
          $cur = $null
          $inAns = $false
        } else { $buf.Add($ln) }
      }
    }
    if ($inAns -and $null -ne $cur) { $cur.answer = ($buf -join "`n").Trim(); $null = $KB.Add($cur) }
  } catch { Write-Log $_ }
}
function Find-Knowledge($question) {
  $q = ' ' + (Simplify-Text $question) + ' '
  $best = $null
  $bestScore = 0.0
  foreach ($entry in $KB) {
    $score = 0.0
    foreach ($kw in $entry.keys) {
      if ($q.Contains(' ' + $kw + ' ')) { $score += [Math]::Pow(@($kw -split ' ').Count, 1.5) }
    }
    if ($score -gt $bestScore) { $bestScore = $score; $best = $entry }
  }
  if ($bestScore -ge 1) { return $best }
  return $null
}
function Get-TopicsText {
  if ($KB.Count -eq 0) { return 'I have no coding notes loaded. Put knowledge.txt in the DogPet folder and type  reload.' }
  $groups = [ordered]@{}
  foreach ($entry in $KB) {
    $title = [string]$entry.title
    if ($title -eq '') { continue }
    $grp = 'Other'
    $short = $title
    $ix = $title.IndexOf(' - ')
    if ($ix -gt 0) { $grp = $title.Substring(0, $ix); $short = $title.Substring($ix + 3) }
    if (-not $groups.Contains($grp)) { $groups[$grp] = New-Object System.Collections.ArrayList }
    $null = $groups[$grp].Add($short)
  }
  $out = 'I know ' + $KB.Count + ' coding topics. Ask in your own words, e.g.  python read file  or  git undo commit' + "`n"
  foreach ($gk in $groups.Keys) { $out += "`n" + $gk + ': ' + (@($groups[$gk]) -join ', ') }
  return $out
}
Load-Knowledge

# ---------- fun lines ----------
$Jokes = @(
  'Why do programmers prefer dark mode? Because light attracts bugs!',
  'There are 10 kinds of people: those who understand binary and those who do not.',
  'A SQL query walks into a bar, walks up to two tables and asks: can I join you?',
  'Why did the developer go broke? Because he used up all his cache.',
  'I would tell you a UDP joke, but you might not get it.',
  'Debugging: being the detective in a crime movie where you are also the murderer.',
  'Why do dogs make great programmers? They always fetch the right data! Woof!',
  'It works on my machine. Then we will ship your machine.',
  'Why was the JavaScript developer sad? Because he did not Node how to Express himself.'
)
$Quotes = @(
  'First, solve the problem. Then, write the code. - John Johnson',
  'Simplicity is the soul of efficiency. - Austin Freeman',
  'Make it work, make it right, make it fast. - Kent Beck',
  'Small steps every day add up to big results.',
  'Done is better than perfect.',
  'Every expert was once a beginner. Keep going!',
  'You do not have to be great to start, but you have to start to be great.'
)
$Facts = @(
  'Dogs can smell about 10,000 to 100,000 times better than humans.',
  'A dog nose print is unique, like a human fingerprint.',
  'Golden Retrievers were first bred in Scotland in the 1800s.',
  'Dogs dream too - twitching paws while sleeping often means a dream!',
  'Puppies are born deaf and blind; their senses develop in a few weeks.',
  'A wagging tail to the right usually means a happy dog.'
)

function New-Reply($text, $web) { return @{ text = [string]$text; web = $web } }
function Code-Block($s) { return ('```' + "`n" + [string]$s + "`n" + '```') }
function Open-Web($url) { try { Start-Process $url } catch { Write-Log $_ } }
function Open-App($name) {
  $apps = @{
    'notepad' = 'notepad.exe'; 'calculator' = 'calc.exe'; 'calc' = 'calc.exe'; 'paint' = 'mspaint.exe'
    'cmd' = 'cmd.exe'; 'command prompt' = 'cmd.exe'; 'powershell' = 'powershell.exe'; 'terminal' = 'wt.exe'
    'explorer' = 'explorer.exe'; 'file explorer' = 'explorer.exe'; 'files' = 'explorer.exe'
    'task manager' = 'taskmgr.exe'; 'settings' = 'ms-settings:'; 'vscode' = 'code'; 'vs code' = 'code'; 'code' = 'code'
    'browser' = 'https://www.google.com'; 'google' = 'https://www.google.com'; 'edge' = 'msedge'; 'chrome' = 'chrome'
    'outlook' = 'outlook'; 'teams' = 'msteams:'; 'snipping tool' = 'snippingtool.exe'; 'youtube' = 'https://www.youtube.com'
  }
  $key = ([string]$name).ToLower().Trim()
  if (-not $apps.ContainsKey($key)) { return ('I do not know how to open "' + $name + '". I can open: ' + (($apps.Keys | Sort-Object) -join ', ')) }
  try { Start-Process $apps[$key]; return ('Opening ' + $name + '...') } catch { return ('Sorry, I could not open ' + $name + ' on this PC.') }
}

# ---------- the quick-command brain (works offline) ----------
function Get-QuickReply($rawText) {
  $t = ([string]$rawText).Trim()
  $l = $t.ToLower()
  if ($l -eq '') { return (New-Reply 'Woof?' $null) }

  if ($l -match '(kill myself|suicide|want to die|end my life|hurt myself|self harm)') {
    return (New-Reply ("I am really sorry you are feeling this way, " + $cfg.userName + ". You matter. Please talk to someone right now: in the US call or text 988 (Suicide and Crisis Lifeline), or call your local emergency number (911 in the US). Reaching out to a person you trust also helps. I am here with you. " + $EM.heart) $null)
  }

  if ($l -match '^(help|\?|commands|menu|what can you do|options)\b') { return (New-Reply (Get-HelpText) $null) }

  # --- reminders and timers ---
  $unitPat = '(s|sec|secs|second|seconds|m|min|mins|minute|minutes|h|hr|hrs|hour|hours)'
  if ($t -match ('^remind me (?:to |about )?(.+?) in (\d+(?:\.\d+)?)\s*' + $unitPat + '\.?$')) {
    $what = $Matches[1]; $num = [double]$Matches[2]; $unit = $Matches[3]
    return (New-Reply (Add-ReminderIn $num $unit $what) $null)
  }
  if ($t -match ('^remind me in (\d+(?:\.\d+)?)\s*' + $unitPat + '\s+(?:to |about )?(.+)$')) {
    $num = [double]$Matches[1]; $unit = $Matches[2]; $what = $Matches[3]
    return (New-Reply (Add-ReminderIn $num $unit $what) $null)
  }
  if ($t -match '^remind me (?:to |about )?(.+?) at (\d{1,2})(?::(\d{2}))?\s*(am|pm)?\.?$') {
    $what = $Matches[1]; $hh = [int]$Matches[2]; $mm = 0; $ampm = ''
    if ($Matches[3]) { $mm = [int]$Matches[3] }
    if ($Matches[4]) { $ampm = ([string]$Matches[4]).ToLower() }
    if ($ampm -eq 'pm' -and $hh -lt 12) { $hh += 12 }
    if ($ampm -eq 'am' -and $hh -eq 12) { $hh = 0 }
    if ($hh -gt 23 -or $mm -gt 59) { return (New-Reply 'That time looks odd. Try: remind me to call Sam at 3:30 pm' $null) }
    $at = [datetime]::Today.AddHours($hh).AddMinutes($mm)
    if ($at -le [datetime]::Now) { $at = $at.AddDays(1) }
    return (New-Reply (Add-ReminderAt $at $what $false) $null)
  }
  if ($l -match '^remind') { return (New-Reply 'Tell me what and when, for example:  remind me to call mom in 10 minutes  |  remind me in 1 hour to stretch  |  remind me to join standup at 9:30 am' $null) }
  if ($l -match '^((my|show|list|show my) )?reminders?$') { return (New-Reply (Get-RemindersText) $null) }
  if ($l -match '^(clear|cancel|delete) (all )?(my )?reminders?$') { $PET.reminders.Clear(); Save-Cfg; return (New-Reply 'All reminders cleared.' $null) }
  if ($t -match ('^(?:set |start )?timer (?:for )?(\d+(?:\.\d+)?)\s*' + $unitPat + '?$')) {
    $num = [double]$Matches[1]; $unit = 'm'
    if ($Matches[2]) { $unit = $Matches[2] }
    return (New-Reply (Add-ReminderIn $num $unit 'Timer is done!') $null)
  }

  # --- focus ---
  if ($l -match '^(focus|pomodoro|start focus|focus mode)(?: (?:for )?(\d+))?(?: ?min(?:ute)?s?)?$') {
    $mins = 25
    if ($Matches[2]) { $mins = [int]$Matches[2] }
    return (New-Reply (Start-Focus $mins) $null)
  }
  if ($l -match '^(stop|end|cancel) (focus|pomodoro)') { return (New-Reply (Stop-Focus) $null) }
  if ($l -match '^focus status|^how (long|much) (is )?left') { return (New-Reply (Get-FocusText) $null) }

  # --- to-dos ---
  if ($l -match '^((show|list|my|show my) )?(todo|todos|to-do|to-dos|task|tasks)( list)?$') { return (New-Reply (Get-TodosText) $null) }
  if ($l -match '^(clear|delete all|remove all) (my )?(todo|todos|to-dos|tasks)$') { $cfg.todos = @(); Save-Cfg; return (New-Reply 'Your to-do list is now empty.' $null) }
  if ($t -match '^(?:done|complete|completed|finish|finished|remove|delete|tick)\s+(?:todo\s+|task\s+)?#?(\d+)$') { return (New-Reply (Remove-TodoAt ([int]$Matches[1])) $null) }
  if ($t -match '^add (.+) to (?:my )?(?:todo|to-do|task)s?(?: list)?$') { return (New-Reply (Add-TodoText $Matches[1]) $null) }
  if ($t -match '^(?:add\s+)?(?:todo|to-do|task)\s*[:\-]?\s+(.+)$') { return (New-Reply (Add-TodoText $Matches[1]) $null) }

  # --- water ---
  if ($l -match '(drank|drunk|had|finished) (a |some |my |one )?(glass |bottle |cup )?(of )?water' -or $l -match '^water done$') { Drink-Water; return (New-Reply ('Good job! ' + (Get-WaterText)) $null) }
  if ($l -match '^water (every|interval|reminder every)\s+(\d+)') {
    $mins = [int]$Matches[2]
    if ($mins -lt 5) { $mins = 5 }
    Set-WaterInterval $mins
    return (New-Reply ('Okay, I will remind you to drink water every ' + $mins + ' minutes.') $null)
  }
  if ($l -match '^water goal\s+(\d+)$') { $cfg.waterGoal = [int]$Matches[1]; Save-Cfg; return (New-Reply ('New daily goal: ' + $cfg.waterGoal + ' glasses.') $null) }
  if ($l -match '^(water|water stats|how much water|water count|water today)\??$') { return (New-Reply (Get-WaterText) $null) }

  # --- time and date ---
  if ($l -match '^(what(''s| is) the )?(time|date)( now| is it| today)?\??$' -or $l -match '^what (time|day|date) is it\??$' -or $l -match '^(today|what day is today)\??$') {
    return (New-Reply ('It is ' + (Get-Date).ToString('dddd, MMMM d yyyy, h:mm tt') + ' ' + $EM.clock) $null)
  }

  # --- calculator ---
  $calcSrc = $null
  if ($t -match '^(?:calc|calculate|compute|math)\s+(.+)$') { $calcSrc = $Matches[1] }
  elseif ($t -match '^(?:what is |what''s |whats )?([\d\.\s\+\-\*/%\(\)]+)[\?=]?$') {
    $cand = $Matches[1]
    if ($cand -match '\d\s*[\+\-\*/%]\s*[\d\(]') { $calcSrc = $cand }
  }
  if ($null -ne $calcSrc) {
    $expr = $calcSrc.Trim().TrimEnd('?', '=')
    if ($expr -notmatch '^[\d\.\s\+\-\*/%\(\)]+$') { return (New-Reply 'I can only do numbers with + - * / % ( ). Example: calc (12+8)*3' $null) }
    try {
      $res = (New-Object System.Data.DataTable).Compute($expr, '')
      return (New-Reply ($expr + ' = ' + $res) $null)
    } catch { return (New-Reply 'Hmm, I could not calculate that.' $null) }
  }

  # --- developer tools ---
  if ($l -match '^(uuid|guid|new guid|new uuid)$') { return (New-Reply ('Here is a new GUID:' + "`n" + (Code-Block ([guid]::NewGuid().ToString()))) $null) }
  if ($t -match '^base64 ?encode\s+(.+)$') { $val = $Matches[1]; return (New-Reply ('Base64:' + "`n" + (Code-Block ([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($val))))) $null) }
  if ($t -match '^base64 ?decode\s+(.+)$') {
    $val = $Matches[1]
    try { return (New-Reply ('Decoded:' + "`n" + (Code-Block ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($val.Trim()))))) $null) }
    catch { return (New-Reply 'That does not look like valid Base64.' $null) }
  }
  if ($t -match '^url ?encode\s+(.+)$') { $val = $Matches[1]; return (New-Reply (Code-Block ([uri]::EscapeDataString($val))) $null) }
  if ($t -match '^url ?decode\s+(.+)$') { $val = $Matches[1]; return (New-Reply (Code-Block ([uri]::UnescapeDataString($val))) $null) }
  if ($l -match '^(epoch|unix ?time|timestamp|now epoch)$') {
    $sec = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    return (New-Reply ('Unix time now:' + "`n" + (Code-Block ([string]$sec))) $null)
  }
  if ($l -match '^(?:epoch|unix|timestamp)\s+(\d{9,13})$') {
    $digits = $Matches[1]
    if ($digits.Length -ge 13) { $dto = [DateTimeOffset]::FromUnixTimeMilliseconds([long]$digits) } else { $dto = [DateTimeOffset]::FromUnixTimeSeconds([long]$digits) }
    return (New-Reply ('Local: ' + $dto.LocalDateTime.ToString('yyyy-MM-dd HH:mm:ss') + "`nUTC:   " + $dto.UtcDateTime.ToString('yyyy-MM-dd HH:mm:ss')) $null)
  }
  if ($l -match '^(?:generate )?(?:password|passwd)(?:\s+(\d+))?$') {
    $len = 16
    if ($Matches[1]) { $len = [int]$Matches[1] }
    $len = [Math]::Max(6, [Math]::Min(64, $len))
    $chars = 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789!@#$%^&*-_=+?'
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $bytes = New-Object byte[] $len
    $rng.GetBytes($bytes)
    $pw = -join ($bytes | ForEach-Object { $chars[[int]$_ % $chars.Length] })
    return (New-Reply ('Here is a strong password:' + "`n" + (Code-Block $pw)) $null)
  }
  if ($t -match '^(?:json|format json|pretty json)\s+([\s\S]+)$') {
    $js = $Matches[1]
    try { $pretty = ($js | ConvertFrom-Json) | ConvertTo-Json -Depth 20; return (New-Reply ('Formatted JSON:' + "`n" + (Code-Block $pretty)) $null) }
    catch { return (New-Reply ('That is not valid JSON: ' + $_.Exception.Message) $null) }
  }
  if ($t -match '^(?:upper|uppercase)\s+(.+)$') { $val = $Matches[1]; return (New-Reply $val.ToUpper() $null) }
  if ($t -match '^(?:lower|lowercase)\s+(.+)$') { $val = $Matches[1]; return (New-Reply $val.ToLower() $null) }
  if ($t -match '^(?:count|length|len)\s+(.+)$') {
    $val = $Matches[1]
    $wc = @($val -split '\s+' | Where-Object { $_ -ne '' }).Count
    return (New-Reply ('Characters: ' + $val.Length + '   Words: ' + $wc) $null)
  }
  if ($t -match '^reverse\s+(.+)$') {
    $arr = $Matches[1].ToCharArray()
    [array]::Reverse($arr)
    return (New-Reply (-join $arr) $null)
  }

  # --- web and apps ---
  if ($t -match '^(?:search|google|look up|lookup)\s+(?:for\s+)?(.+)$') { $q = $Matches[1]; Open-Web ('https://www.google.com/search?q=' + [uri]::EscapeDataString($q)); return (New-Reply ('Searching Google for: ' + $q) $null) }
  if ($t -match '^(?:so|stackoverflow|stack overflow)\s+(.+)$') { $q = $Matches[1]; Open-Web ('https://stackoverflow.com/search?q=' + [uri]::EscapeDataString($q)); return (New-Reply ('Searching Stack Overflow for: ' + $q) $null) }
  if ($t -match '^(?:youtube|yt)\s+(.+)$') { $q = $Matches[1]; Open-Web ('https://www.youtube.com/results?search_query=' + [uri]::EscapeDataString($q)); return (New-Reply ('Searching YouTube for: ' + $q) $null) }
  if ($t -match '^(?:docs|doc|mdn|devdocs)\s+(.+)$') { $q = $Matches[1]; Open-Web ('https://devdocs.io/#q=' + [uri]::EscapeDataString($q)); return (New-Reply ('Opening the docs for: ' + $q) $null) }
  if ($t -match '^open\s+((?:https?://|www\.)\S+)$') {
    $u = $Matches[1]
    if ($u -notmatch '^https?://') { $u = 'https://' + $u }
    Open-Web $u
    return (New-Reply ('Opening ' + $u) $null)
  }
  if ($l -match '^open\s+(.+)$') { $appName = $Matches[1]; return (New-Reply (Open-App $appName) $null) }

  # --- settings and toggles ---
  if ($l -match '^(settings|preferences|setup|config)$') { Show-Settings; return (New-Reply 'Settings window closed.' $null) }
  if ($l -match '^(talk|voice|speech|talk out loud) (on|off)$') {
    $cfg.talk = ($Matches[2] -eq 'on'); Save-Cfg
    if ($cfg.talk -and $null -eq $Voice) { return (New-Reply 'Sorry, text-to-speech is not available on this PC.' $null) }
    return (New-Reply ('Talking out loud is now ' + $Matches[2] + '.') $null)
  }
  if ($l -match '^(sound|sounds|bark sound|barking) (on|off)$') { $cfg.sounds = ($Matches[2] -eq 'on'); Save-Cfg; return (New-Reply ('Sounds are now ' + $Matches[2] + '.') $null) }
  if ($l -match '^(notification|notifications|notify) (on|off)$') { $cfg.notify = ($Matches[2] -eq 'on'); Save-Cfg; return (New-Reply ('Windows notifications are now ' + $Matches[2] + '.') $null) }
  if ($l -match '^(follow me|follow|follow on)$') { $cfg.follow = $true; Save-Cfg; return (New-Reply 'I will follow your mouse!' $null) }
  if ($l -match '^(stop following|unfollow|follow off|dont follow me|don''t follow me)$') { $cfg.follow = $false; Save-Cfg; return (New-Reply 'Okay, I will roam around on my own.' $null) }
  if ($l -match '^(?:size|be|make yourself|get)\s+(small|medium|large|big|huge|tiny|bigger|smaller|normal)$') {
    $want = $Matches[1]
    $order = @('small', 'medium', 'large', 'huge')
    $cur = [array]::IndexOf($order, [string]$cfg.size)
    if ($cur -lt 0) { $cur = 1 }
    switch ($want) {
      'tiny'    { $want = 'small' }
      'big'     { $want = 'large' }
      'normal'  { $want = 'medium' }
      'bigger'  { $want = $order[[Math]::Min(3, $cur + 1)] }
      'smaller' { $want = $order[[Math]::Max(0, $cur - 1)] }
    }
    $cfg.size = $want; Apply-Size; Save-Cfg
    return (New-Reply ('I am now ' + $want + '!') $null)
  }
  if ($l -match '^(topics|coding topics|what can i ask|knowledge|list topics)$') { return (New-Reply (Get-TopicsText) $null) }
  if ($l -match '^reload( knowledge)?$') { Load-Knowledge; return (New-Reply ('Reloaded knowledge.txt: ' + $KB.Count + ' answers.') $null) }

  # --- dog commands ---
  if ($l -match '^(show|show yourself|come back|appear)$') { Show-Dog; return (New-Reply 'Here I am!' $null) }
  if ($l -match '^(hide|go hide|hide yourself)$') { Hide-Dog 0; return (New-Reply 'Okay, I am hiding. Click my tray icon (near the clock) or type  show  to bring me back.' $null) }
  if ($t -match '^(?:say|repeat|repeat after me)[:\s]+(.+)$') {
    $phrase = $Matches[1]
    Show-Dog; Do-Action 'talk' 2.5; Say $phrase 4; Speak-Text $phrase $true
    return (New-Reply $phrase $null)
  }
  if ($l -match '^(play dead|bang)\b') { Do-Trick 'playdead'; return (New-Reply '*falls over* x_x ... just kidding!' $null) }
  if ($l -match '^(sit|sit down)\b') { Do-Trick 'sit'; return (New-Reply ('*sits nicely* ' + $EM.paw) $null) }
  if ($l -match '^(roll|roll over)\b') { Do-Trick 'roll'; return (New-Reply '*rolls over*' $null) }
  if ($l -match '^(jump|hop)\b') { Do-Trick 'jump'; return (New-Reply '*jumps* Boing!' $null) }
  if ($l -match '^(spin|chase your tail|turn around)\b') { Do-Trick 'spin'; return (New-Reply '*chases tail*' $null) }
  if ($l -match '^(shake|paw|give me (your |a )?paw|high five)\b') { Do-Trick 'shake'; return (New-Reply ('*gives paw* ' + $EM.paw) $null) }
  if ($l -match '^(dance|party)\b') { Do-Trick 'dance'; return (New-Reply '*dances*' $null) }
  if ($l -match '^(bark|speak|woof)\b') { Make-Bark; return (New-Reply 'WOOF WOOF!' $null) }
  if ($l -match '^(play|let''?s play|lets play|fetch|play with me)\b') { Play-WithDog; return (New-Reply ('Yay, let us play! ' + $EM.ball) $null) }
  if ($l -match '^(feed|eat|food|treat|bone|give (you )?a (bone|treat))\b') { Feed-Dog 'bone'; return (New-Reply ('Nom nom! Thank you! ' + $EM.bone) $null) }
  if ($l -match '^(sleep|nap|go to sleep|take a nap|go to bed)\b') { Take-Nap; return (New-Reply ('Zzz... ' + $EM.sleepy) $null) }
  if ($l -match '^(come|come here|here boy|here girl|here)\b') { Call-Dog; return (New-Reply 'Coming!' $null) }
  if ($l -match '^(stay|stop|freeze|wait)$') { Set-State 'sit' 30; return (New-Reply 'Staying right here.' $null) }

  # --- names and mood ---
  if ($t -match '^(?:my name is|call me)\s+(.+?)[.!]?$') { $cfg.userName = $Matches[1].Trim(); Save-Cfg; return (New-Reply ('Nice to meet you, ' + $cfg.userName + '! ' + $EM.paw) $null) }
  if ($t -match '^(?:your name is|i will call you|i''ll call you|call you|rename you to|rename (?:the )?dog to)\s+(.+?)[.!]?$') {
    $cfg.dogName = $Matches[1].Trim(); Save-Cfg; Update-ChatStatus
    return (New-Reply ('Woof! I am ' + $cfg.dogName + ' now! ' + $EM.dog) $null)
  }
  if ($l -match 'what(''s| is) my name') { return (New-Reply ('You are ' + $cfg.userName + ', my favorite human! ' + $EM.heart) $null) }
  if ($l -match '(what(''s| is) your name|who are you|what are you)') { return (New-Reply ('I am ' + $cfg.dogName + ', your desktop dog and assistant! Type  help  to see what I can do.') $null) }
  if ($l -match '(how are you|how r u|how are u|how do you feel|are you ok|are you happy|are you hungry|how is it going|hows it going|how''s it going|what''s up|whats up)') { return (New-Reply (Get-MoodText) $null) }

  # --- fun ---
  if ($l -match '\b(joke|funny|make me laugh)\b') { Do-Action 'happy' 1.5; return (New-Reply (Get-Random -InputObject $Jokes) $null) }
  if ($l -match '\b(quote|motivate|motivation|motivate me|inspire|inspiration)\b') { return (New-Reply ((Get-Random -InputObject $Quotes) + ' ' + $EM.muscle) $null) }
  if ($l -match '\b(dog fact|fun fact|fact)\b') { return (New-Reply ((Get-Random -InputObject $Facts) + ' ' + $EM.dog) $null) }

  # --- small talk ---
  if ($l -match '^(hi|hello|hey|hii+|heya|yo|hola|namaste|good (morning|afternoon|evening))\b') {
    $hour = (Get-Date).Hour
    $greet = 'Good evening'
    if ($hour -lt 12) { $greet = 'Good morning' } elseif ($hour -lt 18) { $greet = 'Good afternoon' }
    Do-Action 'wag' 1.5
    return (New-Reply ($greet + ', ' + $cfg.userName + '! ' + $EM.wave + ' How can I help? Type  help  to see everything I can do.') $null)
  }
  if ($l -match '\b(thanks|thank you|thx|tysm)\b') { Do-Action 'happy' 1.5; return (New-Reply ('You are welcome! *wags tail* ' + $EM.paw) $null) }
  if ($l -match '(love you|good (boy|girl|dog|puppy)|cute|you are the best|best dog)') { Do-Action 'happy' 2; Add-Happy 10; return (New-Reply ('Aww! I love you too, ' + $cfg.userName + '! ' + $EM.heart) $null) }
  if ($l -match '\b(tired|sleepy|exhausted|burned out|burnt out)\b') { return (New-Reply ('Take care of yourself! Try: a glass of water ' + $EM.water + ', a 5 minute stretch, or a short walk. Type  focus 25  when you are ready to work again.') $null) }
  if ($l -match '\b(sad|stressed|stress|anxious|upset|lonely|depressed|overwhelmed|angry)\b') { Do-Action 'wag' 2; return (New-Reply ('I am sorry you feel that way, ' + $cfg.userName + '. ' + $EM.heart + ' Try 5 slow deep breaths, drink some water, or take a short walk. Talking to a friend helps too. I am right here with you.') $null) }
  if ($l -match '\b(bored|boring)\b') { return (New-Reply 'Let us have fun! Type  play,  dance,  joke  or  dog fact.' $null) }
  if ($l -match '^(bye|goodbye|good night|gn|see you|see ya|cya)\b') { Do-Action 'wag' 1.5; return (New-Reply ('Bye bye! I will be right here. ' + $EM.paw) $null) }
  if ($l -match '^(ok|okay|cool|nice|great|awesome|lol|haha|yes|no)\b') { Do-Action 'wag' 1.2; return (New-Reply '*wags tail*' $null) }

  # --- coding knowledge ---
  $hit = Find-Knowledge $t
  if ($null -ne $hit) {
    $txt = [string]$hit.answer
    if ($hit.title) { $txt = $EM.book + ' ' + $hit.title + "`n`n" + $txt }
    return (New-Reply $txt $null)
  }

  if ($KB.Count -eq 0) { return (New-Reply 'I could not find my knowledge.txt file, so I do not know coding answers yet. Put knowledge.txt in the DogPet folder and type  reload.' $t) }
  return (New-Reply ('I do not know that one yet ' + $EM.think + "`n" + 'Try key words like  python read file  or  git undo commit,  type  topics  to see what I know, or search the web:') $t)
}

$PartCheck['3'] = $true   # ===== end of PART 3 of 7 =====
# ---------- chat window ----------
$BrushConv = New-Object System.Windows.Media.BrushConverter
function New-Brush($hex) { return $BrushConv.ConvertFromString($hex) }
function New-Thick($a, $b, $c, $d) { return (New-Object System.Windows.Thickness($a, $b, $c, $d)) }

function New-ReadOnlyText($text, $mono) {
  $tb = New-Object System.Windows.Controls.TextBox
  $tb.Text = [string]$text
  $tb.IsReadOnly = $true
  $tb.IsTabStop = $false
  $tb.BorderThickness = New-Thick 0 0 0 0
  $tb.Background = New-Brush '#00000000'
  if ($mono) {
    $tb.FontFamily = New-Object System.Windows.Media.FontFamily('Consolas')
    $tb.FontSize = 13
    $tb.Foreground = New-Brush '#D7E3FF'
    $tb.TextWrapping = 'NoWrap'
    $tb.HorizontalScrollBarVisibility = 'Auto'
  } else {
    $tb.Foreground = New-Brush '#F2F2F5'
    $tb.TextWrapping = 'Wrap'
  }
  return $tb
}

function Open-Chat {
  try {
    if ($null -eq $UI.chat) { Build-Chat }
    Update-ChatStatus
    if (-not $UI.chat.IsVisible) { $UI.chat.Show() }
    if ($UI.chat.WindowState -eq 'Minimized') { $UI.chat.WindowState = 'Normal' }
    $null = $UI.chat.Activate()
    $null = $UI.chatInput.Focus()
  } catch { Write-Log $_ }
}

# ---------- settings window ----------
function Get-StartupLink { return (Join-Path ([Environment]::GetFolderPath('Startup')) 'DogPet.lnk') }
function Set-Startup($on) {
  try {
    $lnk = Get-StartupLink
    if ($on) {
      $ws = New-Object -ComObject WScript.Shell
      $sc = $ws.CreateShortcut($lnk)
      $sc.TargetPath = Join-Path $AppDir 'DogPet.bat'
      $sc.WorkingDirectory = $AppDir
      $sc.WindowStyle = 7
      $sc.Save()
    } elseif (Test-Path $lnk) { Remove-Item $lnk -Force }
  } catch { Write-Log $_ }
}
function Fill-Combo($combo, $values, $current) {
  foreach ($v in $values) { $null = $combo.Items.Add([string]$v) }
  if (-not $combo.Items.Contains([string]$current)) { $null = $combo.Items.Add([string]$current) }
  $combo.SelectedItem = [string]$current
}
function Show-Settings {
  try {
    [xml]$setXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Dog Pet - Settings" Width="430" SizeToContent="Height" WindowStartupLocation="CenterScreen"
        ResizeMode="NoResize" Background="#1E1E26" FontFamily="Segoe UI" FontSize="13">
  <StackPanel Margin="18">
    <TextBlock Text="Settings" FontSize="20" FontWeight="SemiBold" Foreground="White" Margin="0,0,0,12"/>
    <Grid>
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="180"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>
      <Grid.RowDefinitions>
        <RowDefinition Height="34"/><RowDefinition Height="34"/><RowDefinition Height="34"/>
        <RowDefinition Height="34"/><RowDefinition Height="34"/><RowDefinition Height="34"/>
      </Grid.RowDefinitions>
      <TextBlock Grid.Row="0" Text="Your name" Foreground="#DDDDE5" VerticalAlignment="Center"/>
      <TextBox x:Name="SetUser" Grid.Row="0" Grid.Column="1" Margin="0,4"/>
      <TextBlock Grid.Row="1" Text="Dog name" Foreground="#DDDDE5" VerticalAlignment="Center"/>
      <TextBox x:Name="SetDog" Grid.Row="1" Grid.Column="1" Margin="0,4"/>
      <TextBlock Grid.Row="2" Text="Water reminder (minutes)" Foreground="#DDDDE5" VerticalAlignment="Center"/>
      <ComboBox x:Name="SetWater" Grid.Row="2" Grid.Column="1" Margin="0,4"/>
      <TextBlock Grid.Row="3" Text="Daily water goal (glasses)" Foreground="#DDDDE5" VerticalAlignment="Center"/>
      <ComboBox x:Name="SetGoal" Grid.Row="3" Grid.Column="1" Margin="0,4"/>
      <TextBlock Grid.Row="4" Text="Break reminder (minutes)" Foreground="#DDDDE5" VerticalAlignment="Center"/>
      <ComboBox x:Name="SetBreak" Grid.Row="4" Grid.Column="1" Margin="0,4"/>
      <TextBlock Grid.Row="5" Text="Dog size" Foreground="#DDDDE5" VerticalAlignment="Center"/>
      <ComboBox x:Name="SetSize" Grid.Row="5" Grid.Column="1" Margin="0,4"/>
    </Grid>
    <CheckBox x:Name="SetBreakOn" Content="Break reminders (stretch, rest your eyes)" Foreground="#DDDDE5" Margin="0,10,0,4"/>
    <CheckBox x:Name="SetTalk" Content="Talk out loud (text-to-speech)" Foreground="#DDDDE5" Margin="0,4"/>
    <CheckBox x:Name="SetSounds" Content="Bark sounds" Foreground="#DDDDE5" Margin="0,4"/>
    <CheckBox x:Name="SetNotify" Content="Windows notifications for reminders" Foreground="#DDDDE5" Margin="0,4"/>
    <CheckBox x:Name="SetFollow" Content="Follow my mouse" Foreground="#DDDDE5" Margin="0,4"/>
    <CheckBox x:Name="SetStartup" Content="Start Dog Pet when Windows starts" Foreground="#DDDDE5" Margin="0,4"/>
    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,16,0,0">
      <Button x:Name="SetCancel" Content="Cancel" Width="90" Height="30" Margin="0,0,8,0"/>
      <Button x:Name="SetSave" Content="Save" Width="90" Height="30" Background="#4A6CF7" Foreground="White" BorderThickness="0"/>
    </StackPanel>
  </StackPanel>
</Window>
'@
    $sw = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $setXaml))
    $f = @{}
    $UI.setWin = $sw
    $UI.setF = $f
    foreach ($nm in @('SetUser','SetDog','SetWater','SetGoal','SetBreak','SetSize','SetBreakOn','SetTalk','SetSounds','SetNotify','SetFollow','SetStartup','SetCancel','SetSave')) { $f[$nm] = $sw.FindName($nm) }
    $f.SetUser.Text = $cfg.userName
    $f.SetDog.Text = $cfg.dogName
    Fill-Combo $f.SetWater @(15, 20, 30, 45, 60, 90, 120) $cfg.waterMinutes
    Fill-Combo $f.SetGoal @(4, 5, 6, 7, 8, 9, 10, 12) $cfg.waterGoal
    Fill-Combo $f.SetBreak @(30, 45, 60, 90, 120) $cfg.breakMinutes
    Fill-Combo $f.SetSize @('small', 'medium', 'large', 'huge') $cfg.size
    $f.SetBreakOn.IsChecked = [bool]$cfg.breakOn
    $f.SetTalk.IsChecked = [bool]$cfg.talk
    $f.SetSounds.IsChecked = [bool]$cfg.sounds
    $f.SetNotify.IsChecked = [bool]$cfg.notify
    $f.SetFollow.IsChecked = [bool]$cfg.follow
    $f.SetStartup.IsChecked = (Test-Path (Get-StartupLink))
    $UI.setF.SetCancel.Add_Click({ $UI.setWin.Close() })
    $UI.setF.SetSave.Add_Click({
      try {
        if (-not [string]::IsNullOrWhiteSpace($UI.setF.SetUser.Text)) { $cfg.userName = $UI.setF.SetUser.Text.Trim() }
        if (-not [string]::IsNullOrWhiteSpace($UI.setF.SetDog.Text)) { $cfg.dogName = $UI.setF.SetDog.Text.Trim() }
        $newWater = [int]$UI.setF.SetWater.SelectedItem
        if ($newWater -ne [int]$cfg.waterMinutes) { $cfg.waterMinutes = $newWater; $PET.nextWater = [datetime]::Now.AddMinutes($newWater) }
        $cfg.waterGoal = [int]$UI.setF.SetGoal.SelectedItem
        $newBreak = [int]$UI.setF.SetBreak.SelectedItem
        if ($newBreak -ne [int]$cfg.breakMinutes) { $cfg.breakMinutes = $newBreak; $PET.nextBreak = [datetime]::Now.AddMinutes($newBreak) }
        $cfg.size = [string]$UI.setF.SetSize.SelectedItem
        $cfg.breakOn = [bool]$UI.setF.SetBreakOn.IsChecked
        $cfg.talk = [bool]$UI.setF.SetTalk.IsChecked
        $cfg.sounds = [bool]$UI.setF.SetSounds.IsChecked
        $cfg.notify = [bool]$UI.setF.SetNotify.IsChecked
        $cfg.follow = [bool]$UI.setF.SetFollow.IsChecked
        Set-Startup ([bool]$UI.setF.SetStartup.IsChecked)
        Apply-Size
        Save-Cfg
        Update-ChatStatus
        Say ('Settings saved! ' + $EM.paw) 3
      } catch { Write-Log $_ }
      $UI.setWin.Close()
    })
    $null = $sw.ShowDialog()
  } catch { Write-Log $_ }
}

# ---------- clicking the dog ----------
function On-DogClicked($pos) {
  $wasSleep = ($PET.state -eq 'sleep')
  if ($PET.pending -eq 'water') { Drink-Water; return }
  if ($PET.pending) {
    $PET.pending = $null
    Hide-Bubble
    Do-Action 'happy' 1.5
    Say ('Okay ' + $EM.heart) 3
    return
  }
  Add-Happy 3
  if ($wasSleep) {
    Set-State 'idle' 4
    Do-Action 'stretch' 1.6
    Say ('Yawn... hi ' + $cfg.userName + '! ' + $EM.paw) 3
    return
  }
  $isHead = $false
  if ($null -ne $pos -and $W.DogHost.ActualHeight -gt 0) {
    if (($pos.Y / $W.DogHost.ActualHeight) -lt 0.5) { $isHead = $true }
  }
  Set-State 'idle' 4
  if ($isHead) {
    Do-Action 'bark' 1.3
    Bark-Sound
    Say (Get-Random -InputObject @('Woof! Woof!', 'Bark bark!', ('I am ' + $cfg.dogName + '!'), 'Hey! That tickles!', 'Double-click me to chat!')) 3
  } else {
    Do-Action 'happy' 2.0
    Say (Get-Random -InputObject @(('Hehe, that tickles! ' + $EM.heart), ('I love you, ' + $cfg.userName + '! ' + $EM.heart), 'More belly rubs!', ('Wag wag! ' + $EM.paw))) 3
  }
}

# click = pet.  double-click = chat.  drag = pick the dog up.
$W.DogHost.Add_MouseLeftButtonDown({
  param($sender, $ev)
  try {
    if ($ev.ClickCount -ge 2) { Open-Chat; return }
    $pos = $ev.GetPosition($W.DogHost)
    $PET.dragging = $true
    $startL = $win.Left
    $startT = $win.Top
    try { $win.DragMove() } catch { }
    $PET.dragging = $false
    $moved = [Math]::Abs($win.Left - $startL) + [Math]::Abs($win.Top - $startT)
    if ($moved -lt 5) {
      $PET.state = 'idle'
      On-DogClicked $pos
    } else {
      $PET.x = Clamp-X $win.Left
      $PET.y = $win.Top
      $PET.target = $PET.x
      if ($PET.y -lt ($LAY.ground - 10)) { $PET.state = 'fall'; $PET.vy = 0.0; Say 'Wheee!' 2 }
      else { $PET.y = $LAY.ground; Set-State 'idle' 2 }
    }
  } catch { $PET.dragging = $false; Write-Log $_ }
})
$W.Bubble.Add_MouseLeftButtonDown({ try { On-DogClicked $null } catch { Write-Log $_ } })

# ---------- right-click menu ----------
function New-Entry($header, $handler) {
  $mi = New-Object System.Windows.Controls.MenuItem
  $mi.Header = $header
  if ($null -ne $handler) { $mi.Add_Click($handler) }
  return $mi
}
function Add-Entry($parent, $header, $handler) {
  $mi = New-Entry $header $handler
  $null = $parent.Items.Add($mi)
  return $mi
}
function Add-Sep($parent) { $null = $parent.Items.Add((New-Object System.Windows.Controls.Separator)) }

$menu = New-Object System.Windows.Controls.ContextMenu
$miMood = Add-Entry $menu 'Mood' $null
$miMood.IsEnabled = $false
$miWaterInfo = Add-Entry $menu 'Water' $null
$miWaterInfo.IsEnabled = $false
Add-Sep $menu
$miChat = Add-Entry $menu 'Chat with me...' { Open-Chat }
$miChat.FontWeight = 'Bold'
Add-Sep $menu

$miTricks = Add-Entry $menu 'Tricks' $null
$null = Add-Entry $miTricks 'Sit' { Do-Trick 'sit' }
$null = Add-Entry $miTricks 'Roll over' { Do-Trick 'roll' }
$null = Add-Entry $miTricks 'Jump' { Do-Trick 'jump' }
$null = Add-Entry $miTricks 'Spin (chase tail)' { Do-Trick 'spin' }
$null = Add-Entry $miTricks 'Shake paw' { Do-Trick 'shake' }
$null = Add-Entry $miTricks 'Dance' { Do-Trick 'dance' }
$null = Add-Entry $miTricks 'Play dead' { Do-Trick 'playdead' }
$null = Add-Entry $miTricks 'Bark' { Make-Bark }

$miCare = Add-Entry $menu 'Care' $null
$null = Add-Entry $miCare 'Give a bone' { Feed-Dog 'bone' }
$null = Add-Entry $miCare 'Give a treat' { Feed-Dog 'treat' }
$null = Add-Entry $miCare 'Play with me' { Play-WithDog }
$null = Add-Entry $miCare 'Take a nap' { Take-Nap }

$miWater = Add-Entry $menu 'Water' $null
$null = Add-Entry $miWater 'I drank a glass of water' { Drink-Water }
Add-Sep $miWater
$waterItems = @()
foreach ($mins in 15, 20, 30, 45, 60, 90) {
  $item = Add-Entry $miWater ('Remind me every ' + $mins + ' minutes') { param($sender, $ev) try { Set-WaterInterval ([int]$sender.Tag) } catch { Write-Log $_ } }
  $item.Tag = $mins
  $item.IsCheckable = $true
  $waterItems += $item
}

$miFocus = Add-Entry $menu 'Focus timer' $null
$null = Add-Entry $miFocus 'Focus 25 minutes' { $null = Start-Focus 25 }
$null = Add-Entry $miFocus 'Focus 50 minutes' { $null = Start-Focus 50 }
$null = Add-Entry $miFocus 'Stop focus' { $null = Stop-Focus; Say 'Focus stopped.' 2 }

$miTasks = Add-Entry $menu 'Reminders and to-dos' $null
$null = Add-Entry $miTasks 'Remind me about something...' { try { Ask-Reminder } catch { Write-Log $_ } }
$null = Add-Entry $miTasks 'Add a to-do...' { try { Ask-Todo } catch { Write-Log $_ } }
$null = Add-Entry $miTasks 'Show reminders and to-dos' { $null = [System.Windows.MessageBox]::Show(((Get-RemindersText) + "`n`n" + (Get-TodosText)), 'Dog Pet') }
$null = Add-Entry $miTasks 'What time is it?' { Say ((Get-Date).ToString('dddd, MMMM d  -  h:mm tt')) 6 }
Add-Sep $menu

$miFollow = Add-Entry $menu 'Follow my mouse' { $cfg.follow = [bool]$miFollow.IsChecked; Save-Cfg }
$miFollow.IsCheckable = $true
$miTalk = Add-Entry $menu 'Talk out loud' { $cfg.talk = [bool]$miTalk.IsChecked; Save-Cfg; if ($cfg.talk) { Speak-Text ('Hi ' + $cfg.userName + '! I can talk now!') $true } }
$miTalk.IsCheckable = $true
$miSound = Add-Entry $menu 'Bark sounds' { $cfg.sounds = [bool]$miSound.IsChecked; Save-Cfg }
$miSound.IsCheckable = $true
$miSize = Add-Entry $menu 'Size' $null
$sizeItems = @()
foreach ($sz in 'small', 'medium', 'large', 'huge') {
  $item = Add-Entry $miSize ($sz.Substring(0, 1).ToUpper() + $sz.Substring(1)) { param($sender, $ev) try { $cfg.size = [string]$sender.Tag; Apply-Size; Save-Cfg } catch { Write-Log $_ } }
  $item.Tag = $sz
  $item.IsCheckable = $true
  $sizeItems += $item
}
$null = Add-Entry $menu 'Hide for 30 minutes' { Hide-Dog 30 }
$null = Add-Entry $menu 'Settings...' { Show-Settings }
Add-Sep $menu
$null = Add-Entry $menu 'Quit Dog Pet' { Quit-App }

$menu.Add_Opened({
  try {
    Update-DayCounter
    $miMood.Header = 'Fullness ' + [int]$cfg.fullness + '%   Happiness ' + [int]$cfg.happiness + '%'
    $miWaterInfo.Header = 'Water today: ' + $cfg.glasses + ' / ' + $cfg.waterGoal + ' glasses'
    $miFollow.IsChecked = [bool]$cfg.follow
    $miTalk.IsChecked = [bool]$cfg.talk
    $miSound.IsChecked = [bool]$cfg.sounds
    foreach ($entry in $waterItems) { $entry.IsChecked = ([int]$entry.Tag -eq [int]$cfg.waterMinutes) }
    foreach ($entry in $sizeItems) { $entry.IsChecked = ([string]$entry.Tag -eq [string]$cfg.size) }
  } catch { Write-Log $_ }
})
$W.DogHost.ContextMenu = $menu

# ---------- tray icon (near the clock) ----------
function Make-TrayIcon {
  try {
    $path = $null
    if ($PhotoMode) { $path = $ImgPaths[$MainKey]; if ($ImgPaths.ContainsKey('happy')) { $path = $ImgPaths['happy'] } }
    if ($path) {
      $src = [System.Drawing.Image]::FromFile($path)
      $bmpIcon = New-Object System.Drawing.Bitmap(32, 32)
      $g = [System.Drawing.Graphics]::FromImage($bmpIcon)
      $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
      $ratio = [Math]::Min(32.0 / $src.Width, 32.0 / $src.Height)
      $dw = [int]($src.Width * $ratio)
      $dh = [int]($src.Height * $ratio)
      $g.DrawImage($src, [int]((32 - $dw) / 2), [int]((32 - $dh) / 2), $dw, $dh)
      $g.Dispose()
      $src.Dispose()
      return [System.Drawing.Icon]::FromHandle($bmpIcon.GetHicon())
    }
  } catch { Write-Log $_ }
  return [System.Drawing.SystemIcons]::Information
}
try {
  $Tray = New-Object System.Windows.Forms.NotifyIcon
  $Tray.Icon = Make-TrayIcon
  $Tray.Text = 'Dog Pet - double-click to chat'
  $cms = New-Object System.Windows.Forms.ContextMenuStrip
  $null = $cms.Items.Add('Chat with me', $null, { Open-Chat })
  $null = $cms.Items.Add('Show / hide the dog', $null, { if ($PET.hidden) { Show-Dog } else { Hide-Dog 0 } })
  $null = $cms.Items.Add('Settings...', $null, { Show-Settings })
  $null = $cms.Items.Add('-')
  $null = $cms.Items.Add('Quit Dog Pet', $null, { Quit-App })
  $Tray.ContextMenuStrip = $cms
  $Tray.Add_MouseClick({ param($sender, $ev) if ($ev.Button -eq [System.Windows.Forms.MouseButtons]::Left) { Open-Chat } })
  $Tray.Visible = $true
} catch { $Tray = $null; Write-Log $_ }

function Quit-App {
  if ($UI.quitting) { return }
  $UI.quitting = $true
  try { Save-Cfg } catch { }
  try { $timer.Stop(); $checker.Stop() } catch { }
  try { if ($null -ne $Voice) { $Voice.SpeakAsyncCancelAll(); $Voice.Dispose() } } catch { }
  try { if ($null -ne $Tray) { $Tray.Visible = $false; $Tray.Dispose() } } catch { }
  try { if ($null -ne $UI.chat) { $UI.chat.Close() } } catch { }
  try { $win.Close() } catch { }
  [System.Windows.Threading.Dispatcher]::CurrentDispatcher.InvokeShutdown()
}
$win.Add_Closed({ Quit-App })

# ---------- animation loop (25 frames per second, light on the CPU) ----------
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(40)
$timer.Add_Tick({
  try {
    $now = [datetime]::Now
    $PET.t += 0.04
    $PET.frame++
    $tm = $PET.t

    # ----- movement / behaviour -----
    if ($PET.dragging) {
      $PET.state = 'held'
    } else {
      if ($PET.state -eq 'held') { $PET.state = 'idle' }
      if ($PET.state -eq 'fall') {
        $PET.vy += 1.4
        $PET.y += $PET.vy
        if ($PET.y -ge $LAY.ground) {
          $PET.y = $LAY.ground; $PET.vy = 0.0
          Set-State 'idle' 2; Do-Action 'bark' 1.0; Say 'Landed! Woof!' 2
        }
      } else { $PET.y = $LAY.ground }

      $following = [bool]$cfg.follow -and ($PET.state -ne 'fall') -and (-not $PET.pending) -and (-not $PET.action)
      $mp = $null
      if ($following -or ($PET.frame % 5) -eq 0) { $mp = Get-MouseDip }

      if ($PET.pending -and $PET.state -ne 'fall') {
        $PET.state = 'idle'
      } elseif ($following) {
        if ($null -ne $mp) {
          $PET.target = Clamp-X ($mp.X - $LAY.winW / 2)
          if ([Math]::Abs($PET.target - $PET.x) -gt 30) { $PET.state = 'run' }
          elseif ($PET.state -eq 'run' -or $PET.state -eq 'walk') { Set-State 'sit' 2 }
        }
      } elseif ($PET.state -ne 'fall' -and $now -gt $PET.nextChange -and -not $PET.action) {
        Pick-Behavior
      }

      # curious: look at the mouse when it comes close
      if (-not $following -and $null -ne $mp -and -not $PET.action -and ($PET.state -eq 'idle' -or $PET.state -eq 'sit')) {
        $dxm = $mp.X - ($PET.x + $LAY.winW / 2)
        $dym = $mp.Y - ($PET.y + $LAY.winH - $LAY.hostH / 2)
        if ([Math]::Abs($dxm) -lt 240 -and [Math]::Abs($dym) -lt 220) {
          if ([Math]::Abs($dxm) -gt 40) { $PET.dir = [int][Math]::Sign($dxm) }
          if (-not $PET.near) {
            $PET.near = $true
            if ((Get-Random -Minimum 0 -Maximum 100) -lt 35) { Do-Action 'wag' 1.5 }
          }
        } else { $PET.near = $false }
      }

      if ($PET.state -eq 'walk' -or $PET.state -eq 'run') {
        $dist = $PET.target - $PET.x
        $speed = 2.8 * $LAY.scale
        if ($PET.state -eq 'run') { $speed = 7.0 * $LAY.scale }
        if ([Math]::Abs($dist) -le $speed) {
          $PET.x = $PET.target
          if (-not $following) { Set-State 'idle' (Get-Random -Minimum 1 -Maximum 4) }
        } else {
          $PET.dir = [int][Math]::Sign($dist)
          $PET.x += $PET.dir * $speed
        }
      }
    }

    # ----- timed actions -----
    $act = $PET.action
    $prog = 0.0
    if ($act -and $now -ge $PET.actionUntil) {
      $PET.action = $null
      $finished = $act
      $act = $null
      if ($finished -eq 'eat') { Do-Action 'happy' 1.6; $act = 'happy' }
      elseif ($finished -eq 'playdead') { Say 'Just kidding! Woof!' 2; Do-Action 'happy' 1.2; $act = 'happy' }
    }
    if ($act) {
      $span = ($PET.actionUntil - $PET.actionStart).TotalSeconds
      if ($span -gt 0) { $prog = [Math]::Min(1.0, [Math]::Max(0.0, ($now - $PET.actionStart).TotalSeconds / $span)) }
    }

    # ----- pose for this frame -----
    $fxY = 0.0; $fxX = 0.0; $fxRot = 0.0; $fxSx = 1.0; $fxSy = 1.0
    $faceT = [double]$PET.dir; $faceRaw = $false
    $pZzz = ($PET.state -eq 'sleep')

    $StillPhotos = ($PhotoMode -and -not $GifMode)
    if ($StillPhotos) {
      switch ($PET.state) {
        'walk'  { $fxY = -1 * [Math]::Abs([Math]::Sin($tm * 10)) * 6; $fxRot = [Math]::Sin($tm * 10) * 3 }
        'run'   { $fxY = -1 * [Math]::Abs([Math]::Sin($tm * 15)) * 11; $fxRot = [Math]::Sin($tm * 15) * 4; $fxSx = 1.04; $fxSy = 0.97 }
        'sit'   { $fxSy = 0.99 + [Math]::Sin($tm * 2.0) * 0.01 }
        'sleep' { $fxSy = 0.97 + [Math]::Sin($tm * 1.6) * 0.02 }
        'held'  { $fxRot = [Math]::Sin($tm * 14) * 8 }
        'fall'  { $fxRot = [Math]::Sin($tm * 10) * 6 }
        default { $fxSy = 1.0 + [Math]::Sin($tm * 2.2) * 0.015 }
      }
    } elseif ($PET.state -eq 'held') { $fxRot = [Math]::Sin($tm * 5) * 6 }

    if ($act -and ($StillPhotos -or (@('play','jump','spin','roll','dance','playdead','look') -contains $act))) {
      switch ($act) {
        'bark'     { $sq = [Math]::Abs([Math]::Sin($tm * 22)); $fxSy = 1.0 + $sq * 0.07; $fxSx = 1.0 - $sq * 0.03; $fxY = -1 * [Math]::Abs([Math]::Sin($tm * 11)) * 5}
        'talk'     { $sq = [Math]::Abs([Math]::Sin($tm * 16)); $fxSy = 1.0 + $sq * 0.035}
        'happy'    { $fxRot = [Math]::Sin($tm * 25) * 5; $fxSx = 1.03; $fxSy = 1.03}
        'wag'      { $fxRot = [Math]::Sin($tm * 20) * 2.5}
        'eat'      { $fxRot = 3 + [Math]::Sin($tm * 16) * 2; $fxY = [Math]::Abs([Math]::Sin($tm * 16)) * 3}
        'play'     { $fxY = -1 * [Math]::Abs([Math]::Sin($tm * 6)) * 28; $faceT = $PET.dir * [Math]::Cos($tm * 9); $faceRaw = $true}
        'jump'     { $fxY = -280 * $prog * (1 - $prog); $fxSy = 1.0 + 0.06 * [Math]::Sin($prog * [Math]::PI)}
        'spin'     { $faceT = $PET.dir * [Math]::Cos($prog * [Math]::PI * 4); $faceRaw = $true; $fxY = -1 * [Math]::Abs([Math]::Sin($prog * [Math]::PI * 4)) * 6}
        'roll'     { $fxRot = 360 * $prog; $fxY = -1 * [Math]::Sin($prog * [Math]::PI) * 14 }
        'shake'    { $fxRot = -8 + [Math]::Sin($tm * 10) * 2; $fxY = -3.0}
        'dance'    { $fxY = -1 * [Math]::Abs([Math]::Sin($tm * 8)) * 14; $fxRot = [Math]::Sin($tm * 8) * 7; $faceRaw = $true; if ([Math]::Sin($tm * 4) -ge 0) { $faceT = 1.0 } else { $faceT = -1.0 }}
        'playdead' { $fxRot = -90 * [Math]::Min(1.0, $prog * 5); $fxY = 8.0 * [Math]::Min(1.0, $prog * 5)}
        'sniff'    { $fxRot = 5 + [Math]::Sin($tm * 18) * 1.5; $fxY = [Math]::Abs([Math]::Sin($tm * 18)) * 2}
        'scratch'  { $fxX = [Math]::Sin($tm * 40) * 2; $fxRot = [Math]::Sin($tm * 30) * 2}
        'stretch'  { $kk = [Math]::Sin($prog * [Math]::PI); $fxSx = 1.0 + 0.1 * $kk; $fxSy = 1.0 - 0.08 * $kk}
        'look'     { if ($prog -gt 0.33 -and $prog -lt 0.66) { $faceT = -1.0 * $PET.dir } }
      }
    }

    # hop to get attention when a reminder is waiting
    if ($PET.pending) { $fxY = -1 * [Math]::Abs([Math]::Sin($tm * 7)) * 10 }

    # smooth turn-around
    if ($faceRaw) { $PET.face = $faceT } else { $PET.face = $PET.face + ($faceT - $PET.face) * 0.35 }
    $faceSign = 1.0

    $W.ActScale.ScaleX = $PET.face * $fxSx * $faceSign
    $W.ActScale.ScaleY = $fxSy
    $W.ActMove.X = $fxX
    $W.ActMove.Y = $fxY
    $W.ActRot.Angle = $fxRot
    $hopAmt = [Math]::Min(1.0, [Math]::Max(0.0, -1 * $fxY / 80))
    $W.ShadowScale.ScaleX = 1.0 - 0.5 * $hopAmt
    $W.ShadowScale.ScaleY = 1.0 - 0.5 * $hopAmt
    if ($pZzz) { $W.ZzzText.Visibility = 'Visible' } else { $W.ZzzText.Visibility = 'Collapsed' }

    if ($PhotoMode) {
      $photoSrc = Get-PhotoFor $PET.state $act $tm
      if (-not [object]::ReferenceEquals($W.DogPhoto.Source, $photoSrc)) { $W.DogPhoto.Source = $photoSrc }
    } else {
      if ($now -gt $PET.nextBlink) {
        $PET.blinkUntil = $now.AddMilliseconds(150)
        $PET.nextBlink = $now.AddSeconds((Get-Random -Minimum 2 -Maximum 6))
      }
      $dp = Get-DogPose $PET.state $tm $act $prog
      Apply-DogPose $dp ($now -lt $PET.blinkUntil)
    }

    if (-not $PET.dragging -and -not $PET.hidden) {
      $win.Left = $PET.x
      $win.Top = $PET.y
    }
    if ((-not $PET.sticky) -and $W.Bubble.Visibility -eq 'Visible' -and $now -gt $PET.bubbleUntil) { Hide-Bubble }
  } catch { Write-Log $_ }
})

$PartCheck['4'] = $true   # ===== end of PART 4 of 7 =====
# ---------- reminders + needs checker (once per second) ----------
$checker = New-Object System.Windows.Threading.DispatcherTimer
$checker.Interval = [TimeSpan]::FromSeconds(1)
$checker.Add_Tick({
  try {
    $now = [datetime]::Now
    $cfg.fullness = [Math]::Max(0, [double]$cfg.fullness - 0.0083)
    $cfg.happiness = [Math]::Max(0, [double]$cfg.happiness - 0.0067)
    $PET.saveTicks++
    if ($PET.saveTicks -ge 120) { $PET.saveTicks = 0; Save-Cfg; Update-ChatStatus }

    if ($PET.hidden -and $now -ge $PET.showAt) { Show-Dog; Say 'I am back! ' 3 }
    if ($PET.pending -and $PET.pending -ne 'water' -and $now -gt $PET.pendingExpire) { $PET.pending = $null; Hide-Bubble }

    # your own reminders always come first
    $due = $null
    foreach ($rem in $PET.reminders) { if ($rem.at -le $now) { $due = $rem; break } }
    if ($null -ne $due -and $PET.state -ne 'held') {
      $PET.reminders.Remove($due)
      Save-Cfg
      Show-Dog
      Start-Alert 'custom' ($EM.bell + ' Reminder: ' + $due.text) 10
      return
    }

    if ($PET.focusOn -and $now -ge $PET.focusUntil) {
      $PET.focusOn = $false
      $null = Add-ReminderAt ($now.AddMinutes(5)) 'Break is over - ready for another focus session? Type focus in the chat.' $true
      Show-Dog
      Start-Alert 'focus' ('Focus session done! Great work, ' + $cfg.userName + '. Take a 5 minute break ' + $EM.star) 10
      return
    }

    if ($PET.pending -eq 'water') {
      if ($now -ge $PET.nextWater) { Start-WaterReminder }
    } elseif (-not $PET.pending -and $PET.state -ne 'fall' -and $PET.state -ne 'held') {
      if ($now -ge $PET.nextWater) { Start-WaterReminder }
      elseif (-not $PET.focusOn -and [bool]$cfg.breakOn -and $now -ge $PET.nextBreak) { Start-BreakReminder }
      elseif (-not $PET.focusOn -and -not $PET.hidden -and $now -ge $PET.nextNag) {
        if ([double]$cfg.fullness -lt 30) {
          $PET.nextNag = $now.AddMinutes(15); Set-State 'sit' 15
          Say ('I am hungry... ' + $EM.bone + ' Right-click me: Care > Give a bone') 9
        } elseif ([double]$cfg.happiness -lt 30) {
          $PET.nextNag = $now.AddMinutes(15); Set-State 'sit' 15
          Say ('I am bored... ' + $EM.ball + ' Right-click me: Care > Play with me') 9
        } elseif ($now.Hour -ge 23 -and $PET.lateNag -ne $now.ToString('yyyy-MM-dd')) {
          $PET.lateNag = $now.ToString('yyyy-MM-dd')
          Say ('It is late, ' + $cfg.userName + '. Time to rest soon! ' + $EM.sleepy) 8
        }
      }
    }
  } catch { Write-Log $_ }
})

# =====================================================================
# ---------- THE DOG'S OWN BRAIN (an offline agent - no outside AI) ----------
# Everything runs on this PC. Nothing is sent to ChatGPT, Gemini or any
# other AI company. The dog understands what you ask, does things on your
# PC, and learns what you teach it.
# What it learns is saved in  %APPDATA%\DogPet\brain.json
# =====================================================================
$brainFile = Join-Path $dataDir 'brain.json'
$BRAIN = @{
  facts = (New-Object System.Collections.ArrayList)
  notes = (New-Object System.Collections.ArrayList)
  shortcuts = @{}
  routines = @{}
  lastBrief = ''
  results = (New-Object System.Collections.ArrayList)
  lastReply = ''; lastCmd = ''
  confirm = $null
  apps = $null
  dl = $null
  battWarned = [datetime]::MinValue
}

# the old AI-key file from the previous version is not needed any more
try { $oldAiFile = Join-Path $dataDir 'ai.json'; if (Test-Path $oldAiFile) { Remove-Item $oldAiFile -Force } } catch { }

function Load-Brain {
  if (-not (Test-Path $brainFile)) { return }
  try {
    $j = Get-Content $brainFile -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($fa in @($j.facts)) { if ($null -ne $fa -and $fa.q) { $null = $BRAIN.facts.Add(@{ q = [string]$fa.q; a = [string]$fa.a; said = [bool]$fa.said }) } }
    foreach ($nt in @($j.notes)) { if ($null -ne $nt -and $nt.text) { $null = $BRAIN.notes.Add(@{ text = [string]$nt.text; at = [string]$nt.at }) } }
    if ($null -ne $j.shortcuts) { foreach ($pp in $j.shortcuts.PSObject.Properties) { $BRAIN.shortcuts[$pp.Name] = [string]$pp.Value } }
    if ($null -ne $j.routines) { foreach ($pp in $j.routines.PSObject.Properties) { $BRAIN.routines[$pp.Name] = @($pp.Value | ForEach-Object { [string]$_ }) } }
    if ($j.lastBrief) { $BRAIN.lastBrief = [string]$j.lastBrief }
  } catch { Write-Log $_ }
}
function Save-Brain {
  try {
    $data = @{ facts = @($BRAIN.facts); notes = @($BRAIN.notes); shortcuts = $BRAIN.shortcuts; routines = $BRAIN.routines; lastBrief = $BRAIN.lastBrief }
    (ConvertTo-Json -InputObject $data -Depth 6) | Set-Content -Path $brainFile -Encoding UTF8
  } catch { Write-Log $_ }
}
function Get-BrainText {
  return ('Brain: my own (offline, nothing leaves this PC)  |  learned ' + $BRAIN.facts.Count + '  |  notes ' + $BRAIN.notes.Count)
}
Load-Brain

# ---------- understanding words (typos, similar words) ----------
$StopWords = @('a', 'an', 'the', 'is', 'are', 'was', 'were', 'am', 'be', 'to', 'of', 'in', 'on', 'at', 'for', 'and', 'or', 'my', 'me', 'i',
  'you', 'your', 'our', 'it', 'its', 'do', 'doe', 'did', 'what', 'whats', 'when', 'where', 'who', 'which', 'how', 'why', 'tell', 'about',
  'please', 'can', 'could', 'would', 'will', 'that', 'this', 'there', 'with', 'from', 'by', 'as', 'so', 'we', 'us', 'know', 'remember')
function Get-EditDistance($s1, $s2) {
  $n1 = $s1.Length
  $n2 = $s2.Length
  if ($n1 -eq 0) { return $n2 }
  if ($n2 -eq 0) { return $n1 }
  $cols = $n2 + 1
  $d = New-Object 'int[]' (($n1 + 1) * $cols)
  for ($i = 0; $i -le $n1; $i++) { $d[$i * $cols] = $i }
  for ($j = 0; $j -le $n2; $j++) { $d[$j] = $j }
  for ($i = 1; $i -le $n1; $i++) {
    for ($j = 1; $j -le $n2; $j++) {
      $cost = 1
      if ($s1[$i - 1] -ceq $s2[$j - 1]) { $cost = 0 }
      $up = $d[($i - 1) * $cols + $j] + 1
      $left = $d[$i * $cols + $j - 1] + 1
      $diag = $d[($i - 1) * $cols + $j - 1] + $cost
      $best = [Math]::Min([Math]::Min($up, $left), $diag)
      if ($i -gt 1 -and $j -gt 1 -and $s1[$i - 1] -ceq $s2[$j - 2] -and $s1[$i - 2] -ceq $s2[$j - 1]) {
        $swap = $d[($i - 2) * $cols + $j - 2] + 1
        if ($swap -lt $best) { $best = $swap }
      }
      $d[$i * $cols + $j] = $best
    }
  }
  return $d[$n1 * $cols + $n2]
}
function Same-Word($w1, $w2) {
  if ($w1 -eq $w2) { return $true }
  $len = [Math]::Min($w1.Length, $w2.Length)
  if ($len -lt 4) { return $false }
  $limit = 1
  if ($len -ge 8) { $limit = 2 }
  if ([Math]::Abs($w1.Length - $w2.Length) -gt $limit) { return $false }
  return ((Get-EditDistance $w1 $w2) -le $limit)
}
function Get-Words($s) {
  $out = @()
  foreach ($wd in ((Simplify-Text $s) -split ' ')) { if ($wd -ne '' -and $StopWords -notcontains $wd) { $out += $wd } }
  return $out
}
function Get-MatchScore($qWords, $kWords) {
  # how much of kWords is found in qWords (0 to 1), allowing small typos
  $kw = @($kWords)
  if ($kw.Count -eq 0) { return 0.0 }
  $hit = 0
  foreach ($kx in $kw) { foreach ($qx in @($qWords)) { if (Same-Word $qx $kx) { $hit++; break } } }
  return ($hit / $kw.Count)
}
function Flip-Person($s) {
  # "my car is on level 3"  ->  "your car is on level 3"
  $x = ' ' + [string]$s + ' '
  $x = $x -replace '(?i) i am ', ' you are ' -replace '(?i) i''m ', ' you are ' -replace '(?i) i was ', ' you were '
  $x = $x -replace '(?i) my ', ' your ' -replace '(?i) mine ', ' yours ' -replace '(?i) i ', ' you ' -replace '(?i) me ', ' you ' -replace '(?i) myself ', ' yourself ' -replace '(?i) our ', ' your '
  return $x.Trim()
}

# ---------- little text helpers ----------
function Short-Text($s, $maxLen) {
  $plain = [string]$s
  $fence = $plain.IndexOf('```')
  if ($fence -ge 0) { $plain = $plain.Substring(0, $fence) }
  $plain = ($plain -replace '\s+', ' ').Trim()
  if ($plain.Length -gt $maxLen) { $plain = $plain.Substring(0, $maxLen).TrimEnd() + '...' }
  return $plain
}
function Format-Size($bytes) {
  $bt = [double]$bytes
  if ($bt -ge 1TB) { return ('{0:N1} TB' -f ($bt / 1TB)) }
  if ($bt -ge 1GB) { return ('{0:N1} GB' -f ($bt / 1GB)) }
  if ($bt -ge 1MB) { return ('{0:N1} MB' -f ($bt / 1MB)) }
  if ($bt -ge 1KB) { return ('{0:N0} KB' -f ($bt / 1KB)) }
  return ([string][int]$bt + ' bytes')
}
function Format-When($dt) {
  try {
    $dd = [datetime]$dt
    if ($dd.Date -eq [datetime]::Today) { return ('today ' + $dd.ToString('h:mm tt')) }
    if ($dd.Date -eq [datetime]::Today.AddDays(-1)) { return ('yesterday ' + $dd.ToString('h:mm tt')) }
    return $dd.ToString('d MMM yyyy')
  } catch { return '' }
}
function Short-Path($p) {
  $s = [string]$p
  if ($s.Length -gt 75) { $s = $s.Substring(0, 28) + '...' + $s.Substring($s.Length - 44) }
  return $s
}

# ---------- folders, settings pages and apps I can open ----------
function Get-DownloadsPath {
  try {
    $v = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' -ErrorAction Stop).'{374DE290-123F-4565-9164-39C4925E467B}'
    if ($v) { $v = [Environment]::ExpandEnvironmentVariables([string]$v); if (Test-Path -LiteralPath $v) { return $v } }
  } catch { }
  return (Join-Path $env:USERPROFILE 'Downloads')
}
function Get-NamedFolder($nm) {
  $x = ([string]$nm).ToLower().Trim() -replace '\s+folder$', ''
  if ($x -match '^desktop$') { return [Environment]::GetFolderPath('Desktop') }
  if ($x -match '^(my )?(documents?|docs)$') { return [Environment]::GetFolderPath('MyDocuments') }
  if ($x -match '^downloads?$') { return (Get-DownloadsPath) }
  if ($x -match '^(pictures|photos|images)$') { return [Environment]::GetFolderPath('MyPictures') }
  if ($x -match '^videos?$') { return [Environment]::GetFolderPath('MyVideos') }
  if ($x -match '^music$') { return [Environment]::GetFolderPath('MyMusic') }
  if ($x -match '^onedrive$') { if ($env:OneDriveCommercial) { return $env:OneDriveCommercial }; return $env:OneDrive }
  if ($x -match '^(home|user|my user)$') { return $env:USERPROFILE }
  if ($x -match '^[a-z]:\\?$') { return ($x.Substring(0, 1).ToUpper() + ':\') }
  if ($x -match '^[a-z]:\\') { return ([string]$nm).Trim() }
  if ($x -match '^([a-z]) drive$') { return ($Matches[1].ToUpper() + ':\') }
  return $null
}
$KnownFolders = @{
  'desktop' = 'shell:Desktop'; 'documents' = 'shell:Personal'; 'my documents' = 'shell:Personal'; 'docs' = 'shell:Personal'
  'downloads' = 'shell:Downloads'; 'download' = 'shell:Downloads'; 'pictures' = 'shell:My Pictures'; 'photos' = 'shell:My Pictures'
  'music' = 'shell:My Music'; 'videos' = 'shell:My Video'; 'recycle bin' = 'shell:RecycleBinFolder'; 'trash' = 'shell:RecycleBinFolder'
  'this pc' = 'shell:MyComputerFolder'; 'my computer' = 'shell:MyComputerFolder'; 'my pc' = 'shell:MyComputerFolder'
  'startup' = 'shell:Startup'; 'fonts' = 'shell:Fonts'; 'home' = $env:USERPROFILE; 'user' = $env:USERPROFILE
  'appdata' = $env:APPDATA; 'temp' = $env:TEMP; 'onedrive' = $env:OneDrive
  'dog' = $AppDir; 'dogpet' = $AppDir; 'dog pet' = $AppDir; 'your' = $AppDir; 'dog data' = $dataDir; 'your data' = $dataDir
  'screenshots' = (Join-Path ([Environment]::GetFolderPath('MyPictures')) 'Screenshots')
}
$SettingsPages = @{
  'wifi' = 'network-wifi'; 'wi-fi' = 'network-wifi'; 'bluetooth' = 'bluetooth'; 'display' = 'display'; 'screen' = 'display'
  'brightness' = 'display'; 'display brightness' = 'display'; 'sound' = 'sound'; 'audio' = 'sound'; 'volume' = 'sound'
  'apps' = 'appsfeatures'; 'installed apps' = 'appsfeatures'; 'windows update' = 'windowsupdate'; 'update' = 'windowsupdate'
  'updates' = 'windowsupdate'; 'battery' = 'batterysaver'; 'power' = 'powersleep'; 'notification' = 'notifications'
  'notifications' = 'notifications'; 'privacy' = 'privacy'; 'mouse' = 'mousetouchpad'; 'touchpad' = 'devices-touchpad'
  'keyboard' = 'typing'; 'typing' = 'typing'; 'storage' = 'storagesense'; 'date and time' = 'dateandtime'; 'time' = 'dateandtime'
  'language' = 'regionlanguage'; 'region' = 'regionformatting'; 'background' = 'personalization-background'
  'wallpaper' = 'personalization-background'; 'theme' = 'themes'; 'themes' = 'themes'; 'night light' = 'nightlight'
  'dark mode' = 'colors'; 'colors' = 'colors'; 'printer' = 'printers'; 'printers' = 'printers'; 'vpn' = 'network-vpn'
  'proxy' = 'network-proxy'; 'default apps' = 'defaultapps'; 'startup apps' = 'startupapps'; 'account' = 'yourinfo'
  'accounts' = 'yourinfo'; 'camera' = 'privacy-webcam'; 'microphone' = 'privacy-microphone'; 'mic' = 'privacy-microphone'
  'ethernet' = 'network-ethernet'; 'network' = 'network-status'; 'hotspot' = 'network-mobilehotspot'
  'focus assist' = 'quiethours'; 'do not disturb' = 'quiethours'
}
$AdminTools = @{
  'control panel' = 'control.exe'; 'device manager' = 'devmgmt.msc'; 'services' = 'services.msc'; 'event viewer' = 'eventvwr.msc'
  'disk management' = 'diskmgmt.msc'; 'system information' = 'msinfo32.exe'; 'resource monitor' = 'resmon.exe'
  'remote desktop' = 'mstsc.exe'; 'character map' = 'charmap.exe'; 'magnifier' = 'magnify.exe'; 'on-screen keyboard' = 'osk.exe'
  'wordpad' = 'write.exe'; 'snip' = 'ms-screenclip:'; 'clock' = 'ms-clock:'; 'alarms' = 'ms-clock:'; 'store' = 'ms-windows-store:'
  'microsoft store' = 'ms-windows-store:'; 'mail' = 'outlookmail:'; 'calendar' = 'outlookcal:'; 'camera' = 'microsoft.windows.camera:'
}
$AppAliases = @{
  'vs code' = 'visual studio code'; 'vscode' = 'visual studio code'; 'code' = 'visual studio code'; 'ppt' = 'powerpoint'
  'cmd' = 'command prompt'; 'calc' = 'calculator'; 'chrome' = 'google chrome'; 'edge' = 'microsoft edge'; 'store' = 'microsoft store'
  'intellij' = 'intellij idea'; 'vs' = 'visual studio'; 'word' = 'word'; 'teams' = 'teams'; 'onenote' = 'onenote'
}
function Get-AppList {
  if ($null -ne $BRAIN.apps) { return $BRAIN.apps }
  $list = New-Object System.Collections.ArrayList
  try {
    foreach ($sa in @(Get-StartApps -ErrorAction Stop)) {
      if ($null -ne $sa -and $sa.Name -and $sa.AppID) { $null = $list.Add(@{ name = [string]$sa.Name; id = [string]$sa.AppID; kind = 'start' }) }
    }
  } catch { }
  if ($list.Count -eq 0) {
    foreach ($dir in @((Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs'), (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'))) {
      if (-not (Test-Path -LiteralPath $dir)) { continue }
      foreach ($lk in @(Get-ChildItem -LiteralPath $dir -Recurse -Include '*.lnk', '*.url' -ErrorAction SilentlyContinue)) {
        $null = $list.Add(@{ name = [string]$lk.BaseName; id = [string]$lk.FullName; kind = 'file' })
      }
    }
  }
  $BRAIN.apps = $list
  return $list
}
function Find-App($query, $minScore) {
  if ($null -eq $minScore -or [double]$minScore -le 0) { $minScore = 59 }
  $q = ([string]$query).ToLower().Trim() -replace '\s+(app|application|program)$', ''
  if ($AppAliases.ContainsKey($q)) { $q = $AppAliases[$q] }
  if ($q.Length -lt 2) { return $null }
  $qWords = @($q -split '\s+' | Where-Object { $_ -ne '' })
  $best = $null
  $bestScore = 0.0
  foreach ($ap in @(Get-AppList)) {
    if ($null -eq $ap) { continue }
    $nm = ([string]$ap.name).ToLower()
    if ($nm -match '(uninstall|readme|read me|help|documentation|release notes|website|license)' -and $q -notmatch '(uninstall|readme|help|license)') { continue }
    $score = 0.0
    if ($nm -eq $q) { $score = 100 }
    elseif ($nm.StartsWith($q + ' ') -or $nm.StartsWith($q + ' (')) { $score = 90 }
    elseif ((' ' + $nm + ' ').Contains(' ' + $q + ' ')) { $score = 80 }
    elseif ($nm.StartsWith($q)) { $score = 72 }
    else {
      $nmWords = @($nm -split '[\s\-\(\)]+' | Where-Object { $_ -ne '' })
      if ((Get-MatchScore $nmWords $qWords) -ge 1) { $score = 70 }
      elseif ($q.Length -ge 4 -and $nm.Contains($q)) { $score = 60 }
    }
    if ($score -gt 0) { $score -= ($nm.Length / 100.0) }
    if ($score -gt $bestScore) { $bestScore = $score; $best = $ap }
  }
  if ($bestScore -ge [double]$minScore) { return $best }
  return $null
}
function Start-AppEntry($ap) {
  if ($ap.kind -eq 'start') { Start-Process 'explorer.exe' ('"shell:AppsFolder\' + $ap.id + '"') } else { Start-Process $ap.id }
}
function Open-Target($target, $depth, $minAppScore) {
  # returns a reply, or $null if I do not know what this is
  $x = ([string]$target).Trim().Trim('"')
  $lx = $x.ToLower()
  if ($lx -eq '') { return $null }
  if ($lx -match '^#?(\d{1,2})$') {
    $num = [int]$Matches[1]
    if ($num -ge 1 -and $num -le $BRAIN.results.Count) { return (Open-Result $num) }
  }
  if ($lx -match '^https?://\S+$') { Open-Web $x; return (New-Reply ('Opening ' + $x) $null) }
  if ($lx -match '^www\.\S+$' -or $lx -match '^[a-z0-9\-]+(\.[a-z0-9\-]+)*\.(com|org|net|io|dev|ai|in|co|uk|edu|gov|app|me|info)(/\S*)?$') {
    Open-Web ('https://' + $x); return (New-Reply ('Opening https://' + $x) $null)
  }
  if ($BRAIN.shortcuts.ContainsKey($lx)) {
    $dest = [string]$BRAIN.shortcuts[$lx]
    if ($dest -match '^https?://') { Open-Web $dest; return (New-Reply ('Opening your shortcut ' + $lx + ': ' + $dest) $null) }
    if (Test-Path -LiteralPath $dest) { Start-Process $dest; return (New-Reply ('Opening your shortcut ' + $lx + ': ' + $dest) $null) }
    if ($depth -lt 2) { $sub = Open-Target $dest ($depth + 1) 59; if ($null -ne $sub) { return $sub } }
    return (New-Reply ('Your shortcut "' + $lx + '" points to "' + $dest + '", but I cannot find that any more.') $null)
  }
  $fx = $lx -replace '\s+folder$', ''
  if ($KnownFolders.ContainsKey($fx) -and $KnownFolders[$fx]) {
    $fp = [string]$KnownFolders[$fx]
    if ($fp.StartsWith('shell:') -or (Test-Path -LiteralPath $fp)) { Start-Process 'explorer.exe' ('"' + $fp + '"'); return (New-Reply ('Opening ' + $fx + '...') $null) }
  }
  $sx = $lx -replace '\s+settings?$', ''
  if ($lx -match 'settings?$' -and $SettingsPages.ContainsKey($sx)) { Start-Process ('ms-settings:' + $SettingsPages[$sx]); return (New-Reply ('Opening ' + $sx + ' settings...') $null) }
  if ($AdminTools.ContainsKey($lx)) {
    try { Start-Process $AdminTools[$lx]; return (New-Reply ('Opening ' + $lx + '...') $null) } catch { }
  }
  $first = Open-App $lx
  if ($first.StartsWith('Opening')) { return (New-Reply $first $null) }
  $ap = Find-App $lx $minAppScore
  if ($null -ne $ap) {
    try { Start-AppEntry $ap; return (New-Reply ('Opening ' + $ap.name + '...') $null) } catch { Write-Log $_ }
  }
  if ($first.StartsWith('Sorry')) { return (New-Reply $first $null) }
  $nf = Get-NamedFolder $x
  if ($nf -and (Test-Path -LiteralPath $nf)) { Start-Process 'explorer.exe' ('"' + $nf + '"'); return (New-Reply ('Opening ' + $nf) $null) }
  if ($x -match '^[a-zA-Z]:\\' -or $x.StartsWith('\\')) {
    if (Test-Path -LiteralPath $x) { Start-Process $x; return (New-Reply ('Opening ' + $x) $null) }
    return (New-Reply ('I cannot find ' + $x) $null)
  }
  if ($SettingsPages.ContainsKey($lx)) { Start-Process ('ms-settings:' + $SettingsPages[$lx]); return (New-Reply ('Opening ' + $lx + ' settings...') $null) }
  return $null
}

# ---------- background jobs (file search etc.) so the dog never freezes ----------
$JOB = @{ ps = $null; handle = $null; kind = ''; info = $null; started = [datetime]::MinValue; timer = $null; bubble = $null; label = $null; text = ''
  stopped = (New-Object System.Collections.ArrayList) }
function Start-BgJob($kind, $scriptText, $argList, $info, $label) {
  if ($null -ne $JOB.ps) { return $false }
  foreach ($old in @($JOB.stopped)) {
    try { if ([string]$old.InvocationStateInfo.State -notmatch '^(Running|Stopping)$') { $old.Dispose(); $JOB.stopped.Remove($old) } } catch { }
  }
  $pw = [powershell]::Create()
  $null = $pw.AddScript($scriptText)
  foreach ($ar in $argList) { $null = $pw.AddArgument($ar) }
  $hd = $null
  try { $hd = $pw.BeginInvoke() } catch { Write-Log $_; try { $pw.Dispose() } catch { }; return $false }
  $JOB.ps = $pw
  $JOB.handle = $hd
  $JOB.kind = $kind
  $JOB.info = $info
  $JOB.text = [string]$label
  $JOB.started = [datetime]::Now
  Show-Working
  $JOB.timer.Start()
  return $true
}
function Stop-BgJob {
  $JOB.timer.Stop()
  try {
    if ($null -ne $JOB.ps) {
      if ($null -ne $JOB.handle -and -not $JOB.handle.IsCompleted) { $null = $JOB.ps.BeginStop($null, $null); $null = $JOB.stopped.Add($JOB.ps) } else { $JOB.ps.Dispose() }
    }
  } catch { }
  $JOB.ps = $null
  $JOB.handle = $null
  Remove-Working
}
function Check-BgJob {
  if ($null -eq $JOB.ps) { $JOB.timer.Stop(); return }
  Update-Working
  if (-not $JOB.handle.IsCompleted) {
    if (([datetime]::Now - $JOB.started).TotalSeconds -gt 120) {
      Stop-BgJob
      Agent-Say ('That was taking too long, so I stopped. Try a smaller folder, for example:  find report in downloads') $null
    }
    return
  }
  $out = @()
  $errText = ''
  try { $out = @($JOB.ps.EndInvoke($JOB.handle)) } catch { $errText = $_.Exception.Message }
  $kind = $JOB.kind
  $info = $JOB.info
  Stop-BgJob
  $rep = $null
  try { $rep = Finish-BgJob $kind $info $out $errText } catch { Write-Log $_; $rep = New-Reply ('Oops, something went wrong: ' + $_.Exception.Message) $null }
  if ($rep -is [array]) { $rep = @($rep | Where-Object { $_ -is [hashtable] }) | Select-Object -Last 1 }
  if ($null -ne $rep) { Agent-Say $rep.text $rep.web }
}
$JOB.timer = New-Object System.Windows.Threading.DispatcherTimer
$JOB.timer.Interval = [TimeSpan]::FromMilliseconds(250)
$JOB.timer.Add_Tick({ try { Check-BgJob } catch { Write-Log $_; Stop-BgJob } })

function Show-Working {
  if ($null -ne $UI.chatList) {
    $bd = New-Object System.Windows.Controls.Border
    $bd.CornerRadius = New-Object System.Windows.CornerRadius(12)
    $bd.Padding = New-Thick 12 8 12 8
    $bd.Margin = New-Thick 0 4 40 4
    $bd.HorizontalAlignment = 'Left'
    $bd.Background = New-Brush '#2C2C36'
    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.Foreground = New-Brush '#B8B8C8'
    $tb.FontStyle = 'Italic'
    $tb.TextWrapping = 'Wrap'
    $tb.Text = $JOB.text
    $bd.Child = $tb
    $null = $UI.chatList.Children.Add($bd)
    $UI.chatScroll.ScrollToEnd()
    $JOB.bubble = $bd
    $JOB.label = $tb
  }
  if (-not $PET.pending) { Say ('Sniff sniff... working on it ' + $EM.paw) 0 }
  Set-State 'sit' 30
}
function Update-Working {
  $secs = ([datetime]::Now - $JOB.started).TotalSeconds
  if ($null -ne $JOB.label) {
    $dots = '.' * (1 + ([int]($secs * 2.5) % 3))
    $JOB.label.Text = $JOB.text + $dots + '  (' + [int]$secs + 's - type  stop  to cancel)'
  }
  if (-not $PET.action -and (Get-Random -Minimum 0 -Maximum 100) -lt 4) { Do-Action 'wag' 1.0 }
}
function Remove-Working {
  if ($null -ne $JOB.bubble -and $null -ne $UI.chatList) { $UI.chatList.Children.Remove($JOB.bubble) }
  $JOB.bubble = $null
  $JOB.label = $null
  if (-not $PET.pending) { Hide-Bubble }
}
function Agent-Say($text, $web) {
  $BRAIN.lastReply = [string]$text
  Add-ChatMessage 'dog' $text $web
  if (-not $PET.action -and $PET.state -ne 'held') { Do-Action 'talk' 1.6 }
  if (-not $PET.pending) { Say (Short-Text $text 120) 8 }
  Speak-Text $text $false
  Update-ChatStatus
}
function Busy-Reply { return (New-Reply ('I am still busy with the last job (' + $JOB.text + '). Wait a moment, or type  stop  to cancel it.') $null) }

# the jobs themselves (they run in the background)
$FindScript = @'
param($roots, $pattern, $maxCount)
$found = New-Object System.Collections.ArrayList
$seen = @{}
foreach ($root in $roots) {
  if ($found.Count -ge $maxCount) { break }
  if (-not (Test-Path -LiteralPath $root)) { continue }
  Get-ChildItem -LiteralPath $root -Filter $pattern -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '\\(node_modules|\.git|\$Recycle\.Bin|AppData)\\' } |
    Select-Object -First ($maxCount - $found.Count) |
    ForEach-Object {
      if (-not $seen.ContainsKey($_.FullName)) {
        $seen[$_.FullName] = $true
        $len = 0
        if (-not $_.PSIsContainer) { $len = $_.Length }
        $null = $found.Add([pscustomobject]@{ path = $_.FullName; name = $_.Name; folder = [bool]$_.PSIsContainer; size = $len; time = $_.LastWriteTime })
      }
    }
}
$found
'@
$BigScript = @'
param($roots, $topN)
$all = foreach ($root in $roots) { if (Test-Path -LiteralPath $root) { Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue } }
$all | Sort-Object -Property Length -Descending | Select-Object -First $topN | ForEach-Object {
  [pscustomobject]@{ path = $_.FullName; name = $_.Name; folder = $false; size = $_.Length; time = $_.LastWriteTime }
}
'@
$DlScript = @'
param($root)
$now = Get-Date
$top = @(Get-ChildItem -LiteralPath $root -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'desktop.ini' })
$sum = Get-ChildItem -LiteralPath $root -File -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum
$dirs = @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue).Count
$items = foreach ($fi in $top) {
  [pscustomobject]@{ path = $fi.FullName; name = $fi.Name; ext = $fi.Extension.ToLower(); size = $fi.Length; time = $fi.LastWriteTime; days = [int]($now - $fi.LastWriteTime).TotalDays; folder = $false }
}
[pscustomobject]@{ totalSize = [double]$sum.Sum; totalCount = [int]$sum.Count; dirs = $dirs; files = @($items) }
'@
$OrgScript = @'
param($root, $map)
$moved = 0
$failed = 0
$used = @{}
foreach ($fi in @(Get-ChildItem -LiteralPath $root -File -ErrorAction SilentlyContinue)) {
  if ($fi.Name -eq 'desktop.ini' -or $fi.Name -match '\.(crdownload|part|partial|tmp|download)$') { continue }
  $sub = 'Other'
  $ext = $fi.Extension.ToLower()
  if ($map.ContainsKey($ext)) { $sub = $map[$ext] }
  try {
    $destDir = Join-Path $root $sub
    if (-not (Test-Path -LiteralPath $destDir)) { $null = New-Item -ItemType Directory -Path $destDir }
    $dest = Join-Path $destDir $fi.Name
    $n = 1
    while (Test-Path -LiteralPath $dest) { $dest = Join-Path $destDir ($fi.BaseName + ' (' + $n + ')' + $fi.Extension); $n++ }
    Move-Item -LiteralPath $fi.FullName -Destination $dest -ErrorAction Stop
    $moved++
    $used[$sub] = $true
  } catch { $failed++ }
}
[pscustomobject]@{ moved = $moved; failed = $failed; folders = (@($used.Keys) -join ', ') }
'@
$TempScript = @'
param($root, $days)
$cut = (Get-Date).AddDays(-$days)
$n = 0
$bytes = 0.0
Get-ChildItem -LiteralPath $root -File -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $cut } | ForEach-Object {
  try { $len = $_.Length; Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop; $n++; $bytes += $len } catch { }
}
[pscustomobject]@{ count = $n; size = $bytes }
'@

$PartCheck['5'] = $true   # ===== end of PART 5 of 9 =====
# ---------- files ----------
$FileCats = [ordered]@{
  'Images'     = '.jpg .jpeg .png .gif .bmp .webp .svg .heic .ico .tif .tiff'
  'Documents'  = '.pdf .doc .docx .txt .rtf .odt .xls .xlsx .csv .ppt .pptx .md .one .xps .epub'
  'Archives'   = '.zip .rar .7z .tar .gz .tgz .bz2 .iso'
  'Installers' = '.exe .msi .msix .appx .appxbundle .msixbundle'
  'Videos'     = '.mp4 .mkv .avi .mov .wmv .webm'
  'Music'      = '.mp3 .wav .flac .m4a .aac .ogg .wma'
  'Code'       = '.ps1 .bat .cmd .py .js .ts .json .xml .html .css .java .cs .cpp .c .h .sql .sh .ipynb .yaml .yml'
}
$ExtMap = @{}
foreach ($cat in $FileCats.Keys) { foreach ($ex in ($FileCats[$cat] -split ' ')) { $ExtMap[$ex] = $cat } }
$FindExts = @('pdf', 'docx', 'xlsx', 'xls', 'pptx', 'ppt', 'txt', 'csv', 'png', 'jpg', 'jpeg', 'gif', 'zip', 'rar', '7z', 'exe', 'msi',
  'py', 'js', 'ts', 'java', 'cs', 'cpp', 'ps1', 'json', 'xml', 'html', 'css', 'md', 'mp4', 'mp3', 'wav', 'mov', 'sql', 'log', 'ipynb', 'yaml', 'yml')
$ExtWords = @{ 'word' = 'docx'; 'excel' = 'xlsx'; 'spreadsheet' = 'xlsx'; 'powerpoint' = 'pptx'; 'presentation' = 'pptx'; 'slides' = 'pptx'; 'pdfs' = 'pdf' }
function Get-SearchRoots {
  $roots = New-Object System.Collections.ArrayList
  $cands = @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('MyDocuments'), (Get-DownloadsPath),
    [Environment]::GetFolderPath('MyPictures'), [Environment]::GetFolderPath('MyVideos'), [Environment]::GetFolderPath('MyMusic'),
    $env:OneDriveCommercial, $env:OneDrive, (Join-Path $env:USERPROFILE 'source'), (Join-Path $env:USERPROFILE 'repos'),
    (Join-Path $env:USERPROFILE 'projects'), (Join-Path $env:USERPROFILE 'workplace'))
  foreach ($p in $cands) {
    if (-not [string]::IsNullOrWhiteSpace($p) -and (Test-Path -LiteralPath $p) -and -not $roots.Contains($p)) { $null = $roots.Add($p) }
  }
  return $roots
}
function Build-FindPattern($query) {
  $q = ([string]$query).Trim().Trim('"', "'")
  $ext = ''
  $keep = @()
  foreach ($wd in @($q -split '\s+' | Where-Object { $_ -ne '' })) {
    $lw = $wd.ToLower()
    $bare = $lw -replace '^\*?\.', ''
    if ($FindExts -contains $bare -and $lw -notmatch '\w\.\w') { if ($ext -eq '') { $ext = $bare }; continue }
    if ($ExtWords.ContainsKey($lw)) { if ($ext -eq '') { $ext = $ExtWords[$lw] }; continue }
    if (@('file', 'files', 'folder', 'folders', 'document', 'documents', 'called', 'named', 'my', 'the', 'a', 'an', 'all', 'some', 'any', 'of', 'with', 'about', 'that', 'is', 'are', 'for', 'everything', 'something') -contains $lw) { continue }
    $keep += $wd
  }
  $nameText = ($keep -join '*')
  if ($nameText -eq '' -and $ext -eq '') { return '' }
  if ($ext -ne '') { return (('*' + $nameText + '*.' + $ext) -replace '\*\*+', '*') }
  return ('*' + $nameText + '*')
}
function Start-Find($query, $where) {
  $pat = Build-FindPattern $query
  if ($pat -eq '' -and $null -ne $where) { $pat = '*' }
  if ($pat -eq '') { return (New-Reply 'What should I look for? Examples:  find resume  |  find tax pdf  |  find report in downloads' $null) }
  if ($null -ne $where) { $roots = @($where) } else { $roots = @(Get-SearchRoots) }
  $label = $cfg.dogName + ' is sniffing through your files for ' + $pat
  $ok = Start-BgJob 'find' $FindScript @($roots, $pat, 300) @{ pattern = $pat; roots = $roots } $label
  if (-not $ok) { return (Busy-Reply) }
  $whereText = 'your main folders (Desktop, Documents, Downloads, Pictures...)'
  if ($null -ne $where) { $whereText = [string]$where }
  return (New-Reply ('Okay! Looking for "' + $pat + '" in ' + $whereText + ' ' + $EM.paw) $null)
}
function Show-Files($items, $header, $footer) {
  $BRAIN.results.Clear()
  $lines = @($header)
  $num = 0
  foreach ($it in @($items)) {
    if ($null -eq $it) { continue }
    $num++
    if ($num -gt 15) { break }
    $null = $BRAIN.results.Add([string]$it.path)
    $extra = Format-When $it.time
    $kind = ''
    if ($it.folder) { $kind = '  [folder]' } else { $extra = (Format-Size $it.size) + ', ' + $extra }
    $parent = Split-Path -Parent ([string]$it.path)
    $lines += ([string]$num + '. ' + $it.name + $kind + '   (' + $extra + ')' + "`n" + '     in ' + (Short-Path $parent))
  }
  if ($num -gt 0) {
    if ($footer) { $lines += ('' + "`n" + $footer) }
    else { $lines += ("`n" + 'Type  open 1  to open one, or  folder 1  to see it in File Explorer.') }
  }
  return ($lines -join "`n")
}
function Open-Result($num) {
  if ($num -lt 1 -or $num -gt $BRAIN.results.Count) { return (New-Reply ('I only have ' + $BRAIN.results.Count + ' results right now.') $null) }
  $p = [string]$BRAIN.results[$num - 1]
  if (-not (Test-Path -LiteralPath $p)) { return (New-Reply ('That one is gone now: ' + $p) $null) }
  try { Start-Process -FilePath $p; return (New-Reply ('Opening ' + (Split-Path -Leaf $p) + '...') $null) }
  catch { return (New-Reply ('Windows could not open it: ' + $_.Exception.Message) $null) }
}
function Folder-Result($num) {
  if ($num -lt 1 -or $num -gt $BRAIN.results.Count) { return (New-Reply ('I only have ' + $BRAIN.results.Count + ' results right now.') $null) }
  $p = [string]$BRAIN.results[$num - 1]
  Start-Process 'explorer.exe' ('/select,"' + $p + '"')
  return (New-Reply ('Showing it in File Explorer: ' + $p) $null)
}
function Get-DownloadsReport($r) {
  $files = @($r.files)
  $cats = [ordered]@{}
  $oldCount = 0; $oldSize = 0.0; $instCount = 0; $instSize = 0.0
  foreach ($fi in $files) {
    if ($null -eq $fi) { continue }
    $cat = 'Other'
    if ($ExtMap.ContainsKey([string]$fi.ext)) { $cat = $ExtMap[[string]$fi.ext] }
    if (-not $cats.Contains($cat)) { $cats[$cat] = @{ n = 0; s = 0.0 } }
    $cats[$cat].n++
    $cats[$cat].s += [double]$fi.size
    if ($fi.days -gt 30) {
      $oldCount++; $oldSize += [double]$fi.size
      if ($cat -eq 'Installers') { $instCount++; $instSize += [double]$fi.size }
    }
  }
  $lines = @('Your Downloads folder: ' + $r.totalCount + ' files, ' + (Format-Size $r.totalSize) + ' in total.')
  $lines += ('Loose files on top: ' + $files.Count + '   |   sub-folders: ' + $r.dirs)
  if ($cats.Count -gt 0) {
    $byType = @()
    foreach ($ck in $cats.Keys) { $byType += ($ck + ' ' + $cats[$ck].n + ' (' + (Format-Size $cats[$ck].s) + ')') }
    $lines += ('By type: ' + ($byType -join ', '))
  }
  $lines += ('Older than 30 days: ' + $oldCount + ' files (' + (Format-Size $oldSize) + ')')
  if ($instCount -gt 0) { $lines += ('Old installers (.exe/.msi, 30+ days): ' + $instCount + ' (' + (Format-Size $instSize) + ') - usually safe to remove once the app is installed.') }
  $lines += ''
  $lines += 'What I can do next:'
  $lines += '  organize downloads   - sort the loose files into folders (Images, Documents, Installers...)'
  $lines += '  show old downloads   - list the old files so you can check them'
  if ($instCount -gt 0) { $lines += '  delete old installers  - move them to the Recycle Bin (you can restore them)' }
  return ($lines -join "`n")
}
function Get-OldInstallers {
  $root = Get-DownloadsPath
  $cut = [datetime]::Now.AddDays(-30)
  return @(Get-ChildItem -LiteralPath $root -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $cut -and $ExtMap[$_.Extension.ToLower()] -eq 'Installers' })
}
function Finish-BgJob($kind, $info, $out, $errText) {
  if ($errText) { return (New-Reply ('Sorry, that did not work: ' + $errText) $null) }
  switch ($kind) {
    'find' {
      $items = @($out | Where-Object { $null -ne $_ } | Sort-Object -Property time -Descending)
      if ($items.Count -eq 0) {
        return (New-Reply ('I could not find anything matching "' + $info.pattern + '" ' + $EM.think + "`n" + 'Tips: use fewer words (find resume), add a type (find tax pdf), or pick a place (find report in D:\).') $null)
      }
      $more = ''
      if ($items.Count -gt 15) { $more = ' (showing the newest 15 of ' + $items.Count + ')' }
      return (New-Reply (Show-Files $items ('Found it! ' + $EM.paw + ' Matches for "' + $info.pattern + '"' + $more + ':') $null) $null)
    }
    'big' {
      $items = @($out | Where-Object { $null -ne $_ })
      if ($items.Count -eq 0) { return (New-Reply 'I did not find any files there.' $null) }
      return (New-Reply (Show-Files $items ('The biggest files in ' + $info.where + ':') 'Type  open 1  to open one, or  folder 1  to see it in File Explorer. I never delete files on my own.') $null)
    }
    'dl' {
      $r = @($out)[0]
      if ($null -eq $r) { return (New-Reply 'I could not read your Downloads folder.' $null) }
      $BRAIN.dl = $r
      return (New-Reply (Get-DownloadsReport $r) $null)
    }
    'organize' {
      $r = @($out)[0]
      $txt = 'Done! I moved ' + $r.moved + ' files into folders: ' + $r.folders + ' ' + $EM.star
      if ($r.failed -gt 0) { $txt += "`n" + $r.failed + ' files were in use or locked, so I left them where they were.' }
      return (New-Reply $txt $null)
    }
    'temp' {
      $r = @($out)[0]
      return (New-Reply ('Cleaned up ' + $r.count + ' old temporary files and freed ' + (Format-Size $r.size) + '. Files that were in use were skipped. ' + $EM.star) $null)
    }
  }
  return $null
}

# ---------- PC information ----------
function Get-BatteryText {
  $pwr = [System.Windows.Forms.SystemInformation]::PowerStatus
  if ([int]$pwr.BatteryChargeStatus -eq 128) { return 'This PC has no battery (it runs on mains power).' }
  $pct = [int]([double]$pwr.BatteryLifePercent * 100)
  $txt = 'Battery: ' + $pct + '%'
  if ([string]$pwr.PowerLineStatus -eq 'Online') { $txt += ' - plugged in' + $(if ($pct -lt 100) { ', charging' } else { '' }) }
  else {
    $txt += ' - on battery'
    if ([int]$pwr.BatteryLifeRemaining -gt 0) { $ts = [TimeSpan]::FromSeconds([int]$pwr.BatteryLifeRemaining); $txt += ', about ' + [int]$ts.TotalHours + 'h ' + $ts.Minutes + 'm left' }
    if ($pct -le 20) { $txt += '. Please plug in the charger soon!' }
  }
  return $txt
}
function Get-DiskText {
  $lines = @()
  foreach ($dv in [System.IO.DriveInfo]::GetDrives()) {
    try {
      if (-not $dv.IsReady -or [string]$dv.DriveType -ne 'Fixed') { continue }
      $free = [double]$dv.AvailableFreeSpace
      $total = [double]$dv.TotalSize
      $usedPct = [int](100 - ($free / $total * 100))
      $ln = $dv.Name.TrimEnd('\') + '  ' + (Format-Size $free) + ' free of ' + (Format-Size $total) + '  (' + $usedPct + '% used)'
      if ($free / $total -lt 0.1) { $ln += '  - almost full! Try:  check my downloads  or  clean temp files' }
      $lines += $ln
    } catch { }
  }
  if ($lines.Count -eq 0) { return 'I could not read your drives.' }
  return ('Disk space:' + "`n" + ($lines -join "`n"))
}
function Get-OsInfo { try { return (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop) } catch { return $null } }
function Get-MemoryText {
  $os = Get-OsInfo
  if ($null -eq $os) { return 'I could not read the memory info.' }
  $total = [double]$os.TotalVisibleMemorySize * 1KB
  $free = [double]$os.FreePhysicalMemory * 1KB
  $usedPct = [int](100 - ($free / $total * 100))
  $txt = 'Memory (RAM): ' + (Format-Size ($total - $free)) + ' used of ' + (Format-Size $total) + ' (' + $usedPct + '%)'
  if ($usedPct -ge 85) { $txt += '. That is high - type  what is using my memory  to see which apps.' }
  return $txt
}
function Get-CpuText {
  try {
    $cpus = @(Get-CimInstance Win32_Processor -ErrorAction Stop)
    $load = ($cpus | Measure-Object -Property LoadPercentage -Average).Average
    $cores = ($cpus | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum
    $txt = 'CPU: ' + ([string]$cpus[0].Name).Trim() + "`n" + 'Busy right now: ' + [int]$load + '%   (' + $cores + ' logical cores)'
    if ($load -ge 85) { $txt += '. Your PC is working hard - type  what is using my memory  to see the busiest apps.' }
    return $txt
  } catch { return 'I could not read the CPU info.' }
}
function Get-TopAppsText {
  $groups = @(Get-Process -ErrorAction SilentlyContinue | Group-Object -Property ProcessName | ForEach-Object {
    [pscustomobject]@{ name = $_.Name; mem = [double](($_.Group | Measure-Object -Property WorkingSet64 -Sum).Sum); count = $_.Count }
  } | Sort-Object -Property mem -Descending | Select-Object -First 8)
  $lines = @('Apps using the most memory right now:')
  $num = 0
  foreach ($gp in $groups) { $num++; $extra = ''; if ($gp.count -gt 1) { $extra = '  (' + $gp.count + ' windows/processes)' }; $lines += ([string]$num + '. ' + $gp.name + ' - ' + (Format-Size $gp.mem) + $extra) }
  $lines += ''
  $lines += 'To close one, type for example:  close chrome   (I close it politely, like clicking X, so you can save your work).'
  return ($lines -join "`n")
}
function Get-UptimeText {
  $os = Get-OsInfo
  if ($null -eq $os) { return 'I could not read the start time.' }
  $up = [datetime]::Now - [datetime]$os.LastBootUpTime
  $txt = 'Your PC has been on for ' + [int]$up.TotalDays + ' days, ' + $up.Hours + ' hours and ' + $up.Minutes + ' minutes (since ' + ([datetime]$os.LastBootUpTime).ToString('ddd d MMM, h:mm tt') + ').'
  if ($up.TotalDays -ge 7) { $txt += ' A restart now and then keeps Windows fast and installs updates.' }
  return $txt
}
function Get-IpText {
  $lines = @()
  try {
    foreach ($ni in [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
      if ([string]$ni.OperationalStatus -ne 'Up' -or [string]$ni.NetworkInterfaceType -eq 'Loopback') { continue }
      foreach ($ua in $ni.GetIPProperties().UnicastAddresses) {
        if ([string]$ua.Address.AddressFamily -eq 'InterNetwork') { $lines += ($ni.Name + ':  ' + $ua.Address.ToString()) }
      }
    }
  } catch { }
  if ($lines.Count -eq 0) { return 'You do not seem to be connected to any network right now.' }
  return ('Your local IP address:' + "`n" + ($lines -join "`n"))
}
function Get-WifiText {
  $online = [System.Net.NetworkInformation.NetworkInterface]::GetIsNetworkAvailable()
  $ssid = ''
  try {
    foreach ($ln in @(& netsh.exe wlan show interfaces 2>$null)) { if ([string]$ln -match '^\s*SSID\s*:\s*(.+)$') { $ssid = $Matches[1].Trim(); break } }
  } catch { }
  if (-not $online) { return 'You are not connected to any network. Type  wifi settings  to connect.' }
  if ($ssid) { return ('You are connected to Wi-Fi: ' + $ssid + '. (If websites do not load, try  wifi settings  or restart the router.)') }
  return 'You are connected to a network (cable or VPN). Type  ip address  for details.'
}
function Get-PcNameText {
  $os = Get-OsInfo
  $txt = 'PC name: ' + $env:COMPUTERNAME + "`n" + 'Signed in as: ' + $env:USERNAME
  if ($null -ne $os) { $txt += "`n" + 'Windows: ' + $os.Caption + ' (version ' + $os.Version + ')' }
  return $txt
}
function Get-RunningAppsText {
  $procs = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -and $_.Id -ne $PID } | Sort-Object -Property ProcessName)
  if ($procs.Count -eq 0) { return 'I do not see any open windows.' }
  $lines = @('Open windows right now:')
  foreach ($pr in $procs) { $lines += ('- ' + $pr.ProcessName + ':  ' + (Short-Text $pr.MainWindowTitle 60)) }
  $lines += ''
  $lines += 'Type  close <name>  to close one, for example:  close notepad'
  return ($lines -join "`n")
}
$ProcAliases = @{
  'chrome' = 'chrome'; 'google chrome' = 'chrome'; 'edge' = 'msedge'; 'microsoft edge' = 'msedge'; 'word' = 'winword'; 'excel' = 'excel'
  'powerpoint' = 'powerpnt'; 'ppt' = 'powerpnt'; 'outlook' = 'outlook,olk'; 'teams' = 'ms-teams,teams'; 'vs code' = 'code'; 'vscode' = 'code'
  'visual studio code' = 'code'; 'code' = 'code'; 'notepad' = 'notepad'; 'calculator' = 'calculatorapp,calc'; 'calc' = 'calculatorapp,calc'
  'paint' = 'mspaint'; 'firefox' = 'firefox'; 'spotify' = 'spotify'; 'slack' = 'slack'; 'zoom' = 'zoom'; 'task manager' = 'taskmgr'
  'cmd' = 'cmd'; 'command prompt' = 'cmd'; 'terminal' = 'windowsterminal'; 'snipping tool' = 'snippingtool'; 'onenote' = 'onenote'
}
$ProtectedProcs = @('explorer', 'svchost', 'csrss', 'winlogon', 'lsass', 'dwm', 'system', 'smss', 'services', 'wininit', 'powershell', 'pwsh', 'conhost', 'idle')
function Close-AppByName($name) {
  $key = ([string]$name).ToLower().Trim()
  $names = @()
  if ($ProcAliases.ContainsKey($key)) { $names = @($ProcAliases[$key] -split ',') } else { $names = @($key -replace '\s+', '' -replace '\.exe$', '') }
  $procs = @(Get-Process -Name $names -ErrorAction SilentlyContinue)
  if ($procs.Count -eq 0 -and $key.Length -ge 4 -and $key -notmatch '^(all|windows|everything|apps|programs|it|this|that|them|tabs?)$') {
    $procs = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -like ('*' + $key + '*') })
  }
  $procs = @($procs | Where-Object { $_.Id -ne $PID -and $ProtectedProcs -notcontains $_.ProcessName.ToLower() })
  if ($procs.Count -eq 0) { return $null }
  $closed = 0
  foreach ($pr in $procs) { try { if ($pr.MainWindowHandle -ne 0) { if ($pr.CloseMainWindow()) { $closed++ } } } catch { } }
  if ($closed -eq 0) { return ($procs[0].ProcessName + ' is running in the background without a window, so I left it alone (I only close windows safely).') }
  return ('Closing ' + $procs[0].ProcessName + ' (' + $closed + ' window' + $(if ($closed -gt 1) { 's' } else { '' }) + '). If it asks to save, that is up to you!')
}
function Take-Screenshot {
  $dir = Join-Path ([Environment]::GetFolderPath('MyPictures')) 'DogPet Screenshots'
  if (-not (Test-Path $dir)) { $null = New-Item -ItemType Directory -Path $dir }
  $file = Join-Path $dir ('Screenshot ' + (Get-Date).ToString('yyyy-MM-dd HH.mm.ss') + '.png')
  $vs = [System.Windows.Forms.SystemInformation]::VirtualScreen
  $bmp = New-Object System.Drawing.Bitmap($vs.Width, $vs.Height)
  $gr = [System.Drawing.Graphics]::FromImage($bmp)
  $gr.CopyFromScreen($vs.Left, $vs.Top, 0, 0, $bmp.Size)
  $gr.Dispose()
  $bmp.Save($file, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
  $BRAIN.results.Clear()
  $null = $BRAIN.results.Add($file)
  return $file
}
function Send-MediaKey($code, $times) {
  $wsh = New-Object -ComObject WScript.Shell
  for ($k = 0; $k -lt $times; $k++) { $wsh.SendKeys([string][char]$code) }
}
function Minimize-AllWindows {
  (New-Object -ComObject Shell.Application).MinimizeAll()
  $back = New-Object System.Windows.Threading.DispatcherTimer
  $back.Interval = [TimeSpan]::FromMilliseconds(600)
  $back.Add_Tick({ param($sender, $ev) try { $sender.Stop(); $win.WindowState = 'Normal'; $win.Topmost = $true } catch { } })
  $back.Start()
}

# ---------- asking "are you sure?" before big actions ----------
function Ask-Confirm($question, $act, $arg) {
  $BRAIN.confirm = @{ act = $act; arg = $arg; until = [datetime]::Now.AddMinutes(3) }
  return (New-Reply ($question + "`n" + 'Type  yes  to go ahead, or  no  to cancel.') $null)
}
function Check-Confirm($low) {
  $cf = $BRAIN.confirm
  if ($null -eq $cf) { return $null }
  if ([datetime]::Now -gt $cf.until) { $BRAIN.confirm = $null; return $null }
  $x = ($low -replace '[\s\.!\?]+$', '').Trim()
  if ($x -match '^(yes|y|yeah|yep|yup|sure|ok|okay|do it|go ahead|go|confirm|yes please|please do)$') { $BRAIN.confirm = $null; return (Run-Confirmed $cf.act $cf.arg) }
  if ($x -match '^(no|n|nope|nah|cancel|stop|dont|don''t|no thanks|never mind|nevermind)$') { $BRAIN.confirm = $null; return (New-Reply 'Okay, I will not do it. *wags tail*' $null) }
  $BRAIN.confirm = $null
  return $null
}
function Run-Confirmed($act, $arg) {
  switch ($act) {
    'shutdown' { Start-Process 'shutdown.exe' '/s /t 60'; return (New-Reply 'Okay. Your PC will shut down in 60 seconds. Save your work! Type  cancel shutdown  to stop it.' $null) }
    'restart' { Start-Process 'shutdown.exe' '/r /t 60'; return (New-Reply 'Okay. Your PC will restart in 60 seconds. Save your work! Type  cancel restart  to stop it.' $null) }
    'recycle' {
      try { Clear-RecycleBin -Force -ErrorAction Stop; return (New-Reply ('The Recycle Bin is empty now. ' + $EM.star) $null) }
      catch { return (New-Reply ('The Recycle Bin was already empty, or Windows said no: ' + $_.Exception.Message) $null) }
    }
    'temp' {
      $ok = Start-BgJob 'temp' $TempScript @($env:TEMP, 3) @{} ($cfg.dogName + ' is cleaning old temporary files')
      if (-not $ok) { return (Busy-Reply) }
      return (New-Reply 'Cleaning up...' $null)
    }
    'organize' {
      $ok = Start-BgJob 'organize' $OrgScript @((Get-DownloadsPath), $ExtMap) @{} ($cfg.dogName + ' is tidying your Downloads folder')
      if (-not $ok) { return (Busy-Reply) }
      return (New-Reply 'Tidying up your Downloads folder...' $null)
    }
    'installers' {
      $n = 0; $size = 0.0
      foreach ($p in @($arg)) {
        try {
          $len = (Get-Item -LiteralPath $p).Length
          [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($p, [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs, [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin)
          $n++; $size += $len
        } catch { }
      }
      return (New-Reply ('Moved ' + $n + ' old installers (' + (Format-Size $size) + ') to the Recycle Bin. You can restore them from there if needed.') $null)
    }
    'forgetall' { $BRAIN.facts.Clear(); Save-Brain; return (New-Reply 'Done. I forgot everything you taught me. My notes, shortcuts and routines are still there.' $null) }
    'clearnotes' { $BRAIN.notes.Clear(); Save-Brain; return (New-Reply 'All notes deleted.' $null) }
    'quit' { Quit-App; return $null }
  }
  return $null
}

# ---------- nicer chat bubbles: tidy markdown, source links ----------
function Clean-Markdown($s) {
  $bullet = [string][char]0x2022
  $lines = (([string]$s) -replace "`r", '') -split "`n"
  $out = foreach ($ln in $lines) {
    $x = $ln -replace '^\s{0,3}#{1,6}\s*', ''
    $x = $x -replace '^(\s*)[\*\-]\s+', ('$1' + $bullet + ' ')
    $x = $x -replace '\*\*(.+?)\*\*', '$1'
    $x = $x -replace '__(.+?)__', '$1'
    $x = $x -replace '(?<![\*\w])\*(?!\s)(.+?)(?<!\s)\*(?![\*\w])', '$1'
    $x = $x -replace '`([^`]+)`', '$1'
    $x = $x -replace '\[([^\]]+)\]\((https?://[^\)\s]+)\)', '$1 ($2)'
    $x
  }
  return ($out -join "`n")
}
function Add-ChatMessage($who, $text, $webQuery) { Add-ChatMessageEx $who $text $webQuery $null }
function Add-ChatMessageEx($who, $text, $webQuery, $sources) {
  if ($null -eq $UI.chatList) { return }
  $isUser = ($who -eq 'user')
  $outer = New-Object System.Windows.Controls.Border
  $outer.CornerRadius = New-Object System.Windows.CornerRadius(12)
  $outer.Padding = New-Thick 10 6 10 8
  if ($isUser) {
    $outer.Margin = New-Thick 60 4 0 4; $outer.HorizontalAlignment = 'Right'; $outer.Background = New-Brush '#3D5AFE'
  } else {
    $outer.Margin = New-Thick 0 4 40 4; $outer.HorizontalAlignment = 'Left'; $outer.Background = New-Brush '#2C2C36'
  }
  $stack = New-Object System.Windows.Controls.StackPanel
  $hdr = New-Object System.Windows.Controls.TextBlock
  if ($isUser) { $hdr.Text = $cfg.userName } else { $hdr.Text = $cfg.dogName }
  $hdr.FontSize = 11
  $hdr.Foreground = New-Brush '#B8B8C8'
  $hdr.Margin = New-Thick 2 0 0 2
  $null = $stack.Children.Add($hdr)

  $parts = ([string]$text) -split '```'
  for ($i = 0; $i -lt $parts.Count; $i++) {
    $part = $parts[$i]
    if (($i % 2) -eq 1) {
      $lang = ''
      if ($part -match '^([a-zA-Z0-9#+\-]*)\r?
') { $lang = $Matches[1] }
      $code = ($part -replace '^[a-zA-Z0-9#+\-]*\r?
', '').TrimEnd()
      $box = New-Object System.Windows.Controls.Border
      $box.Background = New-Brush '#15151B'
      $box.CornerRadius = New-Object System.Windows.CornerRadius(6)
      $box.Padding = New-Thick 8 4 8 6
      $box.Margin = New-Thick 0 4 0 4
      $inner = New-Object System.Windows.Controls.StackPanel
      $bar = New-Object System.Windows.Controls.DockPanel
      $langText = New-Object System.Windows.Controls.TextBlock
      $langText.Text = $lang
      $langText.FontSize = 11
      $langText.Foreground = New-Brush '#8888A0'
      $btn = New-Object System.Windows.Controls.Button
      $btn.Content = 'Copy'
      $btn.Tag = $code
      $btn.FontSize = 11
      $btn.Padding = New-Thick 8 1 8 1
      $btn.Background = New-Brush '#3A3A46'
      $btn.Foreground = New-Brush '#FFFFFF'
      $btn.BorderThickness = New-Thick 0 0 0 0
      $btn.Cursor = [System.Windows.Input.Cursors]::Hand
      $btn.Add_Click({ param($sender, $ev) try { [System.Windows.Clipboard]::SetText([string]$sender.Tag); $sender.Content = 'Copied!' } catch { Write-Log $_ } })
      [System.Windows.Controls.DockPanel]::SetDock($btn, 'Right')
      $null = $bar.Children.Add($btn)
      $null = $bar.Children.Add($langText)
      $null = $inner.Children.Add($bar)
      $null = $inner.Children.Add((New-ReadOnlyText $code $true))
      $box.Child = $inner
      $null = $stack.Children.Add($box)
    } else {
      $clean = $part.Trim()
      if (-not $isUser) { $clean = (Clean-Markdown $clean).Trim() }
      if ($clean -ne '') { $null = $stack.Children.Add((New-ReadOnlyText $clean $false)) }
    }
  }
  if ($null -ne $sources -and @($sources).Count -gt 0) {
    $srcLabel = New-Object System.Windows.Controls.TextBlock
    $srcLabel.Text = 'Sources:'
    $srcLabel.FontSize = 11
    $srcLabel.Foreground = New-Brush '#8888A0'
    $srcLabel.Margin = New-Thick 2 6 0 2
    $null = $stack.Children.Add($srcLabel)
    $wrap = New-Object System.Windows.Controls.WrapPanel
    foreach ($src in @($sources)) {
      $title = [string]$src.title
      if ($title -eq '') { $title = 'link' }
      if ($title.Length -gt 40) { $title = $title.Substring(0, 40) + '...' }
      $sb2 = New-Object System.Windows.Controls.Button
      $sb2.Content = $title
      $sb2.Tag = [string]$src.uri
      $sb2.FontSize = 11
      $sb2.Margin = New-Thick 0 0 6 4
      $sb2.Padding = New-Thick 8 2 8 2
      $sb2.Background = New-Brush '#33334A'
      $sb2.Foreground = New-Brush '#9FB4FF'
      $sb2.BorderThickness = New-Thick 0 0 0 0
      $sb2.Cursor = [System.Windows.Input.Cursors]::Hand
      $sb2.Add_Click({ param($sender, $ev) Open-Web ([string]$sender.Tag) })
      $null = $wrap.Children.Add($sb2)
    }
    $null = $stack.Children.Add($wrap)
  }
  if ($webQuery) {
    $wb = New-Object System.Windows.Controls.Button
    $wb.Content = 'Search Google for this'
    $wb.Tag = [string]$webQuery
    $wb.Margin = New-Thick 0 6 0 0
    $wb.Padding = New-Thick 10 3 10 3
    $wb.HorizontalAlignment = 'Left'
    $wb.Background = New-Brush '#4A6CF7'
    $wb.Foreground = New-Brush '#FFFFFF'
    $wb.BorderThickness = New-Thick 0 0 0 0
    $wb.Cursor = [System.Windows.Input.Cursors]::Hand
    $wb.Add_Click({ param($sender, $ev) Open-Web ('https://www.google.com/search?q=' + [uri]::EscapeDataString([string]$sender.Tag)) })
    $null = $stack.Children.Add($wb)
  }
  $outer.Child = $stack
  $null = $UI.chatList.Children.Add($outer)
  $UI.chatScroll.ScrollToEnd()
}

$PartCheck['6'] = $true   # ===== end of PART 6 of 9 =====
# ---------- memory: things you teach me ----------
function Add-Fact($q, $a, $said) {
  $qq = ([string]$q).Trim().TrimEnd('?', '.', '!')
  $aa = ([string]$a).Trim()
  if ($qq -eq '' -or $aa -eq '') { return 'Tell me both parts, for example:  teach: standup time = 10:00 am every weekday' }
  if (($qq + ' ' + $aa) -match '(?i)(password|passcode|passwd|\bpin\b|secret|api key|token|credit card|cvv|otp)') {
    return 'For safety I do not remember passwords, PINs or secret keys - my memory is a plain file on this PC. Please keep those in a password manager.'
  }
  foreach ($fa in $BRAIN.facts) {
    if ([string]$fa.q -eq $qq) { $fa.a = $aa; $fa.said = [bool]$said; Save-Brain; return ('Updated! ' + $EM.paw + ' Now I know: ' + (Flip-Person $aa)) }
  }
  $null = $BRAIN.facts.Add(@{ q = $qq; a = $aa; said = [bool]$said })
  Save-Brain
  Do-Action 'happy' 1.5
  $example = 'what is ' + $qq
  if ($said) { $example = 'tell me about ' + (Flip-Person $qq) }
  return ('Got it! I will remember that ' + $EM.paw + "`n" + 'Ask me any time, for example:  ' + $example + "`n" + 'Type  what do you remember  to see everything you taught me.')
}
function Find-Fact($text) {
  $qWords = @(Get-Words $text)
  if ($qWords.Count -eq 0 -or $BRAIN.facts.Count -eq 0) { return $null }
  $best = $null
  $bestScore = 0.0
  foreach ($fa in $BRAIN.facts) {
    $kWords = @(Get-Words $fa.q)
    if ($kWords.Count -eq 0) { continue }
    $cover = Get-MatchScore $qWords $kWords
    if ($cover -lt 0.66) { continue }
    $back = Get-MatchScore $kWords $qWords
    if ($fa.said) { $back = [Math]::Max($back, (Get-MatchScore (@(Get-Words $fa.a)) $qWords)) }
    if ($back -lt 0.34) { continue }
    $score = $cover + $back
    if ($score -gt $bestScore) { $bestScore = $score; $best = $fa }
  }
  if ($null -eq $best) { return $null }
  return @{ fact = $best; score = $bestScore }
}
function Fact-Reply($hit) {
  $fa = $hit.fact
  Do-Action 'wag' 1.2
  if ($fa.said) { return (New-Reply ('You told me: ' + (Flip-Person $fa.a) + ' ' + $EM.paw) $null) }
  return (New-Reply ('From what you taught me: ' + $fa.a + ' ' + $EM.paw) $null)
}
function Get-FactsText {
  if ($BRAIN.facts.Count -eq 0) { return ('You have not taught me anything yet. Try:' + "`n" + '  teach: standup time = 10:00 am' + "`n" + '  remember that my car is parked on level 3') }
  $lines = @('Things you taught me (' + $BRAIN.facts.Count + '):')
  $num = 0
  foreach ($fa in $BRAIN.facts) {
    $num++
    if ($fa.said) { $lines += ([string]$num + '. ' + (Flip-Person $fa.a)) } else { $lines += ([string]$num + '. ' + $fa.q + '  =  ' + $fa.a) }
  }
  $lines += ''
  $lines += 'Type  forget 2  to remove one, or teach me again to change it.'
  return ($lines -join "`n")
}

# ---------- notes ----------
function Add-Note($text) {
  $tx = ([string]$text).Trim() -replace '^(that|this)\s+', ''
  if ($tx -eq '') { return 'What should I write down? Example:  note call the bank about the card' }
  $null = $BRAIN.notes.Add(@{ text = $tx; at = (Get-Date).ToString('yyyy-MM-dd HH:mm') })
  Save-Brain
  return ('Noted! ' + $EM.book + ' (note ' + $BRAIN.notes.Count + ')  Type  notes  to see them all.')
}
function Get-NotesText($filterWords) {
  if ($BRAIN.notes.Count -eq 0) { return 'You have no notes yet. Type for example:  note buy dog food' }
  $hasFilter = ($null -ne $filterWords -and @($filterWords).Count -gt 0)
  $lines = @()
  $num = 0
  $shown = 0
  foreach ($nt in $BRAIN.notes) {
    $num++
    if ($hasFilter) { if ((Get-MatchScore @(Get-Words $nt.text) $filterWords) -lt 0.5) { continue } }
    $shown++
    $lines += ([string]$num + '. ' + $nt.text + '   (' + $nt.at + ')')
  }
  if ($shown -eq 0) { return 'No notes match that.' }
  $head = 'Your notes:'
  if ($hasFilter) { $head = 'Notes that match:' }
  return ($head + "`n" + ($lines -join "`n") + "`n`n" + 'Type  delete note 2  to remove one, or  export notes  to open them in Notepad.')
}
function Export-Notes {
  if ($BRAIN.notes.Count -eq 0) { return 'You have no notes yet.' }
  $file = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'DogPet notes.txt'
  $lines = @('My notes from ' + $cfg.dogName + '  (saved ' + (Get-Date).ToString('yyyy-MM-dd HH:mm') + ')', '')
  foreach ($nt in $BRAIN.notes) { $lines += ('- ' + $nt.text + '   (' + $nt.at + ')') }
  $lines | Set-Content -Path $file -Encoding UTF8
  Start-Process 'notepad.exe' ('"' + $file + '"')
  return ('I saved your notes to ' + $file + ' and opened them in Notepad.')
}

# ---------- shortcuts and routines ----------
function Add-Shortcut($name, $target) {
  $nm = ([string]$name).ToLower().Trim().Trim('"')
  $tg = ([string]$target).Trim().Trim('"')
  if ($nm -eq '' -or $tg -eq '') { return 'Example:  add shortcut jira = https://jira.example.com' }
  if ($tg -match '^www\.') { $tg = 'https://' + $tg }
  $BRAIN.shortcuts[$nm] = $tg
  Save-Brain
  return ('Saved! ' + $EM.paw + ' Now just type  open ' + $nm + '   (it opens ' + $tg + ')')
}
function Get-ShortcutsText {
  if ($BRAIN.shortcuts.Count -eq 0) { return ('No shortcuts yet. Make one like this:' + "`n" + '  add shortcut jira = https://jira.example.com' + "`n" + '  add shortcut project = C:\Users\you\Documents\Project') }
  $lines = @('Your shortcuts:')
  foreach ($key in ($BRAIN.shortcuts.Keys | Sort-Object)) { $lines += ('- ' + $key + '  ->  ' + $BRAIN.shortcuts[$key]) }
  $lines += ''
  $lines += 'Type  open <name>  to use one, or  delete shortcut <name>.'
  return ($lines -join "`n")
}
function Split-RoutineSteps($text) {
  return @([regex]::Split([string]$text, '\s*;\s*|\s+and then\s+|\s+then\s+', 'IgnoreCase') | Where-Object { $_.Trim() -ne '' } | ForEach-Object { $_.Trim() })
}
function Add-Routine($name, $stepsText) {
  $nm = ([string]$name).ToLower().Trim()
  $steps = @(Split-RoutineSteps $stepsText)
  if ($nm -eq '' -or $steps.Count -eq 0) { return 'Example:  add routine morning = open outlook; open teams; brief me' }
  $BRAIN.routines[$nm] = $steps
  Save-Brain
  $lines = @('Saved your "' + $nm + '" routine with ' + $steps.Count + ' steps:')
  $num = 0
  foreach ($st in $steps) { $num++; $lines += ('  ' + $num + '. ' + $st) }
  $lines += ''
  $hint = 'run ' + $nm
  if ($nm -eq 'morning') { $hint = 'start my day' }
  $lines += ('Type  ' + $hint + '  to do it all at once.')
  return ($lines -join "`n")
}
function Get-RoutinesText {
  if ($BRAIN.routines.Count -eq 0) { return ('No routines yet. A routine does several things with one command:' + "`n" + '  add routine morning = open outlook; open teams; brief me' + "`n" + 'Then type  start my day  (or  run morning).') }
  $lines = @('Your routines:')
  foreach ($key in ($BRAIN.routines.Keys | Sort-Object)) { $lines += ('- ' + $key + ':  ' + (@($BRAIN.routines[$key]) -join '; ')) }
  $lines += ''
  $lines += 'Type  run <name>  to start one, or  delete routine <name>.'
  return ($lines -join "`n")
}
function Run-Steps($steps, $depth, $title) {
  $lines = @($title)
  $num = 0
  foreach ($st in @($steps)) {
    $num++
    $rep = $null
    try { $rep = Get-ReplyCore $st ($depth + 1) } catch { Write-Log $_ }
    $res = 'done'
    if ($null -ne $rep -and $rep.text) { $res = Short-Text $rep.text 160 }
    $lines += ([string]$num + '. ' + $st + "`n" + '   -> ' + $res)
  }
  return (New-Reply ($lines -join "`n") $null)
}

# ---------- daily brief ----------
function Get-Brief {
  Update-DayCounter
  $now = Get-Date
  $lines = @('Here is your day, ' + $cfg.userName + ' ' + $EM.dog + '  (' + $now.ToString('dddd, d MMMM, h:mm tt') + ')')
  $wt = '- Water: ' + $cfg.glasses + ' of ' + $cfg.waterGoal + ' glasses'
  if ([int]$cfg.glasses -lt [int]$cfg.waterGoal) { $wt += ' ' + $EM.water + ' keep drinking!' } else { $wt += ' - goal reached, great job!' }
  $lines += $wt
  $todos = @($cfg.todos)
  if ($todos.Count -eq 0) { $lines += '- To-dos: none. Add one with  todo <task>' }
  else {
    $more = ''
    if ($todos.Count -gt 5) { $more = ' (+' + ($todos.Count - 5) + ' more)' }
    $lines += ('- To-dos (' + $todos.Count + '): ' + ((@($todos | Select-Object -First 5)) -join ';  ') + $more)
  }
  $todayRem = @($PET.reminders | Where-Object { $_.at.Date -eq [datetime]::Today } | Sort-Object { $_.at })
  if ($todayRem.Count -gt 0) {
    $rl = @()
    foreach ($rm in ($todayRem | Select-Object -First 4)) { $rl += ($rm.at.ToString('h:mm tt') + ' ' + $rm.text) }
    $lines += ('- Reminders today: ' + ($rl -join ';  '))
  } else { $lines += '- Reminders today: none' }
  if ($PET.focusOn) { $lines += ('- Focus session: ' + [Math]::Ceiling(($PET.focusUntil - $now).TotalMinutes) + ' minutes left') }
  try {
    $pwr = [System.Windows.Forms.SystemInformation]::PowerStatus
    $pct = [int]([double]$pwr.BatteryLifePercent * 100)
    if ([int]$pwr.BatteryChargeStatus -ne 128 -and [string]$pwr.PowerLineStatus -ne 'Online' -and $pct -le 30) { $lines += ('- Battery is at ' + $pct + '% - plug in soon') }
  } catch { }
  try {
    $sysDrive = New-Object System.IO.DriveInfo($env:SystemDrive)
    if ($sysDrive.IsReady -and ($sysDrive.AvailableFreeSpace / $sysDrive.TotalSize) -lt 0.1) { $lines += ('- Drive ' + $env:SystemDrive + ' is almost full (' + (Format-Size $sysDrive.AvailableFreeSpace) + ' free). Try:  check my downloads') }
  } catch { }
  if ($BRAIN.notes.Count -gt 0) { $lines += ('- Notes saved: ' + $BRAIN.notes.Count + '  (type  notes)') }
  $lines += ''
  $lines += ((Get-Random -InputObject $Quotes) + ' ' + $EM.muscle)
  $BRAIN.lastBrief = $now.ToString('yyyy-MM-dd')
  Save-Brain
  return ($lines -join "`n")
}
function Get-ShortBrief {
  Update-DayCounter
  $todayRem = @($PET.reminders | Where-Object { $_.at.Date -eq [datetime]::Today }).Count
  return ('Today: ' + @($cfg.todos).Count + ' to-dos, ' + $todayRem + ' reminders, water ' + $cfg.glasses + '/' + $cfg.waterGoal + '. Double-click me and type  brief me  for your plan.')
}

# ---------- numbers, units and dates ----------
$Units = @{}
foreach ($ud in @(
  'len|0.001|mm millimeter millimeters millimetre millimetres', 'len|0.01|cm centimeter centimeters centimetre centimetres',
  'len|1|m meter meters metre metres', 'len|1000|km kilometer kilometers kilometre kilometres kms',
  'len|0.0254|in inch inches', 'len|0.3048|ft foot feet', 'len|0.9144|yd yard yards', 'len|1609.344|mi mile miles',
  'mass|0.000001|mg milligram milligrams', 'mass|0.001|g gram grams gm', 'mass|1|kg kgs kilo kilos kilogram kilograms',
  'mass|0.45359237|lb lbs pound pounds', 'mass|0.028349523125|oz ounce ounces', 'mass|1000|ton tons tonne tonnes', 'mass|6.35029318|stone stones st',
  'vol|0.001|ml milliliter milliliters millilitre millilitres', 'vol|1|l liter liters litre litres ltr', 'vol|3.785411784|gal gallon gallons',
  'vol|0.2365882365|cup cups', 'vol|0.0147867648|tbsp tablespoon tablespoons', 'vol|0.00492892159|tsp teaspoon teaspoons',
  'vol|0.0295735296|floz', 'vol|0.473176473|pint pints', 'vol|0.946352946|quart quarts',
  'data|0.125|bit bits', 'data|1|b byte bytes', 'data|1024|kb kilobyte kilobytes', 'data|1048576|mb megabyte megabytes',
  'data|1073741824|gb gigabyte gigabytes', 'data|1099511627776|tb terabyte terabytes',
  'time|0.001|ms millisecond milliseconds', 'time|1|s sec secs second seconds', 'time|60|min mins minute minutes',
  'time|3600|h hr hrs hour hours', 'time|86400|day days', 'time|604800|week weeks', 'time|2629746|month months', 'time|31556952|year years yr yrs',
  'speed|0.2777777778|kmh kph km/h kmph', 'speed|0.44704|mph', 'speed|1|m/s mps', 'speed|0.5144444444|knot knots kn',
  'area|1|m2 sqm', 'area|0.09290304|ft2 sqft', 'area|4046.8564224|acre acres', 'area|10000|ha hectare hectares', 'area|1000000|km2 sqkm'
)) {
  $bits = $ud -split '\|'
  foreach ($un in ($bits[2] -split ' ')) { $Units[$un] = @($bits[0], [double]$bits[1]) }
}
$TempUnits = @{ 'c' = 'C'; 'celsius' = 'C'; 'centigrade' = 'C'; 'f' = 'F'; 'fahrenheit' = 'F'; 'k' = 'K'; 'kelvin' = 'K' }
$Currencies = @('usd', 'inr', 'eur', 'gbp', 'jpy', 'aud', 'cad', 'cny', 'sgd', 'aed', 'chf', 'nzd', 'sar', 'rupees', 'rupee', 'dollars', 'dollar', 'euros', 'euro', 'pounds sterling')
function Format-Num($x) {
  $v = [double]$x
  if ([Math]::Abs($v) -ge 1e15 -or ([Math]::Abs($v) -lt 0.0001 -and $v -ne 0)) { return $v.ToString('G6') }
  return $v.ToString('#,0.####')
}
function Do-Convert($val, $fromU, $toU) {
  $v = [double]$val
  $f = ([string]$fromU).ToLower()
  $to = ([string]$toU).ToLower()
  if ($TempUnits.ContainsKey($f) -and $TempUnits.ContainsKey($to)) {
    $a = $TempUnits[$f]; $b2 = $TempUnits[$to]
    $c = $v
    if ($a -eq 'F') { $c = ($v - 32) * 5 / 9 } elseif ($a -eq 'K') { $c = $v - 273.15 }
    $r = $c
    if ($b2 -eq 'F') { $r = $c * 9 / 5 + 32 } elseif ($b2 -eq 'K') { $r = $c + 273.15 }
    return (New-Reply ((Format-Num $v) + ' ' + $a + ' = ' + (Format-Num ([Math]::Round($r, 2))) + ' ' + $b2) $null)
  }
  if ($Currencies -contains $f -or $Currencies -contains $to) {
    $q = (Format-Num $v) + ' ' + $f + ' to ' + $to
    Open-Web ('https://www.google.com/search?q=' + [uri]::EscapeDataString($q))
    return (New-Reply ('Exchange rates change every minute and I work offline, so I opened the live rate for ' + $q + ' in your browser.') $null)
  }
  if (-not $Units.ContainsKey($f) -or -not $Units.ContainsKey($to)) { return $null }
  $uf = $Units[$f]; $ut = $Units[$to]
  if ($uf[0] -ne $ut[0]) { return (New-Reply ('I cannot turn ' + $f + ' into ' + $to + ' - they measure different things.') $null) }
  $r = $v * $uf[1] / $ut[1]
  return (New-Reply ((Format-Num $v) + ' ' + $f + ' = ' + (Format-Num $r) + ' ' + $to) $null)
}
function Parse-Day($s) {
  $raw = ([string]$s).Trim() -replace '[\?\.!]+$', ''
  $x = $raw.ToLower() -replace '^(the |on |is )', '' -replace "'", '' -replace '(\d+)(st|nd|rd|th)\b', '$1'
  $today = [datetime]::Today
  if ($x -match '^(today|now)$') { return $today }
  if ($x -eq 'tomorrow') { return $today.AddDays(1) }
  if ($x -eq 'yesterday') { return $today.AddDays(-1) }
  $hol = @{ 'christmas' = '12-25'; 'xmas' = '12-25'; 'christmas day' = '12-25'; 'christmas eve' = '12-24'; 'new year' = '01-01'; 'new years' = '01-01'
    'new years day' = '01-01'; 'new years eve' = '12-31'; 'valentines' = '02-14'; 'valentines day' = '02-14'; 'valentine' = '02-14'; 'halloween' = '10-31' }
  if ($hol.ContainsKey($x)) {
    $md = $hol[$x] -split '-'
    $d = New-Object DateTime($today.Year, [int]$md[0], [int]$md[1])
    if ($d -lt $today) { $d = $d.AddYears(1) }
    return $d
  }
  $days = @('sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday')
  if ($x -match '^(next |this |coming )?(sunday|monday|tuesday|wednesday|thursday|friday|saturday)$') {
    $want = [array]::IndexOf($days, $Matches[2])
    $diff = ($want - [int]$today.DayOfWeek + 7) % 7
    if ($diff -eq 0 -and $Matches[1] -ne 'this ') { $diff = 7 }
    return $today.AddDays($diff)
  }
  $dt = [datetime]::MinValue
  $okDate = [datetime]::TryParse($x, [ref]$dt)
  if (-not $okDate) { $okDate = [datetime]::TryParse($x, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$dt) }
  if (-not $okDate) { return $null }
  if ($x -notmatch '\d{4}' -and $dt.Date -lt $today) { $dt = $dt.AddYears(1) }
  return $dt.Date
}
function Get-WeekNumber {
  $cal = [Globalization.CultureInfo]::InvariantCulture.Calendar
  return $cal.GetWeekOfYear([datetime]::Today, [Globalization.CalendarWeekRule]::FirstFourDayWeek, [DayOfWeek]::Monday)
}

# ---------- the skills (one function per kind of request) ----------
function Skill-teachpair($m, $t, $depth) { return (New-Reply (Add-Fact $m[1] $m[2] $false) $null) }
function Skill-remindto($m, $t, $depth) { return (New-Reply ((Add-TodoText $m[1]) + "`n" + 'I put it on your to-do list. (For a reminder at a time, say:  remind me to ' + $m[1] + ' in 30 minutes)') $null) }
function Skill-teachsay($m, $t, $depth) { return (New-Reply (Add-Fact $m[1] ($m[1] + ' ' + $m[2] + ' ' + $m[3]) $true) $null) }
function Skill-forgetall($m, $t, $depth) { return (Ask-Confirm ('Forget all ' + $BRAIN.facts.Count + ' things you taught me?') 'forgetall' $null) }
function Skill-forget($m, $t, $depth) {
  $what = ([string]$m[1]).Trim()
  if ($what -match '^\d+$') {
    $num = [int]$what
    if ($num -lt 1 -or $num -gt $BRAIN.facts.Count) { return (New-Reply ('I only know ' + $BRAIN.facts.Count + ' things. Type  what do you remember  to see them.') $null) }
    $BRAIN.facts.RemoveAt($num - 1)
    Save-Brain
    return (New-Reply ('Okay, I forgot number ' + $num + '.') $null)
  }
  $hit = Find-Fact $what
  if ($null -eq $hit) { return (New-Reply ('I do not remember anything about "' + $what + '". Type  what do you remember  to see the list.') $null) }
  $BRAIN.facts.Remove($hit.fact)
  Save-Brain
  return (New-Reply ('Okay, I forgot: ' + $hit.fact.q) $null)
}
function Skill-memories($m, $t, $depth) { return (New-Reply (Get-FactsText) $null) }
function Skill-noteexport($m, $t, $depth) { return (New-Reply (Export-Notes) $null) }
function Skill-notelist($m, $t, $depth) { return (New-Reply (Get-NotesText $null) $null) }
function Skill-notedel($m, $t, $depth) {
  $num = [int]$m[1]
  if ($num -lt 1 -or $num -gt $BRAIN.notes.Count) { return (New-Reply ('There is no note ' + $num + '. Type  notes  to see them.') $null) }
  $gone = $BRAIN.notes[$num - 1].text
  $BRAIN.notes.RemoveAt($num - 1)
  Save-Brain
  return (New-Reply ('Deleted note: ' + $gone) $null)
}
function Skill-noteclear($m, $t, $depth) { return (Ask-Confirm ('Delete all ' + $BRAIN.notes.Count + ' notes?') 'clearnotes' $null) }
function Skill-notefind($m, $t, $depth) {
  $fw = @(Get-Words $m[1])
  if ($fw.Count -eq 0) { return (New-Reply 'What should I look for in your notes? Example:  find in notes bank' $null) }
  return (New-Reply (Get-NotesText $fw) $null)
}
function Skill-noteadd($m, $t, $depth) { return (New-Reply (Add-Note $m[1]) $null) }
function Skill-shortcutadd($m, $t, $depth) { return (New-Reply (Add-Shortcut $m[1] $m[2]) $null) }
function Skill-shortcutlist($m, $t, $depth) { return (New-Reply (Get-ShortcutsText) $null) }
function Skill-shortcutdel($m, $t, $depth) {
  $nm = ([string]$m[1]).ToLower().Trim()
  if (-not $BRAIN.shortcuts.ContainsKey($nm)) { return (New-Reply ('I have no shortcut called ' + $nm + '.') $null) }
  $BRAIN.shortcuts.Remove($nm)
  Save-Brain
  return (New-Reply ('Deleted the shortcut ' + $nm + '.') $null)
}
function Skill-routineadd($m, $t, $depth) { return (New-Reply (Add-Routine $m[1] $m[2]) $null) }
function Skill-routinelist($m, $t, $depth) { return (New-Reply (Get-RoutinesText) $null) }
function Skill-routinedel($m, $t, $depth) {
  $nm = ([string]$m[1]).ToLower().Trim()
  if (-not $BRAIN.routines.ContainsKey($nm)) { return (New-Reply ('I have no routine called ' + $nm + '.') $null) }
  $BRAIN.routines.Remove($nm)
  Save-Brain
  return (New-Reply ('Deleted the routine ' + $nm + '.') $null)
}
function Skill-myday($m, $t, $depth) {
  foreach ($rn in @('morning', 'my day', 'start', 'day', 'work')) {
    if ($BRAIN.routines.ContainsKey($rn) -and $depth -lt 2) { return (Run-Steps $BRAIN.routines[$rn] $depth ('Good morning! Running your "' + $rn + '" routine ' + $EM.paw)) }
  }
  return (New-Reply ((Get-Brief) + "`n`n" + 'Tip: make a morning routine and I will open your apps too:' + "`n" + '  add routine morning = open outlook; open teams; brief me') $null)
}
function Skill-routinerun($m, $t, $depth) {
  $nm = ([string]$m[1]).ToLower().Trim()
  if (-not $BRAIN.routines.ContainsKey($nm)) { return $null }
  if ($depth -ge 2) { return (New-Reply ('(skipped routine ' + $nm + ' - routines inside routines are too deep for me)') $null) }
  return (Run-Steps $BRAIN.routines[$nm] $depth ('Running your "' + $nm + '" routine ' + $EM.paw))
}
function Skill-brief($m, $t, $depth) { return (New-Reply (Get-Brief) $null) }
function Skill-again($m, $t, $depth) {
  if ([string]::IsNullOrWhiteSpace($BRAIN.lastCmd) -or $depth -ge 1) { return (New-Reply 'There is nothing to repeat yet.' $null) }
  return (Get-ReplyCore $BRAIN.lastCmd ($depth + 1))
}
function Skill-stopjob($m, $t, $depth) {
  if ($null -eq $JOB.ps) { return $null }
  Stop-BgJob
  return (New-Reply 'Okay, I stopped.' $null)
}
function Skill-copylast($m, $t, $depth) {
  if ([string]::IsNullOrWhiteSpace($BRAIN.lastReply)) { return (New-Reply 'There is nothing to copy yet.' $null) }
  [System.Windows.Clipboard]::SetText([string]$BRAIN.lastReply)
  return (New-Reply 'Copied my last answer to the clipboard. Paste it anywhere with Ctrl+V.' $null)
}
function Skill-clipshow($m, $t, $depth) {
  $ct = ''
  try { $ct = [System.Windows.Clipboard]::GetText() } catch { }
  if ([string]::IsNullOrEmpty($ct)) { return (New-Reply 'Your clipboard has no text in it right now.' $null) }
  if ($ct.Length -gt 1500) { $ct = $ct.Substring(0, 1500) + "`n..." }
  return (New-Reply ('In your clipboard:' + "`n" + (Code-Block $ct)) $null)
}
function Skill-pickresult($m, $t, $depth) {
  $num = [int]$m[1]
  if ($num -lt 1 -or $num -gt $BRAIN.results.Count) { return $null }
  return (Open-Result $num)
}
function Skill-resultfolder($m, $t, $depth) {
  if ($BRAIN.results.Count -eq 0) { return (New-Reply 'I have no file results yet. Try:  find resume' $null) }
  return (Folder-Result ([int]$m[1]))
}
function Skill-findin($m, $t, $depth) {
  $place = Get-NamedFolder $m[2]
  if ($null -eq $place -or -not (Test-Path -LiteralPath $place)) { return (New-Reply ('I cannot find the folder "' + $m[2] + '".') $null) }
  return (Start-Find $m[1] $place)
}
function Skill-find($m, $t, $depth) {
  $query = ([string]$m[1]).Trim()
  if ($query -match '^(out|how|why|what|if|the difference|duplicates?)\b') { return $null }
  if (@(Get-Words $query).Count -ge 2 -and $null -ne (Find-Knowledge $t)) { return $null }
  return (Start-Find $query $null)
}
function Skill-bigfiles($m, $t, $depth) {
  $roots = @()
  $where = 'Desktop, Documents, Downloads, Pictures and Videos'
  if ($m[1]) {
    $place = Get-NamedFolder $m[1]
    if ($null -eq $place -or -not (Test-Path -LiteralPath $place)) { return (New-Reply ('I cannot find the folder "' + $m[1] + '".') $null) }
    $roots = @($place)
    $where = $place
  } else {
    foreach ($p in @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('MyDocuments'), (Get-DownloadsPath), [Environment]::GetFolderPath('MyPictures'), [Environment]::GetFolderPath('MyVideos'))) { if ($p -and (Test-Path -LiteralPath $p)) { $roots += $p } }
  }
  $ok = Start-BgJob 'big' $BigScript @($roots, 15) @{ where = $where } ($cfg.dogName + ' is measuring your files')
  if (-not $ok) { return (Busy-Reply) }
  return (New-Reply ('Measuring the files in ' + $where + '...') $null)
}
function Skill-recent($m, $t, $depth) {
  $dir = Join-Path $env:APPDATA 'Microsoft\Windows\Recent'
  $wsh = New-Object -ComObject WScript.Shell
  $items = @()
  foreach ($lk in @(Get-ChildItem -LiteralPath $dir -Filter '*.lnk' -ErrorAction SilentlyContinue | Sort-Object -Property LastWriteTime -Descending | Select-Object -First 60)) {
    if ($items.Count -ge 15) { break }
    try {
      $tp = $wsh.CreateShortcut($lk.FullName).TargetPath
      if ([string]::IsNullOrWhiteSpace($tp) -or -not (Test-Path -LiteralPath $tp)) { continue }
      $gi = Get-Item -LiteralPath $tp -ErrorAction Stop
      $len = 0
      if (-not $gi.PSIsContainer) { $len = $gi.Length }
      $items += [pscustomobject]@{ path = $gi.FullName; name = $gi.Name; folder = [bool]$gi.PSIsContainer; size = $len; time = $lk.LastWriteTime }
    } catch { }
  }
  if ($items.Count -eq 0) { return (New-Reply 'I could not find any recent files.' $null) }
  return (New-Reply (Show-Files $items 'Files you opened recently:' $null) $null)
}
function Skill-dlreport($m, $t, $depth) {
  $ok = Start-BgJob 'dl' $DlScript @((Get-DownloadsPath)) @{} ($cfg.dogName + ' is checking your Downloads folder')
  if (-not $ok) { return (Busy-Reply) }
  return (New-Reply 'Let me sniff around your Downloads folder...' $null)
}

$PartCheck['7'] = $true   # ===== end of PART 7 of 9 =====

function Skill-organize($m, $t, $depth) {
  $root = Get-DownloadsPath
  $n = @(Get-ChildItem -LiteralPath $root -File -ErrorAction SilentlyContinue).Count
  if ($n -eq 0) { return (New-Reply 'Your Downloads folder has no loose files - it is already tidy!' $null) }
  return (Ask-Confirm ('I will sort the ' + $n + ' loose files in ' + $root + ' into folders by type (Images, Documents, Installers, Archives, Videos, Music, Code, Other). Nothing gets deleted. Okay?') 'organize' $null)
}
function Skill-oldinstallers($m, $t, $depth) {
  $list = @(Get-OldInstallers)
  if ($list.Count -eq 0) { return (New-Reply 'There are no installers older than 30 days in your Downloads folder.' $null) }
  $size = ($list | Measure-Object -Property Length -Sum).Sum
  $names = (@($list | Select-Object -First 6 | ForEach-Object { $_.Name }) -join ', ')
  if ($list.Count -gt 6) { $names += ', ...' }
  return (Ask-Confirm ('Move ' + $list.Count + ' old installers (' + (Format-Size $size) + ') to the Recycle Bin?' + "`n" + $names + "`n" + 'You can restore them from the Recycle Bin.') 'installers' @($list | ForEach-Object { $_.FullName }))
}
function Skill-oldfiles($m, $t, $depth) {
  $cut = [datetime]::Now.AddDays(-30)
  $items = @(Get-ChildItem -LiteralPath (Get-DownloadsPath) -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $cut } | Sort-Object -Property Length -Descending | Select-Object -First 15 | ForEach-Object {
    [pscustomobject]@{ path = $_.FullName; name = $_.Name; folder = $false; size = $_.Length; time = $_.LastWriteTime } })
  if ($items.Count -eq 0) { return (New-Reply 'Nothing in Downloads is older than 30 days.' $null) }
  return (New-Reply (Show-Files $items 'The biggest downloads older than 30 days:' 'Type  open 1  to check one, or  folder 1  to see it in File Explorer. I never delete files without asking.') $null)
}
function Skill-recycle($m, $t, $depth) { return (Ask-Confirm 'Empty the Recycle Bin? The files in it will be gone for good.' 'recycle' $null) }
function Skill-temp($m, $t, $depth) { return (Ask-Confirm 'Delete temporary files older than 3 days from your Temp folder? Windows and apps make new ones when they need them, and files in use are skipped.' 'temp' $null) }
function Skill-screenshot($m, $t, $depth) {
  $file = Take-Screenshot
  Bark-Sound
  return (New-Reply ('Snap! ' + $EM.star + ' I saved a screenshot of your whole screen:' + "`n" + $file + "`n" + 'Type  open 1  to see it, or  folder 1  to open the folder.') $null)
}
function Skill-snip($m, $t, $depth) { Start-Process 'ms-screenclip:'; return (New-Reply 'Draw a box around the part you want. It goes to your clipboard - paste it with Ctrl+V.' $null) }
function Skill-lock($m, $t, $depth) { Start-Process 'rundll32.exe' 'user32.dll,LockWorkStation'; return (New-Reply ('Locking your PC. I will guard it! ' + $EM.paw) $null) }
function Skill-shutdown($m, $t, $depth) { return (Ask-Confirm 'Shut down your PC? (I will give you 60 seconds to save your work.)' 'shutdown' $null) }
function Skill-restart($m, $t, $depth) { return (Ask-Confirm 'Restart your PC? (I will give you 60 seconds to save your work.)' 'restart' $null) }
function Skill-cancelshutdown($m, $t, $depth) { Start-Process 'shutdown.exe' '/a'; return (New-Reply 'Cancelled. Your PC stays on.' $null) }
function Skill-volume($m, $t, $depth) {
  $word = ([string]$m[1]).ToLower()
  if ($word -match '^(mute|unmute)$') { Send-MediaKey 173 1; return (New-Reply 'Toggled mute.' $null) }
  if ($word -match '^(up|higher|louder)$') { Send-MediaKey 175 5; return (New-Reply 'Volume up!' $null) }
  Send-MediaKey 174 5
  return (New-Reply 'Volume down.' $null)
}
function Skill-minimize($m, $t, $depth) { Minimize-AllWindows; return (New-Reply 'All windows are minimized. Type  restore windows  to bring them back.' $null) }
function Skill-restorewin($m, $t, $depth) { (New-Object -ComObject Shell.Application).UndoMinimizeALL(); return (New-Reply 'Windows are back.' $null) }
function Skill-running($m, $t, $depth) { return (New-Reply (Get-RunningAppsText) $null) }
function Skill-topapps($m, $t, $depth) { return (New-Reply ((Get-MemoryText) + "`n`n" + (Get-TopAppsText)) $null) }
function Skill-close($m, $t, $depth) {
  $target = ([string]$m[1]).ToLower().Trim()
  if ($target -match '^(chat|chat window|this|this window|the chat|chatbox|chat box)$') { if ($null -ne $UI.chat) { $UI.chat.Hide() }; return (New-Reply 'Closed the chat. Double-click me to open it again.' $null) }
  $dn = ([string]$cfg.dogName).ToLower()
  if ($target -match '^(you|yourself|dog|dog pet|dogpet|the dog|pet)$' -or $target -eq $dn) { return (Ask-Confirm 'Quit Dog Pet? (Double-click DogPet.bat to bring me back.)' 'quit' $null) }
  $res = Close-AppByName $target
  if ($null -eq $res) { return (New-Reply ('I could not find an open app called "' + $target + '". Type  open apps  to see what is open.') $null) }
  return (New-Reply $res $null)
}
function Skill-sysinfo($m, $t, $depth) {
  $parts = @('How your PC is doing ' + $EM.dog, '', (Get-BatteryText), (Get-MemoryText), (Get-CpuText), '', (Get-DiskText), '', (Get-UptimeText), (Get-WifiText))
  return (New-Reply ($parts -join "`n") $null)
}
function Skill-battery($m, $t, $depth) { return (New-Reply (Get-BatteryText) $null) }
function Skill-disk($m, $t, $depth) { return (New-Reply (Get-DiskText) $null) }
function Skill-memory($m, $t, $depth) { return (New-Reply (Get-MemoryText) $null) }
function Skill-cpu($m, $t, $depth) { return (New-Reply (Get-CpuText) $null) }
function Skill-uptime($m, $t, $depth) { return (New-Reply (Get-UptimeText) $null) }
function Skill-ip($m, $t, $depth) { return (New-Reply (Get-IpText) $null) }
function Skill-wifi($m, $t, $depth) { return (New-Reply (Get-WifiText) $null) }
function Skill-pcname($m, $t, $depth) { return (New-Reply (Get-PcNameText) $null) }
function Skill-settingspage($m, $t, $depth) {
  $key = ([string]$m[1]).ToLower()
  if (-not $SettingsPages.ContainsKey($key)) { $key = $key -replace 's$', '' }
  if (-not $SettingsPages.ContainsKey($key)) { Start-Process 'ms-settings:'; return (New-Reply 'Opening Settings...' $null) }
  Start-Process ('ms-settings:' + $SettingsPages[$key])
  return (New-Reply ('Opening ' + $key + ' settings...') $null)
}
function Skill-open($m, $t, $depth) {
  $verb = ([string]$m[1]).ToLower()
  $target = ([string]$m[2]).Trim()
  $isOpen = ($verb -eq 'open' -or $verb -eq 'launch')
  if (-not $isOpen -and $target -match '^(focus|timer|sleep|pomodoro|nap|bed|over|again|it|that|this|a |an |the )') { return $null }
  $minScore = 59
  if (-not $isOpen) { $minScore = 89 }
  $rep = Open-Target $target 0 $minScore
  if ($null -ne $rep) { return $rep }
  if (-not $isOpen) { return $null }
  return (New-Reply ('I could not find an app, folder or shortcut called "' + $target + '" on this PC ' + $EM.think + "`n" + 'Try:  find ' + $target + '  (search your files)  |  search ' + $target + '  (Google)  |  add shortcut ' + $target + ' = https://...') $null)
}
function Skill-wiki($m, $t, $depth) { Open-Web ('https://en.wikipedia.org/w/index.php?search=' + [uri]::EscapeDataString($m[1])); return (New-Reply ('Opening Wikipedia for: ' + $m[1]) $null) }
function Skill-translate($m, $t, $depth) {
  $txt = [string]$m[1]
  $lang = 'en'
  $langs = @{ 'hindi' = 'hi'; 'tamil' = 'ta'; 'telugu' = 'te'; 'kannada' = 'kn'; 'malayalam' = 'ml'; 'bengali' = 'bn'; 'marathi' = 'mr'; 'gujarati' = 'gu'
    'punjabi' = 'pa'; 'urdu' = 'ur'; 'english' = 'en'; 'spanish' = 'es'; 'french' = 'fr'; 'german' = 'de'; 'italian' = 'it'; 'portuguese' = 'pt'
    'russian' = 'ru'; 'japanese' = 'ja'; 'chinese' = 'zh-CN'; 'korean' = 'ko'; 'arabic' = 'ar'; 'dutch' = 'nl'; 'turkish' = 'tr' }
  if ($txt -match '^(.+?)\s+(?:to|in|into)\s+([a-z]+)$' -and $langs.ContainsKey($Matches[2].ToLower())) { $lang = $langs[$Matches[2].ToLower()]; $txt = $Matches[1] }
  Open-Web ('https://translate.google.com/?sl=auto&tl=' + $lang + '&text=' + [uri]::EscapeDataString($txt))
  return (New-Reply ('I opened Google Translate for "' + $txt + '" in your browser.') $null)
}
function Skill-maps($m, $t, $depth) { Open-Web ('https://www.google.com/maps/search/' + [uri]::EscapeDataString($m[1])); return (New-Reply ('Opening the map for: ' + $m[1]) $null) }
function Skill-weather($m, $t, $depth) {
  $q = 'weather'
  if ($m[1]) { $q += ' ' + $m[1] }
  Open-Web ('https://www.google.com/search?q=' + [uri]::EscapeDataString($q))
  return (New-Reply ('I do not use the internet for my answers, so I opened the ' + $q + ' forecast in your browser.') $null)
}
function Skill-news($m, $t, $depth) {
  if ($m[1]) { Open-Web ('https://news.google.com/search?q=' + [uri]::EscapeDataString($m[1])); return (New-Reply ('Opening news about ' + $m[1] + ' in your browser.') $null) }
  Open-Web 'https://news.google.com/'
  return (New-Reply 'Opening the latest headlines in your browser.' $null)
}
function Skill-numbase($m, $t, $depth) {
  $n = [long]$m[1]
  $to = ([string]$m[2]).ToLower()
  if ($to -match '^hex') { return (New-Reply ([string]$n + ' = 0x' + [Convert]::ToString($n, 16).ToUpper()) $null) }
  if ($to -match '^bin') { return (New-Reply ([string]$n + ' = 0b' + [Convert]::ToString($n, 2)) $null) }
  return (New-Reply ([string]$n + ' = 0o' + [Convert]::ToString($n, 8)) $null)
}
function Skill-numbase2($m, $t, $depth) {
  $s = ([string]$m[1]).ToLower()
  if ($s.StartsWith('0x')) { $n = [Convert]::ToInt64($s.Substring(2), 16) } else { $n = [Convert]::ToInt64($s.Substring(2), 2) }
  return (New-Reply ($s + ' = ' + $n) $null)
}
function Skill-convert($m, $t, $depth) { return (Do-Convert $m[1] $m[2] $m[3]) }
function Skill-howmany($m, $t, $depth) {
  $v = 1.0
  if ($m[2]) { $v = [double]([string]$m[2]).Trim() }
  return (Do-Convert $v $m[3] $m[1])
}
function Skill-percent($m, $t, $depth) { $r = [double]$m[1] / 100 * [double]$m[2]; return (New-Reply ($m[1] + '% of ' + $m[2] + ' = ' + (Format-Num $r)) $null) }
function Skill-percentof($m, $t, $depth) {
  if ([double]$m[2] -eq 0) { return (New-Reply 'I cannot divide by zero!' $null) }
  $r = [double]$m[1] / [double]$m[2] * 100
  return (New-Reply ($m[1] + ' is ' + (Format-Num ([Math]::Round($r, 2))) + '% of ' + $m[2]) $null)
}
function Skill-pctchange($m, $t, $depth) {
  $a = [double]$m[1]; $b2 = [double]$m[2]
  if ($a -eq 0) { return (New-Reply 'I cannot work out a change from zero.' $null) }
  $r = ($b2 - $a) / [Math]::Abs($a) * 100
  $word = 'increase'
  if ($r -lt 0) { $word = 'decrease' }
  return (New-Reply ('From ' + $m[1] + ' to ' + $m[2] + ' is a ' + (Format-Num ([Math]::Round([Math]::Abs($r), 2))) + '% ' + $word + '.') $null)
}
function Skill-power($m, $t, $depth) { return (New-Reply ($m[1] + ' ^ ' + $m[2] + ' = ' + (Format-Num ([Math]::Pow([double]$m[1], [double]$m[2])))) $null) }
function Skill-sqrt($m, $t, $depth) { return (New-Reply ('Square root of ' + $m[1] + ' = ' + (Format-Num ([Math]::Sqrt([double]$m[1])))) $null) }
function Skill-hash($m, $t, $depth) {
  $alg = ([string]$m[1]).ToUpper()
  $hasher = [System.Security.Cryptography.HashAlgorithm]::Create($alg)
  $bytes = $hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes([string]$m[2]))
  $hex = -join ($bytes | ForEach-Object { $_.ToString('x2') })
  return (New-Reply ($alg + ' of "' + $m[2] + '":' + "`n" + (Code-Block $hex)) $null)
}
function Skill-daysuntil($m, $t, $depth) {
  $d = Parse-Day $m[1]
  if ($null -eq $d) { return $null }
  $diff = ($d - [datetime]::Today).Days
  $when = $d.ToString('dddd, d MMMM yyyy')
  if ($diff -eq 0) { return (New-Reply ('That is today! (' + $when + ')') $null) }
  if ($diff -lt 0) { return (New-Reply ($when + ' was ' + (-$diff) + ' days ago.') $null) }
  $weeks = ''
  if ($diff -ge 14) { $weeks = ' (about ' + [Math]::Round($diff / 7.0, 1) + ' weeks)' }
  return (New-Reply ($m[1] + ' is on ' + $when + ' - that is ' + $diff + ' days from today' + $weeks + '.') $null)
}
function Skill-datein($m, $t, $depth) {
  $n = [int]$m[1]
  $unit = ([string]$m[2]).ToLower()
  $d = [datetime]::Today
  if ($unit -match '^day') { $d = $d.AddDays($n) } elseif ($unit -match '^week') { $d = $d.AddDays(7 * $n) } elseif ($unit -match '^month') { $d = $d.AddMonths($n) } else { $d = $d.AddYears($n) }
  return (New-Reply ('In ' + $n + ' ' + $unit + ' it will be ' + $d.ToString('dddd, d MMMM yyyy') + '.') $null)
}
function Skill-weekday($m, $t, $depth) {
  $d = Parse-Day $m[1]
  if ($null -eq $d) { return $null }
  if ($d -eq [datetime]::Today) { return (New-Reply ('Today is ' + $d.ToString('dddd, d MMMM yyyy') + '.') $null) }
  $verb = 'is'
  if ($d -lt [datetime]::Today) { $verb = 'was' }
  return (New-Reply ($d.ToString('d MMMM yyyy') + ' ' + $verb + ' a ' + $d.ToString('dddd') + '.') $null)
}
function Skill-daysbetween($m, $t, $depth) {
  $d1 = Parse-Day $m[1]
  $d2 = Parse-Day $m[2]
  if ($null -eq $d1 -or $null -eq $d2) { return (New-Reply 'I could not read one of those dates. Try:  days between 1 jan 2026 and 25 dec 2026' $null) }
  return (New-Reply ('There are ' + [Math]::Abs(($d2 - $d1).Days) + ' days between ' + $d1.ToString('d MMM yyyy') + ' and ' + $d2.ToString('d MMM yyyy') + '.') $null)
}
function Skill-weeknum($m, $t, $depth) { return (New-Reply ('It is week ' + (Get-WeekNumber) + ' of ' + [datetime]::Today.Year + '.') $null) }
function Skill-coin($m, $t, $depth) { Do-Trick 'jump'; return (New-Reply ('*flips the coin with my nose* ... ' + (Get-Random -InputObject @('Heads!', 'Tails!'))) $null) }
function Skill-dice($m, $t, $depth) { Do-Trick 'spin'; return (New-Reply ('*rolls the dice* ... you got a ' + (Get-Random -Minimum 1 -Maximum 7) + '!') $null) }
function Skill-randnum($m, $t, $depth) {
  $lo = [int]$m[1]; $hi = [int]$m[2]
  if ($lo -gt $hi) { $tmp = $lo; $lo = $hi; $hi = $tmp }
  return (New-Reply ('Your random number: ' + (Get-Random -Minimum $lo -Maximum ($hi + 1))) $null)
}
function Skill-choose($m, $t, $depth) {
  $opts = @(([string]$m[1]) -split '\s*,\s*' | Where-Object { $_ -ne '' }) + @([string]$m[2])
  return (New-Reply ('*sniffs both* ... I pick: ' + (Get-Random -InputObject $opts) + '! ' + $EM.paw) $null)
}
function Skill-aboutme($m, $t, $depth) {
  return (New-Reply ('I am ' + $cfg.dogName + ', and I have my own brain! ' + $EM.dog + "`n" + 'I do not use ChatGPT, Gemini or any other AI, and I do not send what you type anywhere - everything stays on this PC.' + "`n" + 'I understand commands, do jobs on your PC (open apps, find files, check your PC, tidy Downloads...), know coding notes from knowledge.txt, and learn whatever you teach me. Type  help  to see it all.') $null)
}

# ---------- what each kind of request looks like ----------
$RxParts = @{
  '{ASK}' = '^(?:(?:what(?:''s| is| are)|whats|how much|how many|how|check|show|show me|tell me|get|give me|see)\s+)?(?:is\s+)?(?:my\s+|the\s+|our\s+|this\s+)?(?:pc(?:''s)?\s+|computer(?:''s)?\s+|laptop(?:''s)?\s+)?'
  '{TAIL}' = '(?:\s+(?:left|free|now|status|info|information|level|usage|used|percentage|percent|right now|today|on this pc|on my pc|on my computer|on my laptop|do i have|is left|is free|is used|have i got|address|details))*$'
}
$IntentList = @(
  @('teachpair', '^(?:learn|teach(?: you)?|remember|memori[sz]e)\s*[:,\-]?\s*(.+?)\s*(?:=>|->|=)\s*(.+)$'),
  @('remindto', '^(?:remember|don''t forget|dont forget)\s+to\s+(.+)$'),
  @('teachsay', '^(?:remember|learn|please remember|remember this|note that|fyi)\s*[:,]?\s+(?:that\s+)?(.+?)\s+(is|are|was|were|has|have|will be|lives|works|likes|loves|starts|ends|costs|means)\s+(.+)$'),
  @('forgetall', '^forget (?:everything|all)(?: you (?:learned|learnt|know))?$'),
  @('forget', '^forget\s+(?:about\s+|that\s+|fact\s+|memory\s+|number\s+)?#?(.+)$'),
  @('memories', '^(?:what do you (?:know|remember)(?: about me)?|what have you learn(?:ed|t)|what did i teach you|(?:show |list |my )?(?:memories|memory|facts|things you (?:learned|learnt|know)))$'),
  @('noteexport', '^(?:export|save|open|print)\s+(?:my\s+|all\s+)?notes(?:\s+(?:to|in)\s+(?:a\s+)?(?:file|notepad))?$'),
  @('notelist', '^(?:(?:show|list|read|see)\s+)?(?:me\s+)?(?:my\s+|all\s+|all my\s+)?notes$|^what are my notes$'),
  @('notedel', '^(?:delete|remove|erase) note #?(\d+)$'),
  @('noteclear', '^(?:clear|delete all|remove all|erase all|erase) (?:my |the )?notes$'),
  @('notefind', '^(?:search|find)\s+(?:in\s+)?(?:my\s+)?notes?\s+(?:for\s+)?(.+)$'),
  @('noteadd', '^(?:note|take a note|make a note|add (?:a )?note|write down|jot down|save (?:a )?note|new note)(?:\s*[:\-]\s*|\s+)(.+)$'),
  @('shortcutadd', '^(?:(?:add|save|create|new|make)\s+(?:a\s+)?)?shortcut\s+(.+?)\s*(?:=>|->|=)\s*(.+)$'),
  @('shortcutadd', '^(?:(?:add|save|create|new|make)\s+(?:a\s+)?)?shortcut\s+(\S+)\s+(https?://\S+|www\.\S+|[a-z]:\\.+)$'),
  @('shortcutlist', '^(?:(?:show|list)\s+)?(?:my\s+)?shortcuts$'),
  @('shortcutdel', '^(?:delete|remove) (?:the )?shortcut (.+)$'),
  @('routineadd', '^(?:(?:add|save|create|new|make)\s+(?:a\s+)?)?routine\s+(.+?)\s*(?:=|:)\s*(.+)$'),
  @('routinelist', '^(?:(?:show|list)\s+)?(?:my\s+)?routines$'),
  @('routinedel', '^(?:delete|remove) (?:the )?routine (.+)$'),
  @('myday', '^(?:start my day|start the day|start my work ?day|good morning routine|morning routine|let''?s start(?: the day)?)$'),
  @('routinerun', '^(?:run|start|do|play)\s+(?:my\s+|the\s+)?(?:routine\s+)?(.+?)(?:\s+routine)?$'),
  @('brief', '^(?:brief me|daily brief|briefing|my day|summary|summari[sz]e my day|plan my day|today''?s plan|what(?:''s| is) (?:on )?(?:my )?(?:plan|day|agenda|schedule)(?: today| for today)?|whats (?:on )?(?:my )?(?:plan|day|agenda|schedule)(?: today| for today)?|what do i have(?: to do)?(?: today)?)$'),
  @('again', '^(?:again|do it again|do that again|repeat that|one more time|same again)$'),
  @('stopjob', '^(?:stop|cancel|abort)(?: the| that| this)?(?: search| job| task| scan| it)?$'),
  @('copylast', '^(?:copy (?:that|it|this|the answer|your answer|your reply|last answer|the reply)|copy)$'),
  @('clipshow', '^(?:what(?:''s| is) (?:in )?(?:my |the )?clipboard|whats (?:in )?(?:my |the )?clipboard|show (?:me )?(?:my |the )?clipboard|clipboard)$'),
  @('pickresult', '^#?(\d{1,2})$'),
  @('resultfolder', '^(?:open |show )?(?:the )?(?:folder|location) (?:of |for )?(?:number |file )?#?(\d{1,2})$'),
  @('resultfolder', '^(?:show|open) #?(\d{1,2}) in (?:the )?(?:folder|explorer|file explorer)$'),
  @('resultfolder', '^where is (?:number |file )?#?(\d{1,2})$'),
  @('findin', '^(?:find|search for|look for|locate|search)\s+(?:me\s+)?(?:my\s+|the\s+|a\s+|all\s+)?(.+?)\s+(?:in|on|inside|under|from)\s+(?:the\s+)?(?:my\s+)?([a-z]:\\.*|[a-z]:|[a-z] drive|desktop|documents|docs|downloads|pictures|photos|videos|music|onedrive|home)(?:\s+folder)?$'),
  @('find', '^(?:find|locate|look for|search (?:my )?(?:pc|computer|laptop|files|drive|disk)(?: for)?|search for (?:a |my |the )?(?:file|folder|document)s?(?: called| named)?|where is (?:my |the )?(?:file|folder|document)(?: called| named)?|where are (?:my |the )?(?:files?|documents?)(?: called| named)?)\s+(?:me\s+)?(?:my\s+|the\s+|a\s+|all\s+)?(.+)$'),
  @('bigfiles', '^(?:what are |show |find |list |show me )?(?:the |my )?(?:biggest|largest|big|large|huge)\s+files(?:\s+(?:in|on)\s+(?:my\s+|the\s+)?(.+?))?(?:\s+folder)?$'),
  @('bigfiles', '^what(?:''s| is) (?:taking|using|eating|filling) (?:up )?(?:all )?(?:my |the )?(?:disk|space|storage|drive)(?: space)?$'),
  @('recent', '^(?:my |show |show my |list |open )?(?:recent|recently (?:opened|used)|last) (?:files|documents|docs)$|^what (?:files )?(?:was i|have i been) working on$'),
  @('dlreport', '^(?:check|clean|clean up|cleanup|scan|tidy|tidy up|analy[sz]e|report on|look at|review)\s+(?:my\s+|the\s+)?downloads?(?:\s+folder)?$|^downloads? (?:report|status|size)$|^how (?:big|full|much) is (?:my )?downloads?(?: folder)?$'),
  @('organize', '^(?:organi[sz]e|sort|arrange|sort out)\s+(?:my\s+|the\s+)?downloads?(?:\s+folder)?$'),
  @('oldinstallers', '^(?:delete|remove|clean|clean up|trash|bin)\s+(?:the\s+|my\s+|all\s+)?(?:old\s+)?(?:installers|setup files|exe files)(?:\s+(?:in|from)\s+(?:my\s+)?downloads)?$'),
  @('oldfiles', '^(?:show|list|find)\s+(?:me\s+)?(?:my\s+|the\s+)?old\s+(?:downloads|files in (?:my )?downloads)$'),
  @('recycle', '^(?:empty|clear|clean)\s+(?:the\s+|my\s+)?(?:recycle bin|recycling bin|trash|bin)$'),
  @('temp', '^(?:clean|clear|delete|empty|remove)\s+(?:up\s+)?(?:the\s+|my\s+)?(?:temp|temporary|tmp|junk)(?:\s+files|\s+folder)?$|^free (?:up )?(?:some )?(?:disk )?space$'),
  @('screenshot', '^(?:take\s+(?:a\s+)?|capture\s+(?:a\s+)?|grab\s+(?:a\s+)?|save\s+(?:a\s+)?)?(?:screenshot|screen ?shot|screen capture|picture of (?:my |the )?screen|snapshot)$|^capture (?:my |the )?screen$'),
  @('snip', '^(?:snip|snipping|clip (?:a )?part of (?:my |the )?screen|screenshot (?:of )?(?:a )?(?:part|area|region)(?: of (?:the )?screen)?)$'),
  @('lock', '^lock(?: (?:my |the )?(?:pc|computer|screen|laptop|windows))?$'),
  @('shutdown', '^(?:shut ?down|turn off|power off|switch off)(?: (?:my |the )?(?:pc|computer|laptop))?$'),
  @('restart', '^(?:restart|reboot)(?: (?:my |the )?(?:pc|computer|laptop))?$'),
  @('cancelshutdown', '^(?:cancel|stop|abort) (?:the )?(?:shut ?down|restart|reboot)$'),
  @('volume', '^(?:turn |make (?:it )?)?(?:the )?(?:volume|sound) (up|down|higher|lower|louder|quieter)$'),
  @('volume', '^(?:turn (?:it )?|make (?:it )?)?(louder|quieter|softer)$'),
  @('volume', '^(?:turn )?(up|down) (?:the )?(?:volume|sound)$'),
  @('volume', '^(mute|unmute)(?: (?:the )?(?:sound|volume|audio|pc|speakers|computer))?$'),
  @('minimize', '^(?:minimi[sz]e (?:all|everything|all windows|all apps)|show (?:me )?(?:the )?desktop|hide (?:all )?(?:my )?windows)$'),
  @('restorewin', '^(?:restore|bring back|undo minimi[sz]e)(?: all)?(?: my)? windows$'),
  @('running', '^(?:what|which) (?:apps|programs|windows|applications) (?:are |do i have )?(?:open|running)(?: now)?$|^(?:list |show )?(?:my )?(?:running|open) (?:apps|programs|windows|applications)$'),
  @('topapps', '^(?:what(?:''s| is)|whats) (?:using|eating|taking|hogging) (?:up )?(?:all )?(?:my |the )?(?:ram|memory|cpu)$|^(?:top|heavy|biggest) (?:apps|processes|programs)$|^why is (?:my |the |this )?(?:pc|computer|laptop) (?:so )?slow$'),
  @('close', '^(?:close|quit|exit|kill)\s+(?:the\s+|my\s+|all\s+)?(.+?)(?:\s+(?:app|window|windows|program))?$'),
  @('sysinfo', '^(?:system info(?:rmation)?|pc info|computer info|pc status|system status|computer status|laptop status|how is my (?:pc|computer|laptop)(?: doing)?|check (?:my )?(?:pc|computer|laptop|system)|(?:my )?pc health|(?:my )?specs|about (?:this|my) (?:pc|computer|laptop))$'),
  @('battery', '{ASK}(?:battery|charge|charging|battery life)(?:\s+(?:level|status|life|percentage|percent))?{TAIL}'),
  @('battery', '^(?:am i|is (?:it|my (?:pc|laptop|computer))) (?:charging|plugged in|on battery)$'),
  @('disk', '{ASK}(?:disk|disk space|storage|free space|space|drive space|hard drive|hard disk|ssd|c drive|drives?)(?:\s+(?:space|free|left|used))?{TAIL}'),
  @('memory', '{ASK}(?:ram|memory|ram usage|memory usage)(?:\s+(?:usage|used|free))?{TAIL}'),
  @('cpu', '{ASK}(?:cpu|processor|cpu usage|cpu load)(?:\s+(?:usage|load|speed))?{TAIL}'),
  @('uptime', '{ASK}(?:uptime|up time){TAIL}'),
  @('uptime', '^how long (?:has )?(?:my |the |this )?(?:pc|computer|laptop) (?:been )?(?:on|running|up)$|^when did (?:my |the )?(?:pc|computer|laptop) (?:start|boot|turn on)$|^last (?:boot|restart)$'),
  @('ip', '{ASK}(?:ip|ip address|local ip|ipv4|ip addr){TAIL}'),
  @('wifi', '{ASK}(?:wifi|wi-fi|wifi name|network|network name|ssid|internet|internet connection|connection)(?:\s+(?:name|status|connection))?{TAIL}'),
  @('wifi', '^am i (?:connected|online)(?: to (?:the )?(?:internet|wifi|wi-fi|network))?$|^is (?:my |the )?(?:internet|wifi|wi-fi|network) (?:working|on|connected|up|down|ok)$|^which wifi(?: am i on| am i connected to)?$'),
  @('pcname', '{ASK}(?:pc name|computer name|hostname|host name|device name|windows version|os version|version of windows){TAIL}'),
  @('pcname', '^(?:what|which) (?:windows|windows version|version of windows) (?:is this|do i have|am i (?:on|using|running))$|^who am i(?: logged in as)?$|^(?:what(?:''s| is) |whats )?my (?:user ?name|windows user|login)$'),
  @('settingspage', '^(?:open\s+|go to\s+|show\s+|change\s+)?(?:the\s+|my\s+)?(wifi|wi-fi|bluetooth|display|screen|sound|audio|volume|apps|installed apps|windows update|update|updates|battery|power|notifications?|privacy|mouse|touchpad|keyboard|typing|storage|date and time|time|language|region|background|wallpaper|themes?|night light|dark mode|colors|printers?|vpn|proxy|default apps|startup apps|accounts?|camera|microphone|mic|ethernet|network|hotspot|focus assist|do not disturb|brightness)\s+settings?$'),
  @('open', '^(open|launch|start|run|go to|load|fire up|bring up|pull up)\s+(?:up\s+)?(?:the\s+|my\s+)?(.+?)(?:\s+(?:app|application|program|website|site|page))?$'),
  @('wiki', '^(?:wiki|wikipedia)\s+(.+)$'),
  @('wiki', '^(?:look up|search|search for) (.+?) (?:on|in) wikipedia$'),
  @('translate', '^translate\s+(.+)$'),
  @('maps', '^(?:map of|maps?|directions to|navigate to|route to)\s+(.+)$'),
  @('weather', '^(?:what(?:''s| is) the |whats the |how is the |how''s the )?weather(?: like)?(?: (?:today|now|tomorrow|forecast|this week))?(?: (?:in|at|for) (.+?))?$'),
  @('weather', '^(?:will it|is it going to) (?:rain|snow)(?: today| tomorrow)?(?: (?:in|at) (.+?))?$'),
  @('news', '^(?:show me |what(?:''s| is) (?:in )?the |whats (?:in )?the |any )?(?:latest |today''s |todays )?(?:news|headlines)(?: today)?(?: (?:about|on) (.+))?$'),
  @('numbase', '^(?:convert\s+)?(\d+)\s+(?:to|in|into)\s+(hex|hexadecimal|binary|bin|octal|oct)$'),
  @('numbase2', '^(?:convert\s+)?(0x[0-9a-f]+|0b[01]+)\s+(?:to|in|into)\s+(?:decimal|dec|number|int)$'),
  @('convert', '^(?:convert\s+|how much is\s+|what is\s+|what''s\s+|whats\s+)?(-?\d+(?:\.\d+)?)\s*(?:degrees?\s+)?([a-z/2]+)\s+(?:to|in|into|as)\s+(?:degrees?\s+)?([a-z/2]+)$'),
  @('howmany', '^how many ([a-z/2]+) (?:are |is )?(?:in|make|per) (?:a |an |one )?(\d+(?:\.\d+)?\s*)?([a-z/2]+)$'),
  @('percent', '^(?:what(?:''s| is) |whats |calc |calculate )?(\d+(?:\.\d+)?)\s*(?:%|percent)\s+of\s+(\d+(?:\.\d+)?)$'),
  @('percentof', '^(?:what(?:''s| is) |whats )?(\d+(?:\.\d+)?)\s+(?:is\s+)?(?:what|how many)\s+(?:percent|%|percentage)\s+of\s+(\d+(?:\.\d+)?)$'),
  @('pctchange', '^(?:what(?:''s| is) the )?percent(?:age)? (?:change|increase|decrease|difference) (?:from|between) (\d+(?:\.\d+)?) (?:to|and) (\d+(?:\.\d+)?)$'),
  @('power', '^(?:what(?:''s| is) |whats |calc |calculate )?(-?\d+(?:\.\d+)?)\s*(?:\^|\*\*|to the power of|to the power|raised to)\s*(-?\d+(?:\.\d+)?)$'),
  @('sqrt', '^(?:what(?:''s| is) |whats |calc )?(?:the )?(?:sqrt|square root(?: of)?|root of)\s*\(?(\d+(?:\.\d+)?)\)?$'),
  @('hash', '^(md5|sha1|sha256|sha512)\s+(.+)$'),
  @('daysuntil', '^(?:how many )?days (?:until|till|til|to|left until|left till|left for|before) (.+)$'),
  @('daysuntil', '^how long (?:until|till|til|is it until|to) (.+)$'),
  @('daysuntil', '^when is (christmas|xmas|new year''?s?(?: day| eve)?|valentine''?s?(?: day)?|halloween)$'),
  @('datein', '^(?:what(?:''s| is) the date |whats the date |what day is it |what day will it be )?(?:in )?(\d+) (days?|weeks?|months?|years?) (?:from (?:now|today)|later|after today)$'),
  @('datein', '^(?:what(?:''s| is) the |whats the )?date in (\d+) (days?|weeks?|months?|years?)$'),
  @('weekday', '^what day (?:of the week )?(?:is|was|will be|falls on|does) (.+?)(?: fall on| be)?$'),
  @('daysbetween', '^(?:how many )?days between (.+?) and (.+)$'),
  @('weeknum', '^(?:what )?week (?:number )?(?:is it|of the year|number)(?: today| now)?$|^which week is (?:it|this)(?: now)?$|^what week is it$'),
  @('coin', '^(?:flip|toss) (?:a )?coin$|^heads or tails$'),
  @('dice', '^(?:roll )?(?:a |the )?(?:dice|die)$|^roll (?:a |the )?(?:dice|die)$'),
  @('randnum', '^(?:pick|choose|give me|generate) (?:a )?(?:random )?number(?: between| from)? (\d+) (?:and|to|-) (\d+)$'),
  @('choose', '^(?:choose|pick|decide)(?: between)?:?\s+(.+?)\s+or\s+(.+)$'),
  @('choose', '^should i (.+?) or (.+)$'),
  @('aboutme', '^(?:are you (?:an? )?(?:ai|robot|bot|chatgpt|gemini|copilot|real|human|alive|smart)|what (?:kind|type) of (?:ai|brain) are you|how do you work|how smart are you|where do your answers come from|do you use (?:the )?(?:internet|chatgpt|gemini|ai))$')
)
$Intents = New-Object System.Collections.ArrayList
foreach ($pair in $IntentList) {
  $rxText = [string]$pair[1]
  foreach ($rk in $RxParts.Keys) { $rxText = $rxText.Replace($rk, $RxParts[$rk]) }
  try {
    $rxObj = New-Object System.Text.RegularExpressions.Regex($rxText, ([System.Text.RegularExpressions.RegexOptions]'IgnoreCase, CultureInvariant'))
    $null = $Intents.Add(@{ name = [string]$pair[0]; re = $rxObj })
  } catch { Write-Log ('Bad pattern for ' + $pair[0] + ': ' + $_.Exception.Message) }
}

$PartCheck['8'] = $true   # ===== end of PART 8 of 9 =====
# ---------- understanding a message ----------
$SafetyRx = '(kill myself|suicide|want to die|end my life|hurt myself|self harm)'
function Strip-Polite($s) {
  $x = ([string]$s).Trim()
  $x = $x.Replace([string][char]0x2019, "'").Replace([string][char]0x2018, "'")
  $dn = [regex]::Escape(([string]$cfg.dogName).ToLower())
  for ($k = 0; $k -lt 3; $k++) {
    $before = $x
    $x = $x -replace ('^(?:hey |hi |ok |okay |yo )?(?:' + $dn + '|buddy|doggy|puppy|pup)\s*[,:!]?\s+'), ''
    $x = $x -replace '^(?:please|pls|plz|kindly|can you please|could you please|would you please|can you|could you|would you|will you|can u|could u|i want you to|i need you to|i would like you to|i''d like you to|help me|go ahead and|quickly)\s+', ''
    $x = $x -replace '\s+(?:please|pls|plz|for me|right now|now please|thanks|thank you)$', ''
    if ($x -eq $before) { break }
  }
  return $x.Trim()
}
$StepVerbs = 'open|launch|start|remind|search|google|find|add|todo|note|play|sit|lock|take|show|tell|set|timer|focus|close|calc|convert|mute|volume|brief|check|run'
function Split-Steps($t) {
  if ($t -match '^(?:remind|note|take a note|write down|jot down|learn|teach|remember|routine|add routine|create routine|new routine|save routine|make routine|shortcut|add shortcut|say|repeat|json|format json|pretty json|base64|url|todo|add todo|to-do|translate|search|google|youtube|wiki|wikipedia)\b') { return @($t) }
  if ($t -match '^add\s+.+\s+to\s+(?:my\s+)?(?:todo|to-do|task)') { return @($t) }
  if ($t -notmatch ('^(?:' + $StepVerbs + '|go to|launch|lock|mute|take|empty|clean|organi[sz]e|delete|show)\b') -and $t -notmatch ';') { return @($t) }
  $rx = '\s*;\s*|,?\s+and then\s+|,?\s+then\s+|,?\s+and\s+(?=(?:' + $StepVerbs + ')\b)'
  return @([regex]::Split($t, $rx, 'IgnoreCase') | Where-Object { $_.Trim() -ne '' } | ForEach-Object { $_.Trim() })
}
function Match-Intent($t, $depth) {
  foreach ($it in $Intents) {
    $mm = $it.re.Match($t)
    if (-not $mm.Success) { continue }
    $m = @{}
    for ($gi = 0; $gi -lt $mm.Groups.Count; $gi++) { $m[$gi] = $mm.Groups[$gi].Value }
    $rep = $null
    try { $rep = & ('Skill-' + $it.name) $m $t $depth }
    catch { Write-Log $_; $rep = New-Reply ('Oops, something went wrong while doing that: ' + $_.Exception.Message) $null }
    if ($rep -is [array]) { $rep = @($rep | Where-Object { $_ -is [hashtable] }) | Select-Object -Last 1 }
    if ($null -ne $rep) { return $rep }
  }
  return $null
}
$UnknownMark = 'I do not know that one yet'
function Is-Unknown($rep) {
  if ($null -eq $rep) { return $true }
  $tx = [string]$rep.text
  return ($tx.StartsWith($UnknownMark) -or $tx.StartsWith('I could not find my knowledge.txt'))
}
$Examples = @('open notepad', 'open downloads', 'find resume', 'find tax pdf', 'find report in downloads', 'biggest files', 'recent files',
  'check my downloads', 'organize downloads', 'delete old installers', 'pc status', 'battery', 'disk space', 'memory usage', 'cpu usage',
  'what is using my memory', 'ip address', 'wifi', 'open apps', 'close notepad', 'take a screenshot', 'lock my pc', 'volume up', 'mute',
  'minimize all', 'brief me', 'start my day', 'note buy milk', 'notes', 'export notes', 'teach: question = answer', 'what do you remember',
  'add shortcut jira = https://...', 'shortcuts', 'add routine morning = open outlook; open teams', 'routines', 'remind me to stretch in 20 minutes',
  'timer 5', 'todo send report', 'todos', 'focus 25', 'i drank water', 'convert 5 km to miles', '15% of 2400', 'days until christmas',
  'what day is 25 dec', 'flip a coin', 'roll a dice', 'translate hello to hindi', 'wikipedia python', 'weather', 'news', 'search best laptop',
  'joke', 'dance', 'help', 'empty recycle bin', 'clean temp files', 'copy that', 'clipboard', 'topics', 'settings', 'wifi settings',
  'bluetooth settings', 'restart', 'shut down', 'uptime', 'sit', 'play', 'feed', 'sleep', 'password 16', 'uuid', 'calc 12*7')
$ExampleWords = @{}
foreach ($ex in $Examples) { $ExampleWords[$ex] = @(Get-Words $ex) }
$Vocab = @{}
foreach ($ex in $Examples) { foreach ($wd in (($ex.ToLower() -replace '[^a-z ]', ' ') -split ' ')) { if ($wd.Length -ge 4) { $Vocab[$wd] = $true } } }
foreach ($wd in @('remind', 'reminder', 'minutes', 'hours', 'search', 'google', 'youtube', 'launch', 'start', 'calculate', 'convert', 'delete',
  'remove', 'water', 'drank', 'focus', 'screenshot', 'battery', 'downloads', 'documents', 'desktop', 'pictures', 'folder', 'files', 'notepad',
  'calculator', 'chrome', 'outlook', 'teams', 'excel', 'word', 'powerpoint', 'explorer', 'terminal', 'settings', 'memory', 'remember', 'forget')) { $Vocab[$wd] = $true }
function Fix-Typos($t) {
  $out = @()
  $changed = $false
  foreach ($wd in (([string]$t).ToLower() -split '\s+')) {
    if ($wd.Length -ge 4 -and $wd -match '^[a-z]+$' -and -not $Vocab.ContainsKey($wd)) {
      $fixed = $null
      foreach ($vk in $Vocab.Keys) { if (Same-Word $wd $vk) { $fixed = $vk; break } }
      if ($null -ne $fixed) { $out += $fixed; $changed = $true; continue }
    }
    $out += $wd
  }
  if (-not $changed) { return $null }
  return ($out -join ' ')
}
function Get-Suggestions($t) {
  $qWords = @(Get-Words $t)
  if ($qWords.Count -eq 0) { return @() }
  $scored = @()
  foreach ($ex in $Examples) {
    $eWords = @($ExampleWords[$ex])
    if ($eWords.Count -eq 0) { continue }
    $hit = Get-MatchScore $eWords $qWords
    if ($hit -le 0) { continue }
    $scored += [pscustomobject]@{ ex = $ex; score = ($hit + (Get-MatchScore $qWords $eWords)) }
  }
  return @($scored | Sort-Object -Property score -Descending | Select-Object -First 3 | ForEach-Object { $_.ex })
}
function Unknown-Reply($t) {
  $lines = @($UnknownMark + ' ' + $EM.think)
  $sugg = @(Get-Suggestions $t)
  if ($sugg.Count -gt 0) { $lines += ('Did you mean:  ' + ($sugg -join '   |   ')) }
  $lines += ''
  $lines += 'You can teach me, and I will remember it:'
  $lines += ('  teach: ' + (Short-Text $t 40) + ' = <the answer>')
  $lines += 'Or type  help  to see what I can do, or search the web:'
  return (New-Reply ($lines -join "`n") $t)
}
function Get-Reply($rawText) {
  $rep = Get-ReplyCore $rawText 0
  if ($rep -is [array]) { $rep = @($rep | Where-Object { $_ -is [hashtable] }) | Select-Object -Last 1 }
  return $rep
}
function Get-ReplyCore($rawText, $depth) {
  $orig = ([string]$rawText).Trim()
  if ($orig -eq '') { return (New-Reply 'Woof?' $null) }
  if ($orig.ToLower() -match $SafetyRx) { return (Get-QuickReply $orig) }
  if ($depth -eq 0 -and $null -ne $BRAIN.confirm) {
    $cr = Check-Confirm $orig.ToLower()
    if ($null -ne $cr) { return $cr }
  }
  $low0 = $orig.ToLower()
  $t = $orig
  if ($low0 -notmatch '^(base64|url ?(en|de)code|json|format json|pretty json|say|repeat|md5|sha1|sha256|sha512|hash)\b') { $t = ($orig -replace '[\s\.!\?]+$', '') }
  $t = Strip-Polite $t
  if ($t -eq '') { $t = $orig }

  # several things in one message ("open outlook and remind me in 10 minutes to call Sam")
  if ($depth -lt 2) {
    $steps = @(Split-Steps $t)
    if ($steps.Count -gt 1) { return (Run-Steps $steps $depth ('On it! ' + $steps.Count + ' things:')) }
  }

  # my skills (PC jobs, files, memory, notes, maths, dates...)
  $rep = Match-Intent $t $depth
  if ($null -ne $rep) { return $rep }

  # quick commands, dog tricks, coding notes
  $q = Get-QuickReply $t
  if ($q -is [array]) { $q = @($q | Where-Object { $_ -is [hashtable] }) | Select-Object -Last 1 }
  $isKb = ($null -ne $q -and ([string]$q.text).StartsWith([string]$EM.book))
  $isUnknown = Is-Unknown $q
  if ($isKb -or $isUnknown) {
    $hit = Find-Fact $t
    if ($null -ne $hit -and ($isUnknown -or $hit.score -ge 1.6)) { return (Fact-Reply $hit) }
  }
  if (-not $isUnknown) { return $q }

  # maybe a typo? try again with the closest words I know
  if ($depth -eq 0) {
    $fixed = Fix-Typos $t
    if ($null -ne $fixed) {
      $r2 = Get-ReplyCore $fixed 1
      if (-not (Is-Unknown $r2)) { $r2.text = '(I think you meant: ' + $fixed + ')' + "`n" + [string]$r2.text; return $r2 }
    }
  }
  return (Unknown-Reply $t)
}

function Get-HelpText {
  return @'
I am your own offline assistant - no ChatGPT, no Gemini, nothing leaves this PC. Talk to me in plain words. You can also ask several things at once: "open outlook and remind me in 10 minutes to call Sam".

MY DAY:  brief me  |  start my day  |  todo send report  |  todos  |  done 1  |  remind me to stretch in 20 minutes  |  remind me to join standup at 9:30 am  |  timer 5  |  focus 25
WATER:  I drank water  |  water  |  water every 30  |  water goal 8
OPEN THINGS:  open notepad  |  open excel  |  open downloads  |  open wifi settings  |  open https://...  |  close notepad  |  open apps
FILES:  find resume  |  find tax pdf  |  find report in downloads  |  recent files  |  biggest files  |  then:  open 1  /  folder 1
CLEAN UP:  check my downloads  |  organize downloads  |  delete old installers  |  clean temp files  |  empty recycle bin   (I always ask first)
MY PC:  pc status  |  battery  |  disk space  |  memory usage  |  what is using my memory  |  cpu  |  ip address  |  wifi  |  uptime
PC ACTIONS:  take a screenshot  |  snip  |  lock my pc  |  volume up / down  |  mute  |  minimize all  |  restart  |  shut down
TEACH ME:  teach: standup time = 10 am  |  remember that my car is on level 3  |  what do you remember  |  forget 2
NOTES:  note call the bank  |  notes  |  find in notes bank  |  delete note 1  |  export notes
SHORTCUTS:  add shortcut jira = https://jira.example.com  ->  open jira
ROUTINES:  add routine morning = open outlook; open teams; brief me  ->  start my day  (or  run morning)
MATHS:  calc (12+8)*3  |  15% of 2400  |  2^10  |  sqrt 144  |  5 km to miles  |  100 f to c  |  2 gb to mb  |  255 to hex
DATES:  days until christmas  |  what day is 25 dec  |  date in 30 days  |  what week is it
CODING:  ask in your own words (python read file, git undo commit)  |  topics  |  uuid  |  password 20  |  base64 encode hi  |  json {"a":1}  |  sha256 text
WEB (opens your browser):  search ...  |  youtube ...  |  wikipedia ...  |  translate hello to hindi  |  weather  |  news  |  maps ...
FUN AND DOG:  joke  |  dog fact  |  flip a coin  |  roll a dice  |  sit, roll over, jump, spin, shake, dance, play dead, bark, play, feed, sleep
OTHER:  copy that  |  clipboard  |  again  |  new chat  |  settings  |  talk on / off  |  size large
Tip: press Windows + H in the message box to talk instead of typing.
'@
}
# ---------- chat window ----------
function Reset-Chat {
  $BRAIN.confirm = $null
  if ($null -ne $UI.chatList) { $UI.chatList.Children.Clear() }
  Add-ChatMessage 'dog' ('Fresh start! What can I do for you, ' + $cfg.userName + '? ' + $EM.paw) $null
}
function Update-ChatStatus {
  if ($null -eq $UI.chat) { return }
  try {
    Update-DayCounter
    $UI.chat.Title = 'Chat with ' + $cfg.dogName
    $UI.chatTitle.Text = $cfg.dogName
    $st = 'Happy ' + [int]$cfg.happiness + '%  |  Fullness ' + [int]$cfg.fullness + '%  |  Water ' + $cfg.glasses + '/' + $cfg.waterGoal
    if ($PET.focusOn) { $st += '  |  Focus ' + [Math]::Ceiling(($PET.focusUntil - [datetime]::Now).TotalMinutes) + ' min left' }
    $UI.chatStatus.Text = $st
    if ($null -ne $UI.chatBrain) { $UI.chatBrain.Text = Get-BrainText }
  } catch { Write-Log $_ }
}
function Send-Chat($forcedText) {
  $txt = [string]$forcedText
  if ([string]::IsNullOrWhiteSpace($txt)) { $txt = $UI.chatInput.Text; $UI.chatInput.Text = '' }
  if ([string]::IsNullOrWhiteSpace($txt)) { return }
  $txt = $txt.Trim()
  $lt = ($txt.ToLower() -replace '[\s\.!\?]+$', '')
  if ($lt -match '^(new chat|clear chat|reset chat|start over|forget (it|that))$') { Reset-Chat; return }
  Add-ChatMessage 'user' $txt $null
  $reply = $null
  try { $reply = Get-Reply $txt } catch { Write-Log $_; $reply = New-Reply ('Oops, my brain hiccuped: ' + $_.Exception.Message) $null }
  if ($reply -is [array]) { $reply = @($reply | Where-Object { $_ -is [hashtable] }) | Select-Object -Last 1 }
  if ($lt -notmatch '^(again|do it again|do that again|repeat that|one more time|same again|yes|y|no|n|ok|okay)$') { $BRAIN.lastCmd = $txt }
  if ($null -ne $reply -and $reply.text) {
    $BRAIN.lastReply = [string]$reply.text
    Add-ChatMessage 'dog' $reply.text $reply.web
    if ($null -ne $JOB.bubble -and $null -ne $UI.chatList) {
      # keep the "working on it..." line below my answer
      $UI.chatList.Children.Remove($JOB.bubble)
      $null = $UI.chatList.Children.Add($JOB.bubble)
      $UI.chatScroll.ScrollToEnd()
    }
    if (-not $PET.action -and $PET.state -ne 'held') { Do-Action 'talk' 1.4 }
    Speak-Text $reply.text $false
  }
  Update-ChatStatus
}
function Build-Chat {
  [xml]$chatXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Chat" Width="600" Height="740" MinWidth="380" MinHeight="440"
        WindowStartupLocation="CenterScreen" Background="#1B1B22" FontFamily="Segoe UI" FontSize="14">
  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <Border Grid.Row="0" Background="#26262F" Padding="10,8" BorderBrush="#33333D" BorderThickness="0,0,0,1">
      <StackPanel Orientation="Horizontal">
        <Border Width="48" Height="48" CornerRadius="24" Background="#3A3A46">
          <TextBlock x:Name="AvatarText" FontSize="28" HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Border>
        <StackPanel Margin="10,0,0,0" VerticalAlignment="Center">
          <TextBlock x:Name="ChatTitle" Text="Buddy" Foreground="White" FontSize="17" FontWeight="SemiBold"/>
          <TextBlock x:Name="ChatStatus" Text="" Foreground="#A0A0B0" FontSize="12"/>
          <TextBlock x:Name="ChatBrain" Text="" Foreground="#9FB4FF" FontSize="12"/>
        </StackPanel>
      </StackPanel>
    </Border>
    <ScrollViewer x:Name="ChatScroll" Grid.Row="1" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
      <StackPanel x:Name="ChatList" Margin="10,8,10,8"/>
    </ScrollViewer>
    <WrapPanel x:Name="QuickBar" Grid.Row="2" Margin="8,4,8,0"/>
    <Grid Grid.Row="3" Margin="8,8,8,2">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="Auto"/>
      </Grid.ColumnDefinitions>
      <TextBox x:Name="ChatInput" Grid.Column="0" MinHeight="40" MaxHeight="140" Padding="8,6" Background="#2A2A33"
               Foreground="White" CaretBrush="White" BorderBrush="#444452" FontSize="14"
               VerticalContentAlignment="Center" TextWrapping="Wrap" AcceptsReturn="True" VerticalScrollBarVisibility="Auto"/>
      <Button x:Name="SendBtn" Grid.Column="1" Content="Send" Margin="8,0,0,0" Padding="18,6"
              Background="#4A6CF7" Foreground="White" BorderThickness="0" FontWeight="SemiBold"/>
    </Grid>
    <TextBlock Grid.Row="4" Margin="12,0,8,8" FontSize="11" Foreground="#77778A"
               Text="Enter = send   |   Shift+Enter = new line   |   Windows+H = talk instead of typing"/>
  </Grid>
</Window>
'@
  $cw = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $chatXaml))
  $UI.chat = $cw
  $UI.chatList = $cw.FindName('ChatList')
  $UI.chatScroll = $cw.FindName('ChatScroll')
  $UI.chatInput = $cw.FindName('ChatInput')
  $UI.chatTitle = $cw.FindName('ChatTitle')
  $UI.chatStatus = $cw.FindName('ChatStatus')
  $UI.chatBrain = $cw.FindName('ChatBrain')
  $cw.FindName('AvatarText').Text = $EM.dog

  $quick = $cw.FindName('QuickBar')
  foreach ($qb in @('Brief me|brief me', 'Help|help', 'Find a file|find ', 'I drank water|i drank water', 'To-dos|todos', 'Notes|notes',
                    'PC status|pc status', 'Screenshot|take a screenshot', 'Check Downloads|check my downloads', 'Joke|joke', 'New chat|new chat')) {
    $pair = $qb -split '\|'
    $b = New-Object System.Windows.Controls.Button
    $b.Content = $pair[0]
    $b.Tag = $pair[1]
    $b.Margin = New-Thick 3 3 3 3
    $b.Padding = New-Thick 10 3 10 3
    $b.FontSize = 12
    $b.Background = New-Brush '#33333F'
    $b.Foreground = New-Brush '#FFFFFF'
    $b.BorderThickness = New-Thick 0 0 0 0
    $b.Cursor = [System.Windows.Input.Cursors]::Hand
    $b.Add_Click({
      param($sender, $ev)
      try {
        $tg = [string]$sender.Tag
        if ($tg.EndsWith(' ')) { $UI.chatInput.Text = $tg; $UI.chatInput.CaretIndex = $tg.Length; $null = $UI.chatInput.Focus() }
        else { Send-Chat $tg }
      } catch { Write-Log $_ }
    })
    $null = $quick.Children.Add($b)
  }

  $cw.FindName('SendBtn').Add_Click({ try { Send-Chat $null } catch { Write-Log $_ } })
  $UI.chatInput.Add_PreviewKeyDown({
    param($sender, $ev)
    if ($ev.Key -eq [System.Windows.Input.Key]::Enter -and -not ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Shift)) {
      $ev.Handled = $true
      try { Send-Chat $null } catch { Write-Log $_ }
    }
  })
  $cw.Add_Closing({ param($sender, $ev) if (-not $UI.quitting) { $ev.Cancel = $true; $sender.Hide() } })

  Add-ChatMessage 'dog' ('Hi ' + $cfg.userName + '! I am ' + $cfg.dogName + ' ' + $EM.dog + "`n" + ' I can open apps, find files, check your PC, tidy Downloads, keep notes, remind you, and learn what you teach me.' + "`n`n" + 'Try:  brief me   |   find resume   |   pc status   |   open downloads   |   teach: standup time = 10 am' + "`n" + 'Type  help  to see everything.') $null
}

# ---------- menu entries for the brain ----------
function Ask-TeachMe {
  $q = [Microsoft.VisualBasic.Interaction]::InputBox('What should I learn? (the question or the name of the thing)' + "`n`n" + 'Example:  standup time', ('Teach ' + $cfg.dogName), '')
  if ([string]::IsNullOrWhiteSpace($q)) { return }
  $a = [Microsoft.VisualBasic.Interaction]::InputBox(('And the answer for "' + $q + '"?') + "`n`n" + 'Example:  10:00 am, every weekday', ('Teach ' + $cfg.dogName), '')
  if ([string]::IsNullOrWhiteSpace($a)) { return }
  $msg = Add-Fact $q $a $false
  Say (Short-Text $msg 110) 6
}
function Ask-FindFile {
  $q = [Microsoft.VisualBasic.Interaction]::InputBox('What file are you looking for? (part of its name, e.g.  resume  or  tax pdf)', 'Find a file', '')
  if ([string]::IsNullOrWhiteSpace($q)) { return }
  Open-Chat
  Send-Chat ('find ' + $q)
}
try {
  $miBrain = New-Entry 'My brain' $null
  $null = Add-Entry $miBrain 'Brief me (my day)' { Open-Chat; Send-Chat 'brief me' }
  $null = Add-Entry $miBrain 'Find a file...' { try { Ask-FindFile } catch { Write-Log $_ } }
  $null = Add-Entry $miBrain 'Teach me something...' { try { Ask-TeachMe } catch { Write-Log $_ } }
  $null = Add-Entry $miBrain 'What I remember' { Open-Chat; Send-Chat 'what do you remember' }
  $null = Add-Entry $miBrain 'My notes' { Open-Chat; Send-Chat 'notes' }
  Add-Sep $miBrain
  $null = Add-Entry $miBrain 'PC status' { Open-Chat; Send-Chat 'pc status' }
  $null = Add-Entry $miBrain 'Check my Downloads' { Open-Chat; Send-Chat 'check my downloads' }
  $null = Add-Entry $miBrain 'Take a screenshot' { try { $file = Take-Screenshot; Say ('Snap! Saved to Pictures\DogPet Screenshots ' + $EM.star) 5 } catch { Write-Log $_ } }
  $menu.Items.Insert(($menu.Items.IndexOf($miChat) + 1), $miBrain)
} catch { Write-Log $_ }
try {
  if ($null -ne $Tray -and $null -ne $Tray.ContextMenuStrip) {
    $tsi = New-Object System.Windows.Forms.ToolStripMenuItem('Brief me (my day)')
    $tsi.Add_Click({ Open-Chat; Send-Chat 'brief me' })
    $Tray.ContextMenuStrip.Items.Insert(1, $tsi)
  }
} catch { Write-Log $_ }

# ---------- little helper that keeps an eye on the battery ----------
$watcher = New-Object System.Windows.Threading.DispatcherTimer
$watcher.Interval = [TimeSpan]::FromSeconds(60)
$watcher.Add_Tick({
  try {
    $pwr = [System.Windows.Forms.SystemInformation]::PowerStatus
    if ([int]$pwr.BatteryChargeStatus -eq 128) { return }
    $pct = [int]([double]$pwr.BatteryLifePercent * 100)
    if ([string]$pwr.PowerLineStatus -ne 'Online' -and $pct -le 15 -and ([datetime]::Now - $BRAIN.battWarned).TotalMinutes -gt 20) {
      $BRAIN.battWarned = [datetime]::Now
      if (-not $PET.pending -and -not $PET.hidden) {
        Set-State 'sit' 10
        Say ('Battery is only ' + $pct + '%! Please plug in the charger ' + $EM.bell) 10
        Notify-User ('Battery is at ' + $pct + '% - please plug in the charger.')
      }
    }
  } catch { }
})
# ---------- pet styles (fur colours) ----------
$StyleFile = Join-Path $dataDir 'style.txt'
$STYLE = @{ ready = $false; shapes = (New-Object System.Collections.ArrayList); orig = @{}; blaze = $null; current = 'golden'; items = @{} }
$PetStyleNames = [ordered]@{
  golden = 'Golden retriever'; black = 'Black Labrador'; white = 'White dog'; chocolate = 'Chocolate brown'; collie = 'Black and white (Border Collie)'
}
# keys: G + first colour = a fur gradient, 6 letters = one plain colour of the golden dog
$PetStyles = @{
  golden = @{}
  black = @{
    GF0C27F = @('#45403D', '#2F2B29', '#1E1B1A'); GF6D29A = @('#55504C', '#36322F'); GFBE9C6 = @('#4A4542', '#2F2B29')
    B07636 = '#171413'; C98B47 = '#2A2624'; A86E30 = '#000000'; EBC88E = '#3A3532'; F9DDA8 = '#6A6460'; '8A5A2E' = '#0D0B0A'; '3A3A46' = '#C0392B'
  }
  white = @{
    GF0C27F = @('#FFFFFF', '#F3F0E9', '#E2DCD0'); GF6D29A = @('#FFFFFF', '#EFEBE2'); GFBE9C6 = @('#FFFFFF', '#F7F4EE')
    B07636 = '#D4CDBF'; C98B47 = '#E6E0D4'; A86E30 = '#A79E8E'; EBC88E = '#F8F6F1'; F9DDA8 = '#FFFFFF'; '8A5A2E' = '#8F877B'
  }
  chocolate = @{
    GF0C27F = @('#86543A', '#6B3F25', '#55301B'); GF6D29A = @('#96664A', '#73472C'); GFBE9C6 = @('#9C6E52', '#7E5238')
    B07636 = '#4B2A17'; C98B47 = '#5F3820'; A86E30 = '#331A0C'; EBC88E = '#8E6146'; F9DDA8 = '#A8795C'; '8A5A2E' = '#2A1408'
  }
  collie = @{
    GF0C27F = @('#3A3534', '#262221', '#181514'); GF6D29A = @('#45403E', '#2A2625'); GFBE9C6 = @('#FFFFFF', '#F1EEE8')
    B07636 = '#141110'; C98B47 = '#221E1D'; A86E30 = '#000000'; EBC88E = '#F5F3EF'; F9DDA8 = '#5A5451'; '8A5A2E' = '#9B948A'; '3A3A46' = '#C0392B'
  }
}
function To-Color($hex) {
  $cv = [System.Windows.Media.ColorConverter]::ConvertFromString([string]$hex)
  return [System.Windows.Media.Color]$cv
}
function Collect-PetShapes($el) {
  if ($null -eq $el) { return }
  if ($el -is [System.Windows.Shapes.Shape]) { $null = $STYLE.shapes.Add($el); return }
  if ($el -is [System.Windows.Controls.Panel]) { foreach ($ch in $el.Children) { Collect-PetShapes $ch }; return }
  if ($el -is [System.Windows.Controls.Decorator]) { Collect-PetShapes $el.Child }
}
function Init-PetStyles {
  Collect-PetShapes $W.DrawnDog
  foreach ($sh in $STYLE.shapes) {
    $key = ''
    $fb = $sh.Fill
    if ($fb -is [System.Windows.Media.SolidColorBrush]) { $key = $fb.Color.ToString().Substring(3) }
    elseif ($fb -is [System.Windows.Media.GradientBrush] -and $fb.GradientStops.Count -gt 0) { $key = 'G' + $fb.GradientStops[0].Color.ToString().Substring(3) }
    $sh.Tag = $key
    if ($key -ne '' -and -not $STYLE.orig.ContainsKey($key)) { $STYLE.orig[$key] = $fb }
  }
  # the white stripe on the face of a Border Collie (hidden for the other styles)
  try {
    $headCanvas = $W.DEye.Parent.Parent
    $bz = New-Object System.Windows.Shapes.Path
    $bz.Data = [System.Windows.Media.Geometry]::Parse('M162,7 C165,6 168,6 170,8 C169,11 168,14 168,18 C168,21 169,24 171,26 L167,27 C165,22 164,16 163,11 C162.5,9.5 162,8 162,7 Z')
    $bz.Fill = New-Object System.Windows.Media.SolidColorBrush (To-Color '#FFFFFF')
    $bz.Visibility = 'Collapsed'
    $bz.Tag = 'blaze'
    $headCanvas.Children.Insert(1, $bz)
    $STYLE.blaze = $bz
  } catch { Write-Log $_ }
  $STYLE.ready = $true
}
function New-PetBrush($val, $orig) {
  $vals = @($val)
  if ($orig -is [System.Windows.Media.GradientBrush]) {
    $nb = $orig.Clone()
    for ($i = 0; $i -lt $nb.GradientStops.Count; $i++) { $nb.GradientStops[$i].Color = To-Color $vals[[Math]::Min($i, $vals.Count - 1)] }
    return $nb
  }
  return (New-Object System.Windows.Media.SolidColorBrush (To-Color $vals[0]))
}
function Set-PetStyle($name, $quiet) {
  if (-not $PetStyles.ContainsKey([string]$name)) { return $false }
  if (-not $STYLE.ready) { Init-PetStyles }
  $pal = $PetStyles[[string]$name]
  foreach ($sh in $STYLE.shapes) {
    $key = [string]$sh.Tag
    if ($key -eq '' -or -not $STYLE.orig.ContainsKey($key)) { continue }
    if ($pal.ContainsKey($key)) { $sh.Fill = New-PetBrush $pal[$key] $STYLE.orig[$key] } else { $sh.Fill = $STYLE.orig[$key] }
  }
  if ($null -ne $STYLE.blaze) { if ($name -eq 'collie') { $STYLE.blaze.Visibility = 'Visible' } else { $STYLE.blaze.Visibility = 'Collapsed' } }
  $STYLE.current = [string]$name
  try { Set-Content -Path $StyleFile -Value ([string]$name) -Encoding ASCII } catch { }
  foreach ($sk in @($STYLE.items.Keys)) { $STYLE.items[$sk].IsChecked = ($sk -eq $name) }
  if (-not $quiet) { Do-Action 'happy' 1.5; Say ('Woof! How do I look as a ' + $PetStyleNames[[string]$name] + '? ' + $EM.paw) 5 }
  return $true
}
function Get-StyleListText {
  $lines = @('I can look like this (now: ' + $PetStyleNames[$STYLE.current] + '):')
  foreach ($sk in $PetStyleNames.Keys) { $lines += ('- ' + $PetStyleNames[$sk]) }
  $lines += ''
  $lines += 'Say for example:  be a black lab  |  style white  |  style chocolate  |  style collie  |  style golden'
  $lines += 'Or right-click me > Pet style.'
  return ($lines -join "`n")
}
function Skill-petstyle($m, $t, $depth) {
  $wd = ([string]$m[1]).ToLower()
  $key = $null
  if ($wd -match 'golden|gold|retriever|yellow|original|normal|default') { $key = 'golden' }
  elseif ($wd -match 'collie|black and white|black & white|black white|white and black|patch') { $key = 'collie' }
  elseif ($wd -match 'choco|brown') { $key = 'chocolate' }
  elseif ($wd -match 'white|samoyed|snow') { $key = 'white' }
  elseif ($wd -match 'black|lab|dark') { $key = 'black' }
  if ($null -eq $key) { return (New-Reply (Get-StyleListText) $null) }
  $null = Set-PetStyle $key $true
  Do-Action 'happy' 1.5
  return (New-Reply ('Woof! I am a ' + $PetStyleNames[$key] + ' now! ' + $EM.paw + '  (Right-click me > Pet style to change again.)') $null)
}
try {
  foreach ($rxText in @(
    '^(?:(?:change|switch|set)\s+(?:your\s+|the\s+|my\s+)?(?:pet\s+|dog\s+)?(?:style|colou?r|fur|coat|look|breed)|(?:pet|dog)\s+(?:styles?|colou?rs?|breeds?)|styles?)\b(?:\s+(?:to|into|as))?\s*(.*)$',
    '^(?:be|become|turn into|turn|make yourself|change into|change to|you are)\s+(?:a\s+|an\s+)?((?:golden|black|white|chocolate|brown|samoyed|collie|border collie|lab|labrador)\b.*)$'
  )) {
    $rxObj = New-Object System.Text.RegularExpressions.Regex($rxText, ([System.Text.RegularExpressions.RegexOptions]'IgnoreCase, CultureInvariant'))
    $Intents.Insert(0, @{ name = 'petstyle'; re = $rxObj })
  }
} catch { Write-Log $_ }
try {
  $miStyle = New-Entry 'Pet style' $null
  foreach ($sk in $PetStyleNames.Keys) {
    $styleItem = Add-Entry $miStyle $PetStyleNames[$sk] { param($sender, $ev) try { $null = Set-PetStyle ([string]$sender.Tag) $false } catch { Write-Log $_ } }
    $styleItem.Tag = $sk
    $styleItem.IsCheckable = $true
    $STYLE.items[$sk] = $styleItem
  }
  $menu.Items.Insert(($menu.Items.IndexOf($miSize) + 1), $miStyle)
} catch { Write-Log $_ }
try {
  $startStyle = 'golden'
  if (Test-Path $StyleFile) { $startStyle = ([string](Get-Content -Path $StyleFile -Raw)).Trim() }
  if (-not $PetStyles.ContainsKey($startStyle)) { $startStyle = 'golden' }
  $null = Set-PetStyle $startStyle $true
} catch { Write-Log $_ }

# ---------- check that all the parts were pasted ----------
$missingParts = @()
foreach ($pn in '1', '2', '3', '4', '5', '6', '7', '8') { if (-not $PartCheck.ContainsKey($pn)) { $missingParts += $pn } }
if ($missingParts.Count -gt 0) {
  $null = [System.Windows.MessageBox]::Show(('DogPet.ps1 is missing part(s): ' + ($missingParts -join ', ') + '. Please paste all 9 parts, in order.'), 'Dog Pet')
}

# ---------- go! ----------
$win.Left = $PET.x
$win.Top = $PET.y
$hourNow = (Get-Date).Hour
$greeting = 'Good evening'
if ($hourNow -lt 12) { $greeting = 'Good morning' } elseif ($hourNow -lt 18) { $greeting = 'Good afternoon' }
Say ($greeting + ', ' + $cfg.userName + '! I am ' + $cfg.dogName + ' ' + $EM.dog + ' Double-click me to chat!') 8
Do-Action 'bark' 1.2
Bark-Sound

# once a day, a short plan for the day
if ($BRAIN.lastBrief -ne (Get-Date).ToString('yyyy-MM-dd')) {
  $briefTimer = New-Object System.Windows.Threading.DispatcherTimer
  $briefTimer.Interval = [TimeSpan]::FromSeconds(10)
  $briefTimer.Add_Tick({
    param($sender, $ev)
    try {
      $sender.Stop()
      if (-not $PET.pending -and -not $PET.hidden) {
        Say (Get-ShortBrief) 12
        $BRAIN.lastBrief = (Get-Date).ToString('yyyy-MM-dd')
        Save-Brain
      }
    } catch { Write-Log $_ }
  })
  $briefTimer.Start()
}

# learn the list of installed apps in the background-ish (once, a little after start)
$appsTimer = New-Object System.Windows.Threading.DispatcherTimer
$appsTimer.Interval = [TimeSpan]::FromSeconds(25)
$appsTimer.Add_Tick({ param($sender, $ev) try { $sender.Stop(); $null = Get-AppList } catch { Write-Log $_ } })
$appsTimer.Start()

$timer.Start()
$checker.Start()
$watcher.Start()
$win.Show()
[System.Windows.Threading.Dispatcher]::Run()
# ===== end of PART 9 of 9 =====
