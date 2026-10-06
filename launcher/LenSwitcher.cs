using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Net;
using System.Reflection;
using System.Windows.Forms;

internal static class Program
{
    private const string PrimaryZipUrl = "https://www.autohotkey.com/download/ahk-v2.zip";
    private const string FallbackZipUrl = "https://github.com/AutoHotkey/AutoHotkey/releases/download/v2.0.26/AutoHotkey_2.0.26.zip";

    [STAThread]
    private static void Main()
    {
        try
        {
            ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12;
            string appDir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "LenSwitcher");
            Directory.CreateDirectory(appDir);

            string scriptPath = Path.Combine(appDir, "len-switcher.ahk");
            ExtractScript(scriptPath);

            string runtimeDir = Path.Combine(appDir, "runtime");
            string ahkExe = FindAutoHotkey(runtimeDir);
            if (ahkExe == null)
            {
                DownloadRuntime(runtimeDir);
                ahkExe = FindAutoHotkey(runtimeDir);
            }

            if (ahkExe == null)
                throw new Exception("AutoHotkey was downloaded, but AutoHotkey64.exe / AutoHotkey32.exe was not found in the zip.");

            var start = new ProcessStartInfo();
            start.FileName = ahkExe;
            start.Arguments = "\"" + scriptPath + "\"";
            start.UseShellExecute = false;
            start.WorkingDirectory = appDir;
            Process.Start(start);
        }
        catch (Exception ex)
        {
            MessageBox.Show(
                ex.Message,
                "Len Switcher",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
        }
    }

    private static void ExtractScript(string destPath)
    {
        string besideExe = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "len-switcher.ahk");
        if (File.Exists(besideExe))
        {
            File.Copy(besideExe, destPath, true);
            return;
        }

        Assembly asm = Assembly.GetExecutingAssembly();
        string resourceName = null;
        foreach (string name in asm.GetManifestResourceNames())
        {
            if (name.EndsWith("len-switcher.ahk", StringComparison.OrdinalIgnoreCase)
                || name.Equals("len-switcher.ahk", StringComparison.OrdinalIgnoreCase))
            {
                resourceName = name;
                break;
            }
        }

        if (resourceName == null)
            throw new Exception("Could not find len-switcher.ahk next to the exe or inside it.");

        using (Stream src = asm.GetManifestResourceStream(resourceName))
        using (FileStream dst = File.Create(destPath))
        {
            src.CopyTo(dst);
        }
    }

    private static void DownloadRuntime(string runtimeDir)
    {
        Form wait = ShowWaitWindow("Downloading AutoHotkey v2 (one time)...");
        Application.DoEvents();
        try
        {
            if (Directory.Exists(runtimeDir))
                Directory.Delete(runtimeDir, true);
            Directory.CreateDirectory(runtimeDir);

            string zipPath = Path.Combine(Path.GetTempPath(), "len-switcher-ahk-v2.zip");
            try
            {
                DownloadFile(PrimaryZipUrl, zipPath);
            }
            catch
            {
                DownloadFile(FallbackZipUrl, zipPath);
            }

            ZipFile.ExtractToDirectory(zipPath, runtimeDir);
            try { File.Delete(zipPath); } catch { }
        }
        finally
        {
            wait.Close();
            wait.Dispose();
        }
    }

    private static void DownloadFile(string url, string destPath)
    {
        using (WebClient client = new WebClient())
        {
            client.Headers.Add("User-Agent", "LenSwitcher");
            client.DownloadFile(url, destPath);
        }
    }

    private static Form ShowWaitWindow(string message)
    {
        Form form = new Form();
        form.Text = "Len Switcher";
        form.Width = 420;
        form.Height = 110;
        form.FormBorderStyle = FormBorderStyle.FixedDialog;
        form.StartPosition = FormStartPosition.CenterScreen;
        form.ControlBox = false;
        form.TopMost = true;

        Label label = new Label();
        label.Text = message;
        label.AutoSize = true;
        label.Left = 20;
        label.Top = 28;
        form.Controls.Add(label);
        form.Show();
        return form;
    }

    private static string FindAutoHotkey(string root)
    {
        if (!Directory.Exists(root))
            return null;

        string preferred = Environment.Is64BitOperatingSystem ? "AutoHotkey64.exe" : "AutoHotkey32.exe";
        string fallback = Environment.Is64BitOperatingSystem ? "AutoHotkey32.exe" : "AutoHotkey64.exe";

        string found = FindFile(root, preferred);
        if (found != null)
            return found;
        return FindFile(root, fallback);
    }

    private static string FindFile(string root, string fileName)
    {
        foreach (string path in Directory.GetFiles(root, fileName, SearchOption.AllDirectories))
            return path;
        return null;
    }
}
