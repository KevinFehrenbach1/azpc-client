using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Windows.Forms;

internal static class Launcher
{
    [STAThread]
    private static int Main()
    {
        string log = null;
        try
        {
            string root = AppDomain.CurrentDomain.BaseDirectory;
            string script = Path.Combine(root, "launcher", "AZPC-Launcher.ps1");
            if (!File.Exists(script)) throw new FileNotFoundException("AZPC launcher files are missing. Reinstall the launcher.");
            string logs = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "AZPC", "Launcher", "logs");
            Directory.CreateDirectory(logs);
            log = Path.Combine(logs, "startup-" + DateTime.UtcNow.ToString("yyyyMMdd-HHmmss-fff") + ".log");
            var errors = new StringBuilder();
            var sync = new object();
            var start = new ProcessStartInfo {
                FileName = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "System32", "WindowsPowerShell", "v1.0", "powershell.exe"),
                // CreateNoWindow suppresses the console. WindowStyle Hidden also hides the first GUI window.
                Arguments = "-NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File \"" + script + "\"",
                WorkingDirectory = root,
                UseShellExecute = false, CreateNoWindow = true,
                RedirectStandardError = true, RedirectStandardOutput = true
            };
            using (var process = new Process()) {
                process.StartInfo = start;
                process.ErrorDataReceived += delegate(object sender, DataReceivedEventArgs e) {
                    if (e.Data != null) lock(sync) { errors.AppendLine(e.Data); }
                };
                // Drain output asynchronously so neither redirected pipe can block the UI process.
                process.OutputDataReceived += delegate(object sender, DataReceivedEventArgs e) { };
                if (!process.Start()) throw new Exception("Windows could not start AZPC Launcher.");
                process.BeginErrorReadLine(); process.BeginOutputReadLine();
                process.WaitForExit();
                string detail; lock(sync) { detail = errors.ToString(); }
                File.WriteAllText(log, "AZPC Launcher 0.2.1\r\nExit code: " + process.ExitCode + "\r\n" + detail);
                if (process.ExitCode != 0) {
                    if (detail.Length > 1400) detail = detail.Substring(0,1400);
                    MessageBox.Show("AZPC could not open.\r\n\r\n" + detail + "\r\nStartup log:\r\n" + log,
                        "AZPC Launcher startup error", MessageBoxButtons.OK, MessageBoxIcon.Error);
                }
                return process.ExitCode;
            }
        }
        catch (Exception error)
        {
            MessageBox.Show(error.Message + (log == null ? "" : "\r\nStartup log: " + log), "AZPC Launcher", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }
}
