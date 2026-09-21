using ChatGPTWindowTitleHelper.Domain;
using ChatGPTWindowTitleHelper.Settings;
using Xunit;

namespace ChatGPTWindowTitleHelper.Tests.Settings;

public sealed class SettingsStoreTests
{
    [Fact]
    public void Missing_settings_use_both_features_enabled()
    {
        var path = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"), "settings.json");
        var settings = new SettingsStore(path).Load();

        Assert.True(settings.ShowConversationTitle);
        Assert.True(settings.ChangeAltTabTitle);
    }
}
