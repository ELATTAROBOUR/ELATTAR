
flutter clean
flutter pub get
Write-Host "Building Main Application..." -ForegroundColor Green
flutter build windows

Remove-Item -Path ".\Store\*" -Recurse -Force
New-Item -ItemType Directory -Force -Path ".\Store"
Copy-Item -Path ".\build\windows\x64\runner\Release\*" -Destination ".\Store" -Recurse -Force

Write-Host "Copying database sync scripts to Store directory..." -ForegroundColor Green
Copy-Item -Path ".\sync_setup\*" -Destination ".\Store" -Recurse -Force

Write-Host "Packaging Main Application into a single standalone executable..." -ForegroundColor Green

# 1. Zip the Store directory
if (Test-Path ".\Store.zip") { Remove-Item ".\Store.zip" -Force }
Write-Host "Waiting for file system to release locks..." -ForegroundColor Yellow
Start-Sleep -Seconds 3
Compress-Archive -Path ".\Store\*" -DestinationPath ".\Store.zip" -Force

# 2. Write C# loader code
$csharpCode = @"
using System;
using System.IO;
using System.IO.Compression;
using System.Diagnostics;
using System.Reflection;
using System.Threading;

class Program
{
    [STAThread]
    static void Main()
    {
        string tempRoot = Path.Combine(Path.GetTempPath(), "ElAttarStore_Run");
        string tempDir = Path.Combine(tempRoot, Guid.NewGuid().ToString());
        
        try
        {
            Directory.CreateDirectory(tempDir);
            
            Stream zipStream = Assembly.GetExecutingAssembly().GetManifestResourceStream("Store.zip");
            if (zipStream == null)
            {
                System.Windows.Forms.MessageBox.Show("Error: Embedded program files not found.", "Critical Error", System.Windows.Forms.MessageBoxButtons.OK, System.Windows.Forms.MessageBoxIcon.Error);
                return;
            }
            
            using (ZipArchive archive = new ZipArchive(zipStream))
            {
                archive.ExtractToDirectory(tempDir);
            }
            
            string exePath = Path.Combine(tempDir, "mobile_repair_desktop.exe");
            if (!File.Exists(exePath))
            {
                string[] exes = Directory.GetFiles(tempDir, "*.exe");
                if (exes.Length > 0)
                {
                    exePath = exes[0];
                }
            }
            
            // Check for license.lic next to the loader exe and copy it to tempDir
            string[] args = Environment.GetCommandLineArgs();
            string originalExePath = args[0];
            string originalExeDir = Path.GetDirectoryName(originalExePath);
            string originalLicensePath = Path.Combine(originalExeDir, "license.lic");
            string tempLicensePath = Path.Combine(tempDir, "license.lic");
            if (File.Exists(originalLicensePath))
            {
                try
                {
                    File.Copy(originalLicensePath, tempLicensePath, true);
                }
                catch {}
            }

            ProcessStartInfo startInfo = new ProcessStartInfo(exePath);
            startInfo.WorkingDirectory = tempDir;
            if (args.Length > 1)
            {
                startInfo.Arguments = string.Join(" ", args, 1, args.Length - 1);
            }
            
            using (Process process = Process.Start(startInfo))
            {
                process.WaitForExit();
            }

            // If the temp license.lic was deleted (meaning Dart processed and registered it),
            // delete the original license.lic next to ELATTAR-STORE.exe
            if (File.Exists(originalLicensePath) && !File.Exists(tempLicensePath))
            {
                try
                {
                    File.Delete(originalLicensePath);
                }
                catch {}
            }
        }
        catch (Exception ex)
        {
            System.Windows.Forms.MessageBox.Show("Error starting program: " + ex.Message, "Error", System.Windows.Forms.MessageBoxButtons.OK, System.Windows.Forms.MessageBoxIcon.Error);
        }
        finally
        {
            new Thread(() => {
                Thread.Sleep(3000);
                for (int i = 0; i < 5; i++)
                {
                    try
                    {
                        if (Directory.Exists(tempDir))
                        {
                            Directory.Delete(tempDir, true);
                        }
                        break;
                    }
                    catch
                    {
                        Thread.Sleep(1500);
                    }
                }
            }).Start();
        }
    }
}
"@

$csharpCode | Out-File -FilePath ".\loader.cs" -Encoding utf8

# 3. Create dist directory
New-Item -ItemType Directory -Force -Path ".\dist"

# 4. Compile the C# loader
$cscPath = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
$iconPath = ".\windows\runner\resources\app_icon.ico"

& $cscPath /target:winexe /reference:System.IO.Compression.dll /reference:System.IO.Compression.FileSystem.dll /reference:System.Windows.Forms.dll /resource:Store.zip,Store.zip /win32icon:$iconPath /out:.\dist\ELATTAR-STORE.exe .\loader.cs

# 5. Clean up temporary files
if (Test-Path ".\Store.zip") { Remove-Item ".\Store.zip" -Force }
if (Test-Path ".\loader.cs") { Remove-Item ".\loader.cs" -Force }

Write-Host "Building Keygen Application..." -ForegroundColor Green
flutter build windows -t lib/keygen_main.dart

# Backup subscribers.db if it exists in Keygen folder
$dbPath = ".\Keygen\subscribers.db"
$dbBackup = $null
if (Test-Path $dbPath) {
    $dbBackup = [System.IO.Path]::GetTempFileName()
    Copy-Item -Path $dbPath -Destination $dbBackup -Force
}

Remove-Item -Path ".\Keygen\*" -Recurse -Force
New-Item -ItemType Directory -Force -Path ".\Keygen"
Copy-Item -Path ".\build\windows\x64\runner\Release\*" -Destination ".\Keygen" -Recurse -Force

# Restore subscribers.db if it was backed up
if ($dbBackup -and (Test-Path $dbBackup)) {
    Copy-Item -Path $dbBackup -Destination $dbPath -Force
    Remove-Item -Path $dbBackup -Force
}

Write-Host "Done! You can find the output in the 'dist' folder." -ForegroundColor Cyan
