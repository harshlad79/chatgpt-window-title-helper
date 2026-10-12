# Title event probe

Diagnostic-only tool. This tool does not stop the Title Helper or alter the ChatGPT app.

Build: dotnet build tools/TitleEventProbe/TitleEventProbe.csproj -c Release
Run: dotnet run --project tools/TitleEventProbe/TitleEventProbe.csproj -c Release -- 600

Hooks WinEvent NAMECHANGE/FOREGROUND for current ChatGPT PID(s).
On one MTA thread, subscribes to UIA NameProperty for current Document and
title Button, plus direct-child StructureChanged on the window root.
No periodic UIA read after subscription; callbacks enqueue bounded logging.
The probe exits automatically after 20-3600 seconds.

Local log: %LOCALAPPDATA%\ChatGPTWindowTitleHelper\logs\event-probe-current.log
PRIVATE: log can contain user conversation titles; never commit or upload.
Windows newly opened after startup are not subscribed until probe restart.