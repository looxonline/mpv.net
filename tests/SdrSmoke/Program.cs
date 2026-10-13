using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Media;
using System.Windows.Media.Imaging;
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
if (mode == "regressions")
{
    string applicationConfig = Path.Combine(config, "mpvnet.conf");
    File.WriteAllText(applicationConfig, "# preserve application settings\nmedia-info=no\n");
    File.AppendAllText(Path.Combine(config, "mpv.conf"),
        "input-default-bindings=no\ninput-default-bindings = no\nvolume=50\n");
    Global.App.ApplyInputDefaultBindingsFix();
    Require(File.ReadAllText(applicationConfig) == "# preserve application settings\nmedia-info=no\n",
        "Config migration preserves mpvnet.conf (#772)");
    string migrated = File.ReadAllText(Path.Combine(config, "mpv.conf"));
    Require(!migrated.Contains("input-default-bindings") && migrated.Contains("volume=50"),
        "Config migration updates only mpv.conf (#772)");
    Require(InputHelp.Parse("BROKEN\nx cycle pause\n").Any(binding => binding.Input == "x"),
        "Malformed binding is skipped and valid binding survives (#780)");
}
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

    if (mode == "regressions")
    {
        player.SetPropertyInt("volume", 50);
        Command.ShowText("\"; set volume 17; show-text \"", 100, 16);
        Require(player.GetPropertyInt("volume") == 50, "Display text cannot inject a command (#774)");
        player.MediaTracks = new List<MediaTrack>
        {
            new() { ID = 2, Type = "a", Text = "A: First" },
            new() { ID = 7, Type = "a", Text = "A: Second" }
        };
        player.SetPropertyInt("aid", 2);
        Command.Current.Commands["cycle-audio"](Array.Empty<string>());
        Require(player.GetPropertyInt("aid") == 7, "Audio cycles to real non-contiguous ID (#774)");
        Command.Current.Commands["cycle-audio"](Array.Empty<string>());
        Require(player.GetPropertyInt("aid") == 2, "Audio cycles back to first ID (#774)");
        player.MediaTracks.RemoveAt(1);
        player.SetPropertyString("aid", "no");
        Command.Current.Commands["cycle-audio"](Array.Empty<string>());
        Require(player.GetPropertyInt("aid") == 2, "Disabled single audio track can be enabled (#774)");
    }

    if (mode == "render")
    {
        string icc = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),
            "spool", "drivers", "color", "sRGB Color Space Profile.icm");
        Require(File.Exists(icc), "Windows test ICC profile exists");
        string log = Path.Combine(results, "renderer.log");
        player.SetPropertyString("log-file", log);
        player.SetPropertyString("msg-level", "all=v");
        player.SetPropertyString("d3d11-warp", "yes");
        player.SetPropertyString("dither-depth", "no");
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
        Require(!ReadPixels(managed).SequenceEqual(ReadPixels(unmanaged)),
            "ICC conversion changes rendered output");
        using var logStream = new FileStream(log, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
        using var logReader = new StreamReader(logStream);
        string logs = logReader.ReadToEnd();
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
static byte[] ReadPixels(string path)
{
    using var stream = File.OpenRead(path);
    var image = BitmapDecoder.Create(stream, BitmapCreateOptions.PreservePixelFormat,
        BitmapCacheOption.OnLoad).Frames[0];
    var converted = new FormatConvertedBitmap(image, PixelFormats.Bgra32, null, 0);
    int stride = converted.PixelWidth * 4;
    byte[] pixels = new byte[stride * converted.PixelHeight];
    converted.CopyPixels(pixels, stride, 0);
    return pixels;
}
sealed class IdentityTranslator : ITranslator
{
    public string Gettext(string msgId) => msgId;
    public string GetParticularString(string context, string text) => text;
}
