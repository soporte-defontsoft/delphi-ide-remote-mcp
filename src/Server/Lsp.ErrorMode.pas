unit Lsp.ErrorMode;

{ One thing: a child process that will never open an error dialog. It depends
  on nothing but the system, so the server (engines, builds, git, test
  executables, adb) and the remote-run launcher (src/RunJob, which starts the
  user's program on a Windows target) share it. Empty on any other platform. }

interface

{$IFDEF MSWINDOWS}
uses
  Winapi.Windows;

{ The child will never open an error dialog: nobody is there to answer one.
  One that dies of an unhandled exception then ends at once, instead of going
  through the system's crash reporting (measured 2026-09-30 with a program
  that raises the engine's own exception code: 0.0 s against 1.3 s) or
  waiting behind a dialog - one was found on the operator's desktop that
  morning, from an engine of a test run.
  Called on a child created SUSPENDED, before it runs. The mode is set ON THE
  CHILD, not inherited: a child inherits its parent's PROCESS mode, and the
  server's does not stay where it is put - measured with a build that set it
  to "no dialog" at start-up: it read as "dialogs" after the parallel phases
  of a battery (somebody saves and restores it with no exclusion) - while
  PAServer's is 0 (measured the same day: a program started by a remote run
  on a Windows target said mode 0). With the mode Windows writes NO
  Application Error event for the crash (measured: event 1000 without it,
  nothing with it): whoever launches has to keep the exit code. Never raises:
  a child that could not be told runs as it would have. }
procedure NoErrorDialogs(AProcess: THandle);
{$ENDIF}

implementation

{$IFDEF MSWINDOWS}
function NtSetInformationProcess(ProcessHandle: THandle; ProcessInformationClass: ULONG;
  ProcessInformation: Pointer; ProcessInformationLength: ULONG): Integer; stdcall;
  external 'ntdll.dll';

procedure NoErrorDialogs(AProcess: THandle);
const
  ProcessDefaultHardErrorMode_ = 12;
var
  Mode: ULONG;
begin
  // what SetErrorMode writes for the calling process, written for another
  // one; the kernel keeps SEM_FAILCRITICALERRORS inverted
  Mode := (SEM_FAILCRITICALERRORS or SEM_NOGPFAULTERRORBOX) xor SEM_FAILCRITICALERRORS;
  NtSetInformationProcess(AProcess, ProcessDefaultHardErrorMode_, @Mode, SizeOf(Mode));
end;
{$ENDIF}

end.
