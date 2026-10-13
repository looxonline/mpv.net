using System.Runtime.InteropServices;
using System.Text;
using MpvNet;
using MpvNet.Native;

string mode = args[0];
string runtime = Path.GetFullPath(args[1]);
string results = Path.GetFullPath(args[2]);
Directory.CreateDirectory(results);
string config = Path.Combine(results, mode);
Directory.CreateDirectory(config);
Environment.SetEnvironmentVariable("MPVNET_HOME", config);
Translator.Current = new IdentityTranslator();
NativeLibrary.SetDllImportResolver(typeof(LibMpv).Assembly,
    (name, assembly, searchPath) => name == "libmpv-2.dll"
        ? NativeLibrary.Load(Path.Combine(runtime, name)) : IntPtr.Zero);

string extra = mode == "override" ? "icc-profile-auto=no\ntarget-peak=120\n" : "";
File.WriteAllText(Path.Combine(config, "mpv.conf"), "load-scripts=no\nosc=no\n" + extra);
var player = Global.Player;
player.Init(IntPtr.Zero, false);
try
{
    Require(player.GetPropertyString("vo") == "gpu", "GPU colour renderer default");
    Require(player.GetPropertyString("gpu-api") == "d3d11", "D3D11 default");
    Require(player.GetPropertyBool("icc-profile-auto") == (mode != "override"), "ICC default/config override");
    Require(player.GetPropertyString("target-colorspace-hint") == "no", "SDR colourspace signalling");
    Require(player.GetPropertyInt("target-peak") == (mode == "override" ? 120 : 100), "SDR peak/config override");
    Console.WriteLine(player.GetPropertyString("mpv-version"));

    if (mode == "render")
    {
        string icc = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),
            "spool", "drivers", "color", "sRGB Color Space Profile.icm");
        Require(File.Exists(icc), "Windows test ICC profile exists");
        string log = Path.Combine(results, "renderer.log");
        player.SetPropertyString("log-file", log);
        player.SetPropertyString("msg-level", "all=v");
        player.SetPropertyString("d3d11-warp", "yes");
        player.SetPropertyString("icc-profile", icc);
        player.SetPropertyBool("icc-cache", false);
        player.SetPropertyString("image-display-duration", "inf");
        player.SetPropertyBool("pause", true);
        player.SetPropertyString("osd-level", "0");
        player.SetPropertyString("osd-playing-msg", "");
        player.SetPropertyString("geometry", "256x256");
        string sample = Path.Combine(results, "gradient.ppm");
        using (var file = File.Create(sample))
        {
            file.Write(Encoding.ASCII.GetBytes("P6\n256 256\n255\n"));
            for (int y = 0; y < 256; y++)
                for (int x = 0; x < 256; x++)
                    file.Write(new byte[] { (byte)x, (byte)y, 96 });
        }
        player.CommandV("loadfile", sample);
        Require(SpinWait.SpinUntil(() => player.GetPropertyInt("video-out-params/w") > 0,
            TimeSpan.FromSeconds(30)), "D3D11 software renderer opens a frame");
        Thread.Sleep(2000);
        string managed = Path.Combine(results, "icc-on.png");
        player.CommandV("screenshot-to-file", managed, "window");
        Require(File.Exists(managed) && new FileInfo(managed).Length > 100, "ICC rendering screenshot");
        player.SetPropertyBool("icc-profile-auto", false);
        player.SetPropertyString("icc-profile", "");
        Thread.Sleep(2000);
        string unmanaged = Path.Combine(results, "icc-off.png");
        player.CommandV("screenshot-to-file", unmanaged, "window");
        Require(File.Exists(unmanaged), "Unmanaged rendering screenshot");
        Require(!File.ReadAllBytes(managed).SequenceEqual(File.ReadAllBytes(unmanaged)),
            "ICC conversion changes rendered output");
        string logs = File.ReadAllText(log);
        Require(logs.Contains("Opening ICC profile"), "ICC profile load logged");
        Require(!logs.Contains("Error loading ICC profile"), "No ICC loading failure");
    }
}
finally
{
    player.Destroy();
}
Console.WriteLine($"PASS: {mode}");

static void Require(bool condition, string description)
{
    if (!condition) throw new Exception("FAIL: " + description);
    Console.WriteLine("PASS: " + description);
}
sealed class IdentityTranslator : ITranslator
{
    public string Gettext(string msgId) => msgId;
    public string GetParticularString(string context, string text) => text;
}
