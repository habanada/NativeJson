{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
program Test2_NullAndEmpty;

{$I NativeJson.inc}

// TEST PACKAGE 2 - null, empty and missing
//
//   The three cases
//
//       "Field": null        field is explicitly empty
//       "Field": ""          field is an empty string
//       (field missing)     field was not transmitted
//
//   do NOT mean the same, and a serializer must keep them
//   apart.

{$APPTYPE CONSOLE}

uses
  SysUtils,
  Rtti,
  Generics.Collections,
  Demo.Assert in '..\..\examples\Demos\Demo.Assert.pas',
  NativeJson.Main,
  NativeJson.Attributes,
  NativeJson.Serializer.Writer;

type
  TSubObject = class
  private
    FTitle: string;
  public
    property Title: string read FTitle write FTitle;
  end;

  TEnvelope = class
  private
    FNum: Integer;
    FText: string;
    FYesNo: Boolean;
    FChild: TSubObject;
    FItemList: TObjectList<TSubObject>;
  public
    constructor Create;
    destructor Destroy; override;
    property Num: Integer read FNum write FNum;
    property Text: string read FText write FText;
    property YesNo: Boolean read FYesNo write FYesNo;
    property Child: TSubObject read FChild write FChild;
    property TheList: TObjectList<TSubObject> read FItemList;
  end;

constructor TEnvelope.Create;
begin
  inherited Create;
  FItemList := TObjectList<TSubObject>.Create(True);
end;

destructor TEnvelope.Destroy;
begin
  FItemList.Free;
  FChild.Free;
  inherited;
end;

function Preset: TEnvelope;
var
  U: TSubObject;
begin
  Result := TEnvelope.Create;
  Result.Num := 42;
  Result.Text := 'before';
  Result.YesNo := True;
  Result.Child := TSubObject.Create;
  Result.Child.Title := 'Child';
  U := TSubObject.Create;
  U.Title := 'Entry';
  Result.TheList.Add(U);
end;

function ReadInto(const Json: string): TEnvelope;
begin
  Result := Preset;
  try
    JsonConvert.PopulateObject(Result, Json);
  except
    Result.Free;
    raise;
  end;
end;

// ---------------------------------------------------------------------------

procedure Step1_NullOnScalars;
var
  H: TEnvelope;
begin
  Section('1. null on a number, text and boolean field');
  H := ReadInto('{"Num":null,"Text":null,"YesNo":null}');
  try
    Show('after', JsonConvert.SerializeObject(H));
    Check('Number is set to 0', 0, H.Num);
    Check('Text is cleared', '', H.Text);
    Check('Boolean becomes False', False, H.YesNo);
    Writeln('       So null clears, it does not keep the old value.');
  finally
    H.Free;
  end;
end;

procedure Step2_MissingField;
var
  H: TEnvelope;
begin
  Section('2. A field that does not appear in the JSON at all');
  H := ReadInto('{"Text":"new"}');
  try
    Check('Transmitted field is set', 'new', H.Text);
    Check('Missing field stays unchanged', 42, H.Num);
    Check('Missing boolean stays', True, H.YesNo);
    Writeln('       That is the difference from null - exactly the case');
    Writeln('       a PATCH interface needs.');
  finally
    H.Free;
  end;
end;

procedure Step3_EmptyString;
var
  H: TEnvelope;
begin
  Section('3. An empty string is not null');
  H := ReadInto('{"Text":""}');
  try
    Check('Empty text is assigned', '', H.Text);
    CheckContains('and is also written that way', '"Text":""',
      JsonConvert.SerializeObject(H));
  finally
    H.Free;
  end;
end;

procedure Step4_NullOnSubObject;
var
  H: TEnvelope;
begin
  Section('4. null on a sub-object');
  H := ReadInto('{"Child":null}');
  try
    Show('after', JsonConvert.SerializeObject(H));
    // There are two defensible answers here. We record which one
    // we give, so that it does not change unnoticed.
    CheckTrue('The existing sub-object stays', H.Child <> nil,
      'Child is nil');
    Writeln('       Freeing it would be dangerous: the library does not know');
    Writeln('       who owns the object.');
  finally
    H.Free;
  end;
end;

procedure Step5_EmptyArrayAndObject;
var
  H: TEnvelope;
begin
  Section('5. Empty array and empty object');
  H := ReadInto('{"TheList":[]}');
  try
    Check('Empty array clears the list', 0, H.TheList.Count);
  finally
    H.Free;
  end;

  H := ReadInto('{"Child":{}}');
  try
    CheckTrue('Empty object leaves the sub-object', H.Child <> nil, '');
    Check('and changes nothing about it', 'Child', H.Child.Title);
  finally
    H.Free;
  end;

  H := ReadInto('{}');
  try
    Check('Completely empty JSON changes nothing', 42, H.Num);
    Check('not the text either', 'before', H.Text);
  finally
    H.Free;
  end;
end;

procedure Step6_NullInAList;
var
  H: TEnvelope;
begin
  Section('6. null as an element of a list');
  H := ReadInto('{"TheList":[{"Title":"A"},null,{"Title":"C"}]}');
  try
    Show('after', JsonConvert.SerializeObject(H));
    Check('All three slots are kept', 3, H.TheList.Count);
    CheckTrue('The middle one is nil', H.TheList[1] = nil, '');
    Check('The first is correct', 'A', H.TheList[0].Title);
    Check('The third is correct', 'C', H.TheList[2].Title);
    Writeln('       Important: the position must not shift, otherwise');
    Writeln('       position 2 later points to the wrong record.');
  finally
    H.Free;
  end;
end;

procedure Step7_NullOnWrite;
var
  H: TEnvelope;
  Json: string;
begin
  Section('7. How a nil sub-object is written');
  H := TEnvelope.Create;
  try
    H.Text := 'text only';
    Json := JsonConvert.SerializeObject(H);
    Show('Default', Json);
    CheckContains('nil becomes null', '"Child":null', Json);

    Json := JsonConvert.SerializeObject(H,
      procedure(S: TJsonSettings)
      begin
        S.NullValueHandling := TJsonNullValueHandling.Ignore;
      end);
    Show('With Ignore', Json);
    CheckNotContains('With Ignore the field is dropped', '"Child"', Json);
  finally
    H.Free;
  end;
end;

// ---------------------------------------------------------------------------

begin
  try
    Title('TEST PACKAGE 2 - NULL, EMPTY AND MISSING');

    Step1_NullOnScalars;
    Step2_MissingField;
    Step3_EmptyString;
    Step4_NullOnSubObject;
    Step5_EmptyArrayAndObject;
    Step6_NullInAList;
    Step7_NullOnWrite;

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
