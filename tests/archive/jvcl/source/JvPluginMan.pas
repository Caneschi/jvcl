{-----------------------------------------------------------------------------
The contents of this file are subject to the Mozilla Public License
Version 1.1 (the "License"); you may not use this file except in compliance
with the License. You may obtain a copy of the License at
http://www.mozilla.org/MPL/MPL-1.1.html

Software distributed under the License is distributed on an "AS IS" basis,
WITHOUT WARRANTY OF ANY KIND, either expressed or implied. See the License for
the specific language governing rights and limitations under the License.

The Original Code is: uilPluginMan.PAS, released on 1999-09-06.

The Initial Developer of the Original Code is Tim Sullivan [tim@uil.net]
Portions created by Tim Sullivan are Copyright (C) 1999 Tim Sullivan.
All Rights Reserved.

Contributor(s): Ralf Steinhaeusser [ralfiii@gmx.net].

Last Modified: 2002-09-02

You may retrieve the latest version of this file at the Project JEDI's JVCL home page,
located at http://jvcl.sourceforge.net

Known Issues:

 PluginManager loads Plugins

 detailed Versionhistory see JvPlugCommon .pas

 changed 26.7.2001, by Ralf Steinhaeusser, Changes marked with !

 Events :
 When loading plugins (LoadPlugins) the events are called in the following order:
 FOnBeforeLoad(Sender, Name, CanLoad)
     Plugin -> Register
     Plugin.Initialize
   FOnNewCommand (times Nr. of commands)
 FOnAfterLoad
-----------------------------------------------------------------------------}

{$I JVCL.INC}

unit JvPluginMan;

interface

uses
  Windows, SysUtils, Classes, Graphics,
  JvComponent, JvPlugin; // reduced to the min

type
  TNewCommandEvent = procedure(Sender: TObject; ACaption, AHint, AData: string;
    ABitmap: TBitmap; AEvent: TNotifyEvent) of object;

type
  EJvPluginError = class(Exception);
  EJvLoadPluginError = class(EJvPluginError);

type
  TJvBeforeLoadEvent = procedure(Sender: TObject; FileName: string; var AllowLoad: Boolean) of object;
  //  TJvAfterLoadEvent = procedure(Sender: TObject; Filename: string) of object;
  TJvNotifyStrEvent = procedure(Sender: TObject; S: string) of object;

type
  TPluginKind = (plgDLL, plgPackage, plgCustom);

type
  TPluginInfo = class(TObject)
  public
    PluginKind: TPluginKind;
    Handle: HINST;
    Plugin: TJvPlugin;
  end;

type
  TJvPluginManager = class(TJvComponent)
  private
    FExtension: string;
    FPluginFolder: string;
    FPluginKind: TPluginKind;
    FPluginInfos: TList;
    FOnBeforeLoad: TJvBeforeLoadEvent;
    FOnAfterLoad: TJvNotifyStrEvent;
    FOnNewCommand: TNewCommandEvent;
    FOnErrorLoading: TJvNotifyStrEvent;
    procedure SetPluginKind(const Value: TPluginKind);
  protected
    procedure SetExtension(NewValue: string);
    function GetPlugin(Index: Integer): TJvPlugin;
    //    function GetVersion: string;
    function GetPluginCount: Integer;
    //    procedure SetVersion(newValue: string);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure LoadPlugin(FileName: string; PlgKind: TPluginKind);
    procedure LoadPlugins;
    procedure UnloadPlugin(Index: Integer);
    procedure GetLoadedPlugins(PluginList: TStrings);
    property Plugins[Index: Integer]: TJvPlugin read GetPlugin;
    property PluginCount: Integer read GetPluginCount;
    procedure SendMessage(PluginMessage: Longint; PluginParams: string);
    function AddCustomPlugin(Plugin: TJvPlugin): Boolean;
  published
    property PluginFolder: string read FPluginFolder write FPluginFolder;
    property Extension: string read FExtension write SetExtension;
    property PluginKind: TPluginKind read FPluginKind write SetPluginKind;
    //    property Version: string read GetVersion write SetVersion;
    property OnBeforeLoad: TJvBeforeLoadEvent read FOnBeforeLoad write FOnBeforeLoad;
    property OnAfterLoad: TJvNotifyStrEvent read FOnAfterLoad write FOnAfterLoad;
    property OnNewCommand: TNewCommandEvent read FOnNewCommand write FOnNewCommand;
    property OnErrorLoading: TJvNotifyStrEvent read FOnErrorLoading write FOnErrorLoading;
  end;

implementation

uses
  Forms,
  JvPlugCommon, JvFunctions; // for IncludeTrailingPathDelimiter (only <D6)

const
  C_Extensions: array [plgDLL..plgPackage] of PChar = ('dll', 'bpl');

constructor TJvPluginManager.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FPluginInfos := TList.Create;
  FPluginKind := plgDLL;
  FExtension := C_Extensions[FPluginKind];
end;

destructor TJvPluginManager.Destroy;
begin
  // Free the loaded plugins
  while FPluginInfos.Count > 0 do // !change as suggested in forum
    UnloadPlugin(0);
  FPluginInfos.Free;
  inherited Destroy;
end;

procedure TJvPluginManager.SetExtension(NewValue: string);
begin
  if (FExtension <> NewValue) then
  begin
    // (rb) No reason to block this
    if {(Length(newValue) > 3) or} Length(NewValue) < 1 then
      raise Exception.Create('Extension may not be empty')
    else
      FExtension := NewValue;
  end;
end;

procedure TJvPluginManager.SetPluginKind(const Value: TPluginKind);
begin
  if FPluginKind <> Value then
  begin
    if FExtension = C_Extensions[FPluginKind] then
      FExtension := C_Extensions[Value];
    FPluginKind := Value;
  end;
end;

{function TJvPluginManager.GetVersion: string;
begin
  result := C_VersionString;
end;}

{procedure TJvPluginManager.SetVersion(newValue: string);
begin
end;}

function TJvPluginManager.GetPluginCount: Integer;
begin
  Result := FPluginInfos.Count;
end;

function TJvPluginManager.GetPlugin(Index: Integer): TJvPlugin;
var
  PlgI: TPluginInfo;
begin
  PlgI := FPluginInfos.Items[Index];
  Result := PlgI.Plugin;
end;

procedure TJvPluginManager.GetLoadedPlugins(PluginList: TStrings);
var
  J: Integer;
begin
  PlugInList.Clear;
  for J := 0 to FPluginInfos.Count - 1 do
    PluginList.Add(Plugins[J].Name);
end;

// Create and add plugin - if error occurs, the Plugin is not added to list

function TJvPluginManager.AddCustomPlugin(Plugin: TJvPlugin): Boolean;
var
  PlgInfo: TPluginInfo;
  Counter: Integer;
begin
  Result := Plugin.Initialize(Self, Application, 'CustomPlugin');
  if not Result then
    Exit;

  PlgInfo := TPluginInfo.Create;
  PlgInfo.PluginKind := PlgCustom;
  PlgInfo.Plugin := Plugin;

  FPluginInfos.Add(PlgInfo);

  // Events for all new commands
  if Assigned(FOnNewCommand) then
    for Counter := 0 to Plugin.Commands.Count - 1 do
      with TJvPluginCommand(Plugin.Commands.Items[Counter]) do
      try
        FOnNewCommand(Self, Caption, Hint, Data, Bitmap, OnExecute);
      except
      end;
end;

// Load a Plugin - either DLL or package

procedure TJvPluginManager.LoadPlugin(FileName: string; PlgKind: TPluginKind);
type
  TSxRegisterPlugin = function: TJvPlugin; stdcall;
var
  Counter: Integer;
  LibHandle: Integer;
  RegisterProc: TSxRegisterPlugin;
  Plugin: TJvPlugin;
  NumCopies: Integer;
  PlgInfo: TPluginInfo;
begin
  LibHandle := 0;
  Plugin := nil;
  case PlgKind of
    plgDLL:
      LibHandle := LoadLibrary(PChar(FileName));
    plgPackage:
      LibHandle := LoadPackage(FileName);
  end;

  if LibHandle = 0 then
    raise EJvLoadPluginError.Create('Error loading Plug-in "' + FileName + '"');

  try
    // Load the registration procedure
    RegisterProc := GetProcAddress(LibHandle, C_REGISTER_PLUGIN);
    if not Assigned(RegisterProc) then
      raise EJvLoadPluginError.Create('"' + FileName + '" is not a valid Plug-in. Export-function not found');

    // get the plugin
    Plugin := RegisterProc;
    if Plugin = nil then
      raise Exception.Create('No Plugin returned!');

    // make sure we don't load more copies of the plugin than allowed
    if Plugin.InstanceCount > 0 then // 0 = unlimited
    begin
      NumCopies := 0;
      for Counter := 0 to FPluginInfos.Count - 1 do
      begin
        if Plugins[Counter].PluginID = Plugin.PluginID then
          Inc(NumCopies);
      end;

      if NumCopies >= Plugin.InstanceCount then
      begin
        Plugin.Free;
        Exit; // Todo : Don't know what Skipload does here
      end;
    end;

    // initialize the plugin and add to list
    if AddCustomPlugin(Plugin) then
    begin
      PlgInfo := FPluginInfos.Last;
      PlgInfo.PluginKind := PlgKind;
      PlgInfo.Handle := LibHandle;
    end;

  except //!11    if - for whatever reason - an exception has occurred
    //            free Plugin and library
    // (rom) statements used twice could be wrapped in method
    Plugin.Free;
    case PlgKind of
      plgDLL:
        FreeLibrary(LibHandle);
      plgPackage:
        UnloadPackage(LibHandle);
    end;
    raise;
  end;
end;

// Load all plugins in the plugin-folder
// exceptions can only be seen through the OnErrorLoading-Event

procedure TJvPluginManager.LoadPlugins;
var
  AllowLoad: Boolean;
  FileName: string;
  Found: Integer;
  Path: string;
  Sr: TSearchRec;
begin
  // if the PluginPath is blank, we load from the app's folder.
  if FPluginFolder = '' then
    Path := ExtractFilePath(Application.ExeName)
  else
    Path := FPluginFolder;

  Path := IncludeTrailingPathDelimiter(Path);

  try
    Found := FindFirst(Path + '*.' + FExtension, 0, Sr);
    while Found = 0 do
    begin
      FileName := Sr.Name;
      AllowLoad := True;

      if (Assigned(FOnBeforeLoad)) then
        FOnBeforeLoad(Self, FileName, AllowLoad);

      if AllowLoad then
      begin
        try
          //! If one plugin made problems -> no other plugins where loaded
          //! To avoid that the try-except block was wrapped around here...
          LoadPlugin(Path + FileName, PluginKind);

          if (Assigned(FOnAfterLoad)) then
            FOnAfterLoad(Self, FileName);
        except
          on E: Exception do
            if Assigned(FOnErrorLoading) then
              FOnErrorLoading(Self, E.Message);
        end;
      end;
      Found := FindNext(Sr);
    end;
  finally
    FindClose(Sr);
  end;
end;

procedure TJvPluginManager.UnloadPlugin(Index: Integer);
var
  PlgI: TPluginInfo;
begin
  PlgI := FPluginInfos.Items[Index];
  PlgI.Plugin.Free;
  case PlgI.PluginKind of
    plgDLL:
      FreeLibrary(PlgI.Handle);
    plgPackage:
      UnloadPackage(PlgI.Handle);
  end;

  PlgI.Free;
  FPluginInfos.Delete(Index);
end;

procedure TJvPluginManager.SendMessage(PluginMessage: Longint; PluginParams: string);
var
  J: Integer;
begin
  for J := 0 to FPluginInfos.Count - 1 do
    Plugins[J].SendPluginMessage(PluginMessage, PluginParams);
end;

end.

