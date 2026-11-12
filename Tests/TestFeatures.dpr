{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
program TestFeatures;

{$I NativeJson.inc}

{$APPTYPE CONSOLE}

uses
  SysUtils,
  Classes,
  Generics.Collections,
  DateUtils,
  TypInfo,
  Rtti,
  
  // NativeJson units
  NativeJson.Main,
  NativeJson.Attributes,
  NativeJson.Fluent,
  NativeJson.Schema.Attributes,
  NativeJson.Serializer.Writer,
  NativeJson.Dom.JsonObject;

type
  // --- Test Entities ---

  TTestEnum = (enOne, enTwo, enThree);

  // 1. Basic & 8. Attributes
  TSimpleObj = class
  private
    FName: string;
    FAge: Integer;
  public
    [JsonProperty('user_name')] // NativeJson attribute
    property Name: string read FName write FName;
    property Age: Integer read FAge write FAge;
  end;

  TChildA = class;
  TChildB = class;

  // 4. Polymorphism
  [JsonKnownType('TChildA')]
  [JsonKnownType('TChildB')]
  TBaseItem = class
  public
    BaseProp: string;
  end;

  TChildA = class(TBaseItem)
  public
    UniqueA: Integer;
  end;

  TChildB = class(TBaseItem)
  public
    UniqueB: Boolean;
  end;

  // 5. Duck typing (not a TList, but iterable!)
  TCustomList = class
  private
    FItems: TList<string>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(const S: string);
    function GetEnumerator: TEnumerator<string>; // magic!
  end;

  // 6. Schema & Validation
  [JsonDescription('A validated user')]
  TValidUser = class
  private
    FEmail: string;
    FScore: Integer;
  public
    [JsonRequired]
    [JsonPattern('^.+@.+\..+$')]
    property Email: string read FEmail write FEmail;

    [JsonRange('0', '100')]
    property Score: Integer read FScore write FScore;
  end;

  // 9. Streams
  TFileContainer = class
  private
    FContent: TMemoryStream;
  public
    constructor Create;
    destructor Destroy; override;
    property Content: TMemoryStream read FContent;
  end;

  // 13. Only public fields, no properties
  TFieldOnlyObj = class
  public
    PublicField: string;
    Counter: Integer;
  end;

{ TCustomList Impl }
constructor TCustomList.Create; begin FItems := TList<string>.Create; end;
destructor TCustomList.Destroy; begin FItems.Free; inherited; end;
procedure TCustomList.Add(const S: string); begin FItems.Add(S); end;
function TCustomList.GetEnumerator: TEnumerator<string>; begin Result := FItems.GetEnumerator; end;

{ TFileContainer Impl }
constructor TFileContainer.Create; begin FContent := TMemoryStream.Create; end;
destructor TFileContainer.Destroy; begin FContent.Free; inherited; end;


// --- Test Runner ---

procedure PrintHeader(const Title: string);
begin
  Writeln('------------------------------------------------------------');
  Writeln('TEST: ' + Title);
  Writeln('------------------------------------------------------------');
end;

// --- TESTS ---

procedure Test1_Basic();
var
  Obj: TSimpleObj;
  Json: string;
begin
  PrintHeader('1. Basic Serialization (Attributes)');
  Obj := TSimpleObj.Create;
  try
    Obj.Name := 'Max Power';
    Obj.Age := 42;
    
    // NativeJson
    Json := JsonConvert.SerializeObject(Obj);
    Writeln('NativeJson: ' + Json);
    
    // Check
    if Pos('user_name', Json) > 0 then Writeln(' -> OK: Attribute respected')
    else Writeln(' -> FAIL: Attribute ignored');
  finally
    Obj.Free;
  end;
end;

procedure Test2_Collections();
var
  List: TObjectList<TSimpleObj>;
  O1, O2: TSimpleObj;
  Json: string;
begin
  PrintHeader('2. Generics & Collections');
  List := TObjectList<TSimpleObj>.Create;
  try
    O1 := TSimpleObj.Create; O1.Name := 'A';
    O2 := TSimpleObj.Create; O2.Name := 'B';
    List.Add(O1);
    List.Add(O2);
    
    Json := JsonConvert.SerializeObject(List);
    Writeln('Output: ' + Json);
    
    if (Pos('[', Json) = 1) and (Pos('"A"', Json) > 0) then Writeln(' -> OK')
    else Writeln(' -> FAIL');
  finally
    List.Free;
  end;
end;

procedure Test3_FluentConfig();
var
  Obj: TSimpleObj;
  Json: string;
  Settings: TJsonSettings;
begin
  PrintHeader('3. Fluent Configuration (Runtime Rename)');
  Obj := TSimpleObj.Create;
  Settings := TJsonSettings.Create;
  try
    Obj.Name := 'Secret Agent';
    Obj.Age := 99;
    
    // Fluent magic: we rename "Age" and ignore "Name" (despite the attribute!)
    Settings.Fluent.Entity<TSimpleObj>
      .Map('FAge').Name('years_old').EndMember
      .Map('FName').Ignore;
      
    Json := JsonConvert.SerializeObject(Obj, Settings);
    Writeln('Configured: ' + Json);
    
    if (Pos('years_old', Json) > 0) and (Pos('user_name', Json) = 0) then 
      Writeln(' -> OK: Fluent beat Attributes')
    else 
      Writeln(' -> FAIL');
  finally
    Obj.Free;
    Settings.Free;
  end;
end;

procedure Test4_Polymorphism();
var
  List: TObjectList<TBaseItem>;
  Settings: TJsonSettings;
  Json: string;
begin
  PrintHeader('4. Polymorphism ($type)');
  List := TObjectList<TBaseItem>.Create;
  Settings := TJsonSettings.Create;
  try
    List.Add(TChildA.Create);
    List.Add(TChildB.Create);
    
    // Enable auto type handling
    Settings.TypeNameHandling := TJsonTypeNameHandling.Auto;
    // The test classes only have public fields, otherwise the body would stay empty
    Settings.MemberSelection := [TJsonMemberType.mtProperties, TJsonMemberType.mtFields];

    Json := JsonConvert.SerializeObject(List, Settings);
    Writeln(Json);
    
    if Pos('$type', Json) > 0 then Writeln(' -> OK: Type discriminator found')
    else Writeln(' -> FAIL: No type info');
  finally
    List.Free;
    Settings.Free;
  end;
end;

procedure Test5_DuckTyping();
var
  List: TCustomList;
  Json: string;
begin
  PrintHeader('5. Duck Typing (Custom Iterables)');
  List := TCustomList.Create;
  try
    List.Add('Duck');
    List.Add('Typing');
    List.Add('Works');
    
    // NativeJson must recognize that the thing is iterable although it does not inherit from TList
    Json := JsonConvert.SerializeObject(List);
    Writeln(Json);
    
    if Json = '["Duck","Typing","Works"]' then Writeln(' -> OK: Detected as Array')
    else Writeln(' -> FAIL: ' + Json);
  finally
    List.Free;
  end;
end;

procedure Test6_SchemaGen();
var
  Schema: TJsonObject;
begin
  PrintHeader('6. Schema Generation (Validation)');
  Schema := JsonConvert.GenerateSchema<TValidUser>;
  try
    Writeln(Schema.ToJson);
    
    if Pos('"pattern"', Schema.ToJson) > 0 then Writeln(' -> OK: Pattern found') else Writeln(' -> FAIL');
    if Pos('"maximum"', Schema.ToJson) > 0 then Writeln(' -> OK: Range found') else Writeln(' -> FAIL');
  finally
    Schema.Free;
  end;
end;

procedure Test7_SpecialTypes();
var
  Dict: TDictionary<string, TGUID>;
  Json: string;
  ID: TGUID;
begin
  PrintHeader('7. Special Types (Dictionary + GUID)');
  Dict := TDictionary<string, TGUID>.Create;
  try
    CreateGUID(ID);
    Dict.Add('Key1', ID);
    
    Json := JsonConvert.SerializeObject(Dict);
    Writeln(Json);
    
    // Check GUID format (no braces around the value expected).
    // Checking for '{' alone does not work: the JSON object itself starts with it.
    if Pos('"{', Json) = 0 then Writeln(' -> OK: GUID clean')
    else Writeln(' -> WARN: GUID has brackets');
  finally
    Dict.Free;
  end;
end;

procedure Test9_Streams();
var
  Container: TFileContainer;
  Json: string;
  RawBytes: TBytes;
begin
  PrintHeader('9. Stream (Base64)');
  Container := TFileContainer.Create;
  try
    RawBytes := TEncoding.UTF8.GetBytes('Hello World');
    if Length(RawBytes) > 0 then Container.Content.WriteBuffer(RawBytes[0], Length(RawBytes));
    
    Json := JsonConvert.SerializeObject(Container);
    Writeln(Json);
    
    // "SGVsbG8gV29ybGQ=" is Base64 for "Hello World"
    if Pos('SGVsbG8gV29ybGQ=', Json) > 0 then Writeln(' -> OK: Base64 matches')
    else Writeln(' -> FAIL');
  finally
    Container.Free;
  end;
end;

procedure Test10_Enums();
var
  Val: TTestEnum;
  Settings: TJsonSettings;
  Json: string;
begin
  PrintHeader('10. Enum Handling');
  Val := enTwo;
  Settings := TJsonSettings.Create;
  try
    // Test 1: Name
    Settings.EnumHandling := TJsonEnumHandling.ByName;
    Json := JsonConvert.SerializeObject(TValue.From<TTestEnum>(Val), Settings);
    Writeln('ByName: ' + Json);
    if Pos('enTwo', Json) > 0 then Writeln(' -> OK');
    
    // Test 2: Int
    Settings.EnumHandling := TJsonEnumHandling.ByInteger;
    Json := JsonConvert.SerializeObject(TValue.From<TTestEnum>(Val), Settings);
    Writeln('ByInt:  ' + Json);
    if Pos('1', Json) > 0 then Writeln(' -> OK');
  finally
    Settings.Free;
  end;
end;


procedure Test11_DomOrder;
var
  Obj: NativeJson.Dom.JsonObject.TJsonObject;
  Json: string;
begin
  PrintHeader('11. DOM insertion order');
  Obj := TJsonObject.Create;
  try
    Obj.AddPair('z', 1);
    Obj.AddPair('a', 2);
    Obj.AddPair('m', 3);
    Json := Obj.ToJson;
    Writeln(Json);
    if Json <> '{"z":1,"a":2,"m":3}' then raise Exception.Create('DOM insertion order failed');
    Writeln(' -> OK');
  finally
    Obj.Free;
  end;
end;

procedure Test12_InvariantDate;
var
  Settings: TJsonSettings;
  SourceValue, RoundTrip: TDateTime;
  Json: string;
begin
  PrintHeader('12. Invariant custom date format');
  Settings := TJsonSettings.Create;
  try
    Settings.DateFormat := 'yyyy-MM-dd';
    SourceValue := EncodeDate(2026, 9, 4);
    Json := JsonConvert.SerializeObject(TValue.From<TDateTime>(SourceValue), Settings);
    RoundTrip := JsonConvert.DeserializeObject<TDateTime>(Json, Settings);
    Writeln(Json);
    if (Json <> '"2026-09-04"') or (Trunc(RoundTrip) <> Trunc(SourceValue)) then raise Exception.Create('Invariant date roundtrip failed');
    Writeln(' -> OK');
  finally
    Settings.Free;
  end;
end;

procedure Test13_MemberSelection;
var
  Obj: TFieldOnlyObj;
  Settings: TJsonSettings;
  JsonDefault, JsonWithFields, JsonPerType: string;
begin
  PrintHeader('13. Member selection at runtime');
  Obj := TFieldOnlyObj.Create;
  Settings := TJsonSettings.Create;
  try
    Obj.PublicField := 'visible';
    Obj.Counter := 7;

    JsonDefault := JsonConvert.SerializeObject(Obj);
    Writeln('Default:    ' + JsonDefault);
    if JsonDefault <> '{}' then raise Exception.Create('Default must not serialize public fields');

    Settings.MemberSelection := [TJsonMemberType.mtProperties, TJsonMemberType.mtFields];
    JsonWithFields := JsonConvert.SerializeObject(Obj, Settings);
    Writeln('Global:     ' + JsonWithFields);
    if Pos('"PublicField":"visible"', JsonWithFields) = 0 then raise Exception.Create('Global MemberSelection ignored');
    if Pos('"Counter":7', JsonWithFields) = 0 then raise Exception.Create('Global MemberSelection incomplete');

    Settings.MemberSelection := [];
    Settings.Fluent.Entity<TFieldOnlyObj>.SelectMembers([TJsonMemberType.mtFields]);
    JsonPerType := JsonConvert.SerializeObject(Obj, Settings);
    Writeln('Per Type:   ' + JsonPerType);
    if Pos('"PublicField":"visible"', JsonPerType) = 0 then raise Exception.Create('Fluent SelectMembers ignored');

    Writeln(' -> OK: cache returns its own member list per setting');
  finally
    Obj.Free;
    Settings.Free;
  end;
end;

begin
  try
    Writeln('=== NATIVE JSON FEATURE TEST SUITE ===');
    Writeln;
    
    Test1_Basic;
    Writeln;
    
    Test2_Collections;
    Writeln;
    
    Test3_FluentConfig;
    Writeln;
    
    Test4_Polymorphism;
    Writeln;
    
    Test5_DuckTyping;
    Writeln;
    
    Test6_SchemaGen;
    Writeln;
    
    Test7_SpecialTypes;
    Writeln;
    
    Test9_Streams;
    Writeln;
    
    Test10_Enums;
    Writeln;

    Test11_DomOrder;
    Writeln;

    Test12_InvariantDate;
    Writeln;

    Test13_MemberSelection;
    Writeln;

    Writeln('ALL TESTS COMPLETED.');
    ReadLn;
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.