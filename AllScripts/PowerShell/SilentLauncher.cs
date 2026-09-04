using System;
using System.Diagnostics;

namespace SilentLauncher
{
    class Program
    {
        static int Main(string[] args)
        {
            if (args == null || args.Length == 0)
            {
                return 0;
            }

            try
            {
                string rawCmd = Environment.CommandLine.Trim();
                string targetCmd = "";

                // Strip our own executable name from the command line
                if (rawCmd.StartsWith("\""))
                {
                    int closeQuote = rawCmd.IndexOf('\"', 1);
                    if (closeQuote != -1 && closeQuote + 1 < rawCmd.Length)
                    {
                        targetCmd = rawCmd.Substring(closeQuote + 1).Trim();
                    }
                }
                else
                {
                    int space = rawCmd.IndexOf(' ');
                    if (space != -1)
                    {
                        targetCmd = rawCmd.Substring(space + 1).Trim();
                    }
                }

                if (string.IsNullOrEmpty(targetCmd))
                {
                    return 0;
                }

                string app = "";
                string appArgs = "";

                if (targetCmd.StartsWith("\""))
                {
                    int endQuote = targetCmd.IndexOf('\"', 1);
                    if (endQuote != -1)
                    {
                        app = targetCmd.Substring(1, endQuote - 1);
                        if (endQuote + 1 < targetCmd.Length)
                        {
                            appArgs = targetCmd.Substring(endQuote + 1).Trim();
                        }
                    }
                    else
                    {
                        app = targetCmd.Trim('\"');
                    }
                }
                else
                {
                    int space = targetCmd.IndexOf(' ');
                    if (space != -1)
                    {
                        app = targetCmd.Substring(0, space);
                        appArgs = targetCmd.Substring(space + 1).Trim();
                    }
                    else
                    {
                        app = targetCmd;
                    }
                }

                ProcessStartInfo psi = new ProcessStartInfo();
                psi.FileName = app;
                psi.Arguments = appArgs;
                psi.CreateNoWindow = true;
                psi.UseShellExecute = false;
                psi.WindowStyle = ProcessWindowStyle.Hidden;

                using (Process proc = Process.Start(psi))
                {
                    if (proc != null)
                    {
                        proc.WaitForExit();
                        return proc.ExitCode;
                    }
                }
            }
            catch (Exception)
            {
                return 1;
            }

            return 0;
        }
    }
}
