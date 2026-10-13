using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

namespace MpvNet.Windows.Help;

// Diagnostic lookup only: mpv owns profile loading and monitor-change handling.
internal static class DisplayColorInfo
{
    public static string Describe(IntPtr window)
    {
        string display = Screen.FromHandle(window).DeviceName;
        string manual = Player.GetPropertyString("icc-profile");
        bool automatic = Player.GetPropertyBool("icc-profile-auto");
        string mode = manual.Length > 0 ? "Manual" : automatic ? "Automatic" : "Off";
        string profile = manual.Length > 0 ? manual : automatic ? GetAssignedProfile(display) : "None";

        return $"Display: {display}\nICC mode: {mode}\n" +
            $"{(manual.Length > 0 ? "Configured profile" : "Windows assigned profile")}: {profile}\n\n" +
            $"Renderer: {Player.GetPropertyString("current-vo")}\n" +
            $"GPU API setting: {Player.GetPropertyString("gpu-api")}\n" +
            $"Output primaries: {Player.GetPropertyString("video-out-params/primaries")}\n" +
            $"Output transfer: {Player.GetPropertyString("video-out-params/gamma")}\n\n" +
            "This SDR build expects Windows HDR to be off. The profile above is the " +
            "configured/assigned profile, not confirmation that a valid ICC transform loaded. " +
            "Use the mpv verbose log to check profile loading and any errors.";
    }

    private static string GetAssignedProfile(string display)
    {
        IntPtr dc = CreateDC("DISPLAY", display, null, IntPtr.Zero);
        if (dc == IntPtr.Zero)
            return "Unavailable (could not open display)";

        try
        {
            uint length = 0;
            GetICMProfile(dc, ref length, null);
            if (length == 0 || length > 32768)
                return "Unavailable (no ICC profile reported)";

            var path = new StringBuilder((int)length);
            return GetICMProfile(dc, ref length, path)
                ? path.ToString() : "Unavailable (profile lookup failed)";
        }
        finally
        {
            DeleteDC(dc);
        }
    }

    [DllImport("gdi32.dll", CharSet = CharSet.Unicode, EntryPoint = "CreateDCW")]
    private static extern IntPtr CreateDC(string driver, string device, string? output, IntPtr initData);

    [DllImport("gdi32.dll", CharSet = CharSet.Unicode, EntryPoint = "GetICMProfileW")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetICMProfile(IntPtr dc, ref uint length, StringBuilder? filename);

    [DllImport("gdi32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DeleteDC(IntPtr dc);
}
