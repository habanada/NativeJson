{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
program Demo09_BinaryData;

{$I NativeJson.inc}

{
  DEMO 9 - Binary data, fixed order, required fields

  Bundles the three changes from the last round:

    1. TBytes is written as Base64 instead of a list of numbers.
       Previously every byte was written as a separate number - one
       megabyte of payload became about four megabytes of text.

    2. The order of the fields is now predictable. For equal Order the
       sorter uses the discovery index as the second key,
       because TList.Sort is a quicksort and therefore not stable.

    3. [JsonRequired] now really works - in the schema and when reading.
       Previously the attribute was pure documentation.
}

{$APPTYPE CONSOLE}

uses
  SysUtils,
  Rtti,
  Demo.Assert in 'Demo.Assert.pas',
  Demo.Model in 'Demo.Model.pas',
  NativeJson.Main,
  NativeJson.Dom.JsonObject,
  NativeJson.Attributes,
  NativeJson.Schema.Attributes,
  NativeJson.Fluent,
  NativeJson.Serializer.Writer;

type
  TDocument = class
  private
    FName: string;
    FContent: TBytes;
    FSize: Integer;
  public
    property Name: string read FName write FName;
    property Content: TBytes read FContent write FContent;
    property Size: Integer read FSize write FSize;
  end;

  TLogin = class
  private
    FUserName: string;
    FPassword: string;
    FRemark: string;
  public
    [JsonRequired]
    property UserName: string read FUserName write FUserName;

    [JsonRequired]
    property Password: string read FPassword write FPassword;

    property Remark: string read FRemark write FRemark;
  end;

function CreateBytes(ItemCount: Integer): TBytes;
var
  I: Integer;
begin
  SetLength(Result, ItemCount);
  for I := 0 to ItemCount - 1 do
    Result[I] := Byte(I mod 256);
end;

// ---------------------------------------------------------------------------

procedure Step1_BytesAsBase64;
var
  DocObj, CopyObj: TDocument;
  Json: string;
  RawData: TBytes;
begin
  Section('1. TBytes as Base64 instead of a list of numbers');
  DocObj := TDocument.Create;
  try
    RawData := TEncoding.UTF8.GetBytes('Hello World');
    DocObj.Name := 'greeting.txt';
    DocObj.Content := RawData;
    DocObj.Size := Length(RawData);

    Json := JsonConvert.SerializeObject(DocObj);
    Show('JSON', Json);

    CheckContains('Base64 instead of numbers', '"Content":"SGVsbG8gV29ybGQ="', Json);
    CheckNotContains('No list of numbers anymore', '"Content":[', Json);

    CopyObj := JsonConvert.DeserializeObject<TDocument>(Json);
    try
      Check('Name', 'greeting.txt', CopyObj.Name);
      Check('Length of the raw data', Length(RawData), Length(CopyObj.Content));
      CheckTrue('Content equal byte by byte',
        (Length(CopyObj.Content) > 0) and
        (TEncoding.UTF8.GetString(CopyObj.Content) = 'Hello World'),
        TEncoding.UTF8.GetString(CopyObj.Content));
    finally
      CopyObj.Free;
    end;
  finally
    DocObj.Free;
  end;
end;

procedure Step2_SpaceSaving;
var
  DocObj: TDocument;
  Json: string;
  RawData: TBytes;
  CharsPerByte: Double;
begin
  Section('2. How much space this saves');
  DocObj := TDocument.Create;
  try
    RawData := CreateBytes(10000);
    DocObj.Name := 'large.bin';
    DocObj.Content := RawData;

    Json := JsonConvert.SerializeObject(DocObj);
    CharsPerByte := Length(Json) / Length(RawData);

    Show('RawData', Format('%d bytes', [Length(RawData)]));
    Show('JSON', Format('%d chars', [Length(Json)]));
    Show('Ratio', Format('%.2f chars per byte', [CharsPerByte]));

    // Base64 needs about 1.34 chars per byte. The old list of numbers
    // needed about 3.8 on average - every number plus a comma.
    CheckTrue('Below 1.5 chars per byte', CharsPerByte < 1.5,
      Format('%.2f', [CharsPerByte]));
    Writeln('       For comparison: as a list of numbers it would have been about 3.8.');
  finally
    DocObj.Free;
  end;
end;

procedure Step3_EmptyAndOldData;
var
  DocObj: TDocument;
  Json: string;
begin
  Section('3. Empty data and the old format');
  DocObj := TDocument.Create;
  try
    Json := JsonConvert.SerializeObject(DocObj);
    Show('Empty', Json);
    // An unassigned TBytes is a nil array. The serializer
    // writes null for it before any converter is asked.
    CheckContains('Empty array becomes null', '"Content":null', Json);
  finally
    DocObj.Free;
  end;

  // Old files with a list of numbers must stay readable
  DocObj := JsonConvert.DeserializeObject<TDocument>(
    '{"Name":"old.bin","Content":[72,101,108,108,111],"Size":5}');
  try
    Check('Old format: name', 'old.bin', DocObj.Name);
    Check('Old format: length', 5, Length(DocObj.Content));
    CheckTrue('Old format: content correct',
      TEncoding.UTF8.GetString(DocObj.Content) = 'Hello',
      TEncoding.UTF8.GetString(DocObj.Content));
  finally
    DocObj.Free;
  end;
end;

procedure Step4_StableOrder;
var
  Address: TAddress;
  FirstRun, SecondRun, Third: string;
  S1, S2, S3: TJsonSettings;
begin
  Section('4. The order is the same across runs');
  Address := TAddress.Create;
  try
    Address.Street := 'Main Road 1';
    Address.ZipCode := '12345';
    Address.City := 'Exampletown';
    Address.Country := 'DE';

    // Three separate configurations force three separate
    // cache entries and therefore three real analysis runs.
    S1 := TJsonSettings.Create;
    S2 := TJsonSettings.Create;
    S3 := TJsonSettings.Create;
    try
      S1.Fluent.Entity<TAddress>.Map('City').Required(True).EndMember;
      S2.Fluent.Entity<TAddress>.Map('ZipCode').Required(True).EndMember;
      S3.Fluent.Entity<TAddress>.Map('Country').Required(True).EndMember;

      FirstRun := JsonConvert.SerializeObject(Address, S1);
      SecondRun := JsonConvert.SerializeObject(Address, S2);
      Third := JsonConvert.SerializeObject(Address, S3);
    finally
      S3.Free;
      S2.Free;
      S1.Free;
    end;

    Show('Run 1', FirstRun);
    Show('Run 2', SecondRun);
    Show('Run 3', Third);

    Check('Run 1 and 2 identical', FirstRun, SecondRun);
    Check('Run 2 and 3 identical', SecondRun, Third);
    Writeln('       Without the second sort key the order of fields with');
    Writeln('       equal rank would have been random.');
  finally
    Address.Free;
  end;
end;

procedure Step5_RequiredFieldsByAttribute;
var
  Login: TLogin;
begin
  Section('5. [JsonRequired] works when reading');

  // Complete -> passes
  Login := JsonConvert.DeserializeObject<TLogin>(
    '{"UserName":"selahattin","Password":"secret","Remark":"Test account"}');
  try
    Check('Complete record', 'selahattin', Login.UserName);
    Check('Optional field', 'Test account', Login.Remark);
  finally
    Login.Free;
  end;

  CheckError('Missing password is reported',
    procedure
    var
      A: TLogin;
    begin
      A := JsonConvert.DeserializeObject<TLogin>('{"UserName":"selahattin"}');
      A.Free;
    end);

  CheckError('Password set to null is reported',
    procedure
    var
      A: TLogin;
    begin
      A := JsonConvert.DeserializeObject<TLogin>(
        '{"UserName":"selahattin","Password":null}');
      A.Free;
    end);

  // Remark is not a required field
  Login := JsonConvert.DeserializeObject<TLogin>(
    '{"UserName":"a","Password":"b"}');
  try
    Check('Optional field may be missing', '', Login.Remark);
  finally
    Login.Free;
  end;
end;

procedure Step6_RequiredFieldsInSchema;
var
  Schema: TJsonObject;
  S: string;
begin
  Section('6. [JsonRequired] is now in the schema too');
  Schema := JsonConvert.GenerateSchema<TLogin>;
  try
    S := Schema.ToJson;
    Show('Schema', S);

    CheckContains('required block present', '"required"', S);
    CheckContains('UserName is required', '"UserName"', S);
    CheckContains('Password is required', '"Password"', S);

    // A required field must not be described as nullable at the same
    // time - the deserializer does not allow null there either.
    CheckContains('Required field is not nullable',
      '"Password":{"type":"string"}', S);
    CheckContains('Optional field stays nullable',
      '"Remark":{"type":["string","null"]}', S);
  finally
    Schema.Free;
  end;
end;

// ---------------------------------------------------------------------------

begin
  try
    Title('DEMO 9 - BINARY DATA, ORDER, REQUIRED FIELDS');

    Step1_BytesAsBase64;
    Step2_SpaceSaving;
    Step3_EmptyAndOldData;
    Step4_StableOrder;
    Step5_RequiredFieldsByAttribute;
    Step6_RequiredFieldsInSchema;

    ExitCode := Summary;
  except
    on E: Exception do
    begin
      Writeln('ABORTED: ', E.ClassName, ': ', E.Message);
      ExitCode := 2;
    end;
  end;
  if ParamCount = 0 then
  begin
    Writeln;
    Writeln('Press Enter ...');
    Readln;
  end;
end.
