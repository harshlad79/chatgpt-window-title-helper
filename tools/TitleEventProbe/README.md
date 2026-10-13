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
Runtime ID verification:
1. Start the 900-second probe before changing a conversation title.
2. The uia.ready log records each Document and title Button RuntimeId.
3. After renaming, run:
   dotnet run --project tools/TitleEventProbe/TitleEventProbe.csproj -c Release -- --snapshot
4. Compare by HWND: initial documentRuntimeId versus snapshot documentRuntimeId,
   Document.Name (doc versus name), and any uia.document-name event.
   The snapshot does not clear the running event log.
5. A stable RuntimeId with changed name but no UIA event indicates the
   UIA provider did not report that property change to this subscription.
   A changed RuntimeId suggests the Document element was replaced.
