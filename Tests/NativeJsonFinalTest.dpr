{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
program NativeJsonFinalTest;

{$I NativeJson.inc}

{$APPTYPE CONSOLE}

uses
  SysUtils,
  DateUtils,
  Generics.Collections,
  NativeJson.Main,
  NativeJson.Attributes,
  NativeJson.Dom.Value,
  NativeJson.Serializer.Writer; // for enums

type
  TUserRole = (User, Admin);

  // Feature: Immutable Object via [JsonConstructor]
  TUser = class
  private
    FName: string;
    FBirthday: TDateTime;
    FRole: TUserRole;
    FShowSecret: Boolean;
    FSecretData: string;
    FBestFriend: TUser;
  public
    // Constructor injection!
    [JsonConstructor]
    constructor Create(AName: string; ABirthday: TDateTime; ARole: TUserRole);
    
    // Properties (Read-Only)
    property Name: string read FName;
    property Birthday: TDateTime read FBirthday;
    property Role: TUserRole read FRole;
    property BestFriend: TUser read FBestFriend write FBestFriend;

    // Feature: conditional serialization
    property ShowSecret: Boolean read FShowSecret write FShowSecret; // control
    property SecretData: string read FSecretData write FSecretData;

    function ShouldSerializeSecretData: Boolean;
  end;

{ TUser }

constructor TUser.Create(AName: string; ABirthday: TDateTime; ARole: TUserRole);
begin
  FName := AName;
  FBirthday := ABirthday;
  FRole := ARole;
  FShowSecret := False; // default
end;

function TUser.ShouldSerializeSecretData: Boolean;
begin
  Result := FShowSecret;
end;

// -----------------------------------------------------------------------------

procedure RunFinalCheck;
var
  Alice, Bob, LoadedAlice: TUser;
  Json: string;
  MyFormat: string;
begin
  Writeln('=== NATIVEJSON FINAL SYSTEM CHECK ===');
  Writeln;

  // 1. Prepare data (cyclic reference!)
  Alice := TUser.Create('Alice', EncodeDate(1990, 5, 20), TUserRole.Admin);
  Bob := TUser.Create('Bob', EncodeDate(1995, 8, 15), TUserRole.User);
  
  try
    Alice.BestFriend := Bob;
    Bob.BestFriend := Alice; // CYCLE! A->B->A

    // Setup for conditional serialization
    Alice.SecretData := 'MyPassword123';
    Alice.ShowSecret := False; // should NOT end up in the JSON

    // 2. Serialize (with custom date, enum as int, reference handling)
    Writeln('[Step 1] Serialization...');
    MyFormat := 'dd-mm-yyyy';
    
    // HERE all new features are used at once:
    // - TJsonFormatting.Indented
    // - TJsonEnumHandling.ByInteger (Admin becomes 1)
    // - DateFormat 'dd-mm-yyyy'
    // - TJsonPreserveReferences.Objects (prevents a crash and uses $id/$ref)
    
    Json := JsonConvert.SerializeObject(
      Alice, 
      TJsonFormatting.Indented, 
      TJsonEnumHandling.ByInteger, 
      MyFormat, 
      TJsonPreserveReferences.Objects
    );

    Writeln('JSON Output:');
    Writeln(Json);
    Writeln;

    // Checks on the string
    if Pos('20-05-1990', Json) > 0 then Writeln('[OK] Custom Date Format') else Writeln('[FAIL] Date Format');
    if Pos('"Role": 1', Json) > 0 then Writeln('[OK] Enum as Integer') else Writeln('[FAIL] Enum as Integer');
    if Pos('MyPassword123', Json) = 0 then Writeln('[OK] Conditional Serialization (Secret hidden)') else Writeln('[FAIL] Secret is visible!');
    if Pos('$id', Json) > 0 then Writeln('[OK] Reference IDs generated') else Writeln('[FAIL] No IDs found');
    if Pos('$ref', Json) > 0 then Writeln('[OK] Reference Loop handled via $ref') else Writeln('[FAIL] Loop not handled correctly');

    // 3. Deserialize (the stress test for the constructor)
    Writeln;
    Writeln('[Step 2] Deserialization (Restore Graph)...');
    
    // The deserializer has to:
    // - understand the date '20-05-1990'
    // - find and use the constructor Create(AName...)
    // - link the references ($ref) back to real pointers
    LoadedAlice := JsonConvert.DeserializeObject<TUser>(Json, MyFormat);
    
    try
      if LoadedAlice.Name = 'Alice' then Writeln('[OK] Constructor Injection (Name)') else Writeln('[FAIL] Name wrong');
      if YearOf(LoadedAlice.Birthday) = 1990 then Writeln('[OK] Date Parsed correctly') else Writeln('[FAIL] Date wrong');
      if LoadedAlice.Role = TUserRole.Admin then Writeln('[OK] Enum Parsed correctly') else Writeln('[FAIL] Enum wrong');
      
      // The graph check
      if LoadedAlice.BestFriend <> nil then
      begin
        Writeln('[OK] Child Object loaded');
        if LoadedAlice.BestFriend.Name = 'Bob' then Writeln('[OK] Child Data correct');
        
        // Does Bob.BestFriend really point to exactly the same Alice instance again?
        if LoadedAlice.BestFriend.BestFriend = LoadedAlice then
          Writeln('[OK] *** REFERENCE CYCLE RESTORED PERFECTLY ***')
        else
          Writeln('[FAIL] Object Identity lost (Different instances)');
      end
      else
        Writeln('[FAIL] Child object missing');

    finally
      LoadedAlice.Free; 
      // Freeing the root is enough here. With shared references the owner
      // has to be chosen explicitly, because Bob also references Alice.
    end;

  finally
    // Careful with Free because of the cycle in the original (break it manually or use ReportMemoryLeaksOnShutdown)
    Alice.BestFriend := nil; 
    Bob.BestFriend := nil;
    Alice.Free;
    Bob.Free;
  end;
  
  ReadLn;
end;

begin
  try
    RunFinalCheck;
  except
    on E: Exception do
      Writeln('CRASH: ' + E.ClassName + ': ' + E.Message);
  end;
end.