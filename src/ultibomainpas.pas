program UltiboMainPas;
{$mode objfpc}{$H+}

uses
 {$ifdef BUILD_QEMUVPB } QEMUVersatilePB, {$endif}
 {$ifdef BUILD_RPI     } RaspberryPi,     {$endif}
 {$ifdef BUILD_RPI2    } RaspberryPi2,    {$endif}
 {$ifdef BUILD_RPI3    } RaspberryPi3,    {$endif}
 GlobalConst,GlobalTypes,Platform,Threads,Syscalls,
 API in '.\subtree\ultibohub\API\interface\api.pas',
 UltiboUtils,Logging,GlobalConfig,SysUtils,Console,
 DwcOtg,Keyboard,GraphicsConsole,Math;
 
{$link zig-cache\ultibomainzig.o}
function mainzig(argc: int; argv: PPChar): int; cdecl; external name 'mainzig';

procedure StartLogging;
begin
 LOGGING_INCLUDE_COUNTER:=False;
 LOGGING_INCLUDE_TICKCOUNT:=True;
 CONSOLE_REGISTER_LOGGING:=True;
 CONSOLE_LOGGING_POSITION:=CONSOLE_POSITION_RIGHT;
 LoggingConsoleDeviceAdd(ConsoleDeviceGetDefault);
 LoggingDeviceSetDefault(LoggingDeviceFindByType(LOGGING_TYPE_CONSOLE));
end;

var
 argc:int;      
 argv:PPChar;
 ExitCode:Integer;

begin
 StartLogging;
 argv:=AllocateCommandLine(SystemGetCommandLine,argc);
 ExitCode := mainzig(argc,argv);
 LoggingOutput(Format('mainzig stopped with exit code %d',[ExitCode]));
 ReleaseCommandLine(argv);
 ThreadHalt(0);
end.
