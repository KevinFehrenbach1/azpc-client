using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

internal static class Launcher
{
    [STAThread]
    private static int Main()
    {
        try
        {
            string script = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "launcher", "AZPC-Launcher.ps1");
            if (!File.Exists(script)) throw new FileNotFoundException("AZPC launcher files are missing. Reinstall the launcher.");
            var start = new ProcessStartInfo {
                FileName = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "System32", "WindowsPowerShell", "v1.0", "powershell.exe"),
                Arguments = "-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File \"" + script + "\"",
                UseShellExecute = false, CreateNoWindow = true
            };
            using (var process = Process.Start(start)) { process.WaitForExit(); return process.ExitCode; }
        }
        catch (Exception error)
        {
            MessageBox.Show(error.Message, "AZPC Launcher", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }
}
