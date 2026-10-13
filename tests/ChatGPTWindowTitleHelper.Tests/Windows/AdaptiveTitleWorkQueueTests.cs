using ChatGPTWindowTitleHelper.Windows;
using Xunit;

namespace ChatGPTWindowTitleHelper.Tests.Windows;

public sealed class AdaptiveTitleWorkQueueTests
{
    [Fact]
    public void ImmediateWorkOvertakesEarlierBackgroundWork()
    {
        using var q = new AdaptiveTitleWorkQueue();
        q.Request(1, AdaptiveTitleWorkQueue.Background);
        q.Request(2, AdaptiveTitleWorkQueue.Background);
        q.Request(3, AdaptiveTitleWorkQueue.Immediate);
        Assert.Equal((nint)3, q.Take());
        q.Complete(3, true, DateTime.UtcNow);
        Assert.Equal((nint)1, q.Take());
        q.Complete(1, true, DateTime.UtcNow);
        Assert.Equal((nint)2, q.Take());
    }

    [Fact]
    public void PromotionDoesNotCreateDuplicateWindowJobs()
    {
        using var q = new AdaptiveTitleWorkQueue();
        q.Request(10, AdaptiveTitleWorkQueue.Background);
        q.Request(20, AdaptiveTitleWorkQueue.Background);
        q.Request(10, AdaptiveTitleWorkQueue.Immediate);
        Assert.Equal((nint)10, q.Take());
        q.Complete(10, true, DateTime.UtcNow);
        Assert.Equal((nint)20, q.Take());
    }

    [Fact]
    public void BackgroundScanSelectsOnlyOneDueWindowPerTick()
    {
        using var q = new AdaptiveTitleWorkQueue();
        var now = DateTime.UtcNow;
        q.Request(100, AdaptiveTitleWorkQueue.Immediate);
        q.Request(200, AdaptiveTitleWorkQueue.Immediate);
        Assert.Equal((nint)100, q.Take());
        q.Complete(100, true, now);
        Assert.Equal((nint)200, q.Take());
        q.Complete(200, true, now.AddSeconds(1));
        q.RequestOneDue([100, 200], now.AddSeconds(22));
        Assert.Equal((nint)100, q.Take());
        q.Complete(100, true, now.AddSeconds(22));
        q.RequestOneDue([100, 200], now.AddSeconds(23));
        Assert.Equal((nint)200, q.Take());
    }

    [Fact]
    public void FailedReadGetsEarlierBackoffThanSuccessfulRead()
    {
        using var q = new AdaptiveTitleWorkQueue();
        var now = DateTime.UtcNow;
        q.Request(1, AdaptiveTitleWorkQueue.Immediate);
        Assert.Equal((nint)1, q.Take());
        q.Complete(1, false, now);
        q.RequestOneDue([1], now.AddSeconds(1));
        q.RequestOneDue([1], now.AddSeconds(3));
        Assert.Equal((nint)1, q.Take());
    }

    [Fact]
    public void RemovingClosedWindowClearsKnownState()
    {
        using var q = new AdaptiveTitleWorkQueue();
        q.Request(15, AdaptiveTitleWorkQueue.Immediate);
        Assert.Equal((nint)15, q.Take());
        q.Complete(15, true, DateTime.UtcNow);
        Assert.True(q.IsKnown(15));
        q.RemoveMissing([]);
        Assert.False(q.IsKnown(15));
    }

    [Fact]
    public void PendingRunningWindowIsPromotedAfterCompletion()
    {
        using var q = new AdaptiveTitleWorkQueue();
        q.Request(1, AdaptiveTitleWorkQueue.Background);
        Assert.Equal((nint)1, q.Take());
        q.Request(2, AdaptiveTitleWorkQueue.Background);
        q.Request(1, AdaptiveTitleWorkQueue.Immediate);
        q.Complete(1, true, DateTime.UtcNow);
        Assert.Equal((nint)1, q.Take());
        q.Complete(1, true, DateTime.UtcNow);
        Assert.Equal((nint)2, q.Take());
    }
}
