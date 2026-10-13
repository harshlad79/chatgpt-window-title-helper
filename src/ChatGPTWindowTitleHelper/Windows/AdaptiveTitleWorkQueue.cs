namespace ChatGPTWindowTitleHelper.Windows;

// All queue mutations run on the WinForms UI thread except Dequeue and Complete.
// Pending HWNDs are unique; a high-priority event promotes existing work.
public sealed class AdaptiveTitleWorkQueue : IDisposable
{
    private readonly object gate = new();
    private readonly AutoResetEvent wake = new(false);
    private readonly Dictionary<nint, Pending> pending = [];
    private readonly Dictionary<nint, DateTime> due = [];
    private readonly HashSet<nint> running = [];
    private readonly Dictionary<nint, int> failures = [];
    private long counter;
    private bool stopping;

    private readonly record struct Pending(int Priority, long Order);
    public const int Background = 0, Active = 1, Immediate = 2;

    public void Request(nint hwnd, int priority)
    {
        lock (gate)
        {
            if (stopping || hwnd == 0) return;
            if (pending.TryGetValue(hwnd, out var old))
                pending[hwnd] = new Pending(Math.Max(old.Priority, priority), old.Order);
            else if (!running.Contains(hwnd))
                pending[hwnd] = new Pending(priority, ++counter);
            else if (priority >= Immediate)
                pending[hwnd] = new Pending(priority, ++counter);
            wake.Set();
        }
    }

    // Only ONE overdue established window per discovery tick.
    public void RequestOneDue(IEnumerable<nint> visible, DateTime now)
    {
        lock (gate)
        {
            if (stopping) return;
            var candidate = visible.Where(h => due.TryGetValue(h, out var at)
                && at <= now && !pending.ContainsKey(h) && !running.Contains(h))
                .OrderBy(h => due[h]).FirstOrDefault();
            if (candidate != 0)
            {
                pending[candidate] = new Pending(Background, ++counter);
                wake.Set();
            }
        }
    }

    public bool IsKnown(nint hwnd) { lock (gate) return due.ContainsKey(hwnd); }

    public void RemoveMissing(IEnumerable<nint> current)
    {
        var keep = current.ToHashSet();
        lock (gate)
        {
            foreach (var h in due.Keys.Where(h => !keep.Contains(h)).ToArray())
            {
                due.Remove(h);
                failures.Remove(h);
                pending.Remove(h);
            }
        }
    }

    public nint Take()
    {
        while (true)
        {
            lock (gate)
            {
                if (stopping) return 0;
                var next = pending.Where(x => !running.Contains(x.Key))
                    .OrderByDescending(x => x.Value.Priority)
                    .ThenBy(x => x.Value.Order).FirstOrDefault();
                if (next.Key != 0)
                {
                    pending.Remove(next.Key);
                    running.Add(next.Key);
                    return next.Key;
                }
            }
            wake.WaitOne();
        }
    }

    public void Complete(nint hwnd, bool successful, DateTime now)
    {
        lock (gate)
        {
            running.Remove(hwnd);
            if (stopping) return;
            var failed = successful ? 0 : Math.Min(5, failures.GetValueOrDefault(hwnd) + 1);
            failures[hwnd] = failed;
            due[hwnd] = now + (successful
                ? TimeSpan.FromSeconds(20)
                : TimeSpan.FromSeconds(Math.Min(30, Math.Pow(2, failed))));
            if (pending.Count > 0) wake.Set();
        }
    }

    public void Dispose()
    {
        lock (gate) { stopping = true; pending.Clear(); wake.Set(); }
        // The worker owns UIA COM subscriptions and is allowed to exit asynchronously
        // if one provider RPC call is stalled. Never block the WinForms UI thread.
    }
}
