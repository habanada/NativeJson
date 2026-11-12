{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
program Demo12_ValidationRules;

{$I NativeJson.inc}

// DEMO 12 - Validation rules from attributes
//
//   Eight attributes describe the schema. JsonConvert.Validate checks
//   them at runtime.
//
//   The call is deliberately separate from reading: you get the object
//   AND the error list. EDI needs both, because you want to send the
//   partner one rejection with all points and not go through
//   the same round twelve times.

{$APPTYPE CONSOLE}

uses
  SysUtils,
  Rtti,
  Generics.Collections,
  Demo.Assert in 'Demo.Assert.pas',
  NativeJson.Main,
  NativeJson.Attributes,
  NativeJson.Schema.Attributes,
  NativeJson.Validation,
  NativeJson.NamingStrategy,
  NativeJson.Fluent,
  NativeJson.Serializer.Writer;

type
  TPostalAddress = class
  private
    FZipCode: string;
    FCity: string;
  public
    [JsonPattern('^\d{5}$')]
    property ZipCode: string read FZipCode write FZipCode;

    [JsonMinLength(2)]
    [JsonMaxLength(40)]
    property City: string read FCity write FCity;
  end;

  TLineItem = class
  private
    FArticle: string;
    FQuantity: Double;
  public
    [JsonMinLength(1)]
    property Article: string read FArticle write FArticle;

    [JsonRange(0.5, 1000)]
    [JsonMultipleOf(0.5)]
    property Quantity: Double read FQuantity write FQuantity;
  end;

  TPerson = class
  private
    FName: string;
    FAge: Integer;
    FPostalAddress: TPostalAddress;
    FAbbreviation: TArray<string>;
    FLineItems: TObjectList<TLineItem>;
  public
    constructor Create;
    destructor Destroy; override;

    [JsonMinLength(2)]
    [JsonMaxLength(60)]
    property Name: string read FName write FName;

    [JsonRange(18, 120)]
    property Age: Integer read FAge write FAge;

    property PostalAddress: TPostalAddress read FPostalAddress;

    [JsonUniqueItems]
    [JsonArrayLength(1, 3)]
    property Abbreviation: TArray<string> read FAbbreviation write FAbbreviation;

    [JsonArrayLength(1, 5)]
    property LineItems: TObjectList<TLineItem> read FLineItems;
  end;

  TRing = class
  private
    FName: string;
    FNeighbor: TRing;
  public
    [JsonMinLength(2)]
    property Name: string read FName write FName;
    property Neighbor: TRing read FNeighbor write FNeighbor;
  end;

constructor TPerson.Create;
begin
  inherited Create;
  FPostalAddress := TPostalAddress.Create;
  FLineItems := TObjectList<TLineItem>.Create(True);
end;

destructor TPerson.Destroy;
begin
  FLineItems.Free;
  FPostalAddress.Free;
  inherited;
end;

function BuildPerson: TPerson;
var
  P: TLineItem;
begin
  Result := TPerson.Create;
  Result.Name := 'Selahattin';
  Result.Age := 45;
  Result.PostalAddress.ZipCode := '12345';
  Result.PostalAddress.City := 'Exampletown';
  Result.Abbreviation := ['SB', 'SEL'];
  P := TLineItem.Create;
  P.Article := 'TRAFO-400';
  P.Quantity := 2.5;
  Result.LineItems.Add(P);
end;

function Report(Outcome: TJsonValidationResult; Index: Integer): string;
begin
  if (Index < 0) or (Index >= Outcome.Count) then Exit('(no error at this position)');
  Result := Outcome[Index].Path + ' [' + Outcome[Index].Rule + '] ' + Outcome[Index].Message;
end;

function RuleOf(Outcome: TJsonValidationResult; Index: Integer): string;
begin
  // Without this guard an empty error list raises an exception
  // instead of reporting a failed check - and you cannot see
  // which step actually stumbled.
  if (Index < 0) or (Index >= Outcome.Count) then Exit('(no error)');
  Result := Outcome[Index].Rule;
end;

function PathOf(Outcome: TJsonValidationResult; Index: Integer): string;
begin
  if (Index < 0) or (Index >= Outcome.Count) then Exit('(no error)');
  Result := Outcome[Index].Path;
end;

procedure ShowAll(Outcome: TJsonValidationResult);
var
  I: Integer;
begin
  for I := 0 to Outcome.Count - 1 do
    Writeln('       ', Report(Outcome, I));
end;

// ---------------------------------------------------------------------------

procedure Step1_CleanIsClean;
var
  Person: TPerson;
  Outcome: TJsonValidationResult;
begin
  Section('1. A valid record reports nothing');
  Person := BuildPerson;
  try
    Outcome := JsonConvert.Validate(Person);
    try
      ShowAll(Outcome);
      Check('Error count', 0, Outcome.Count);
      CheckTrue('IsValid', Outcome.IsValid, '');
    finally
      Outcome.Free;
    end;
  finally
    Person.Free;
  end;
end;

procedure Step2_AgeBelow18;
var
  Person: TPerson;
  Outcome: TJsonValidationResult;
begin
  Section('2. Age must not be below 18');
  Person := BuildPerson;
  try
    Person.Age := 12;
    Outcome := JsonConvert.Validate(Person);
    try
      ShowAll(Outcome);
      Check('Exactly one error', 1, Outcome.Count);
      Check('Path', '/Age', PathOf(Outcome, 0));
      Check('Rule', 'minimum', RuleOf(Outcome, 0));
      CheckContains('Message names the limit', '18', Outcome[0].Message);
      CheckContains('Message names the value', '12', Outcome[0].Message);
    finally
      Outcome.Free;
    end;

    Person.Age := 18;
    Outcome := JsonConvert.Validate(Person);
    try
      CheckTrue('Exactly 18 is allowed', Outcome.IsValid, Outcome.ToString);
    finally
      Outcome.Free;
    end;

    Person.Age := 121;
    Outcome := JsonConvert.Validate(Person);
    try
      Check('Upper bound applies too', 'maximum', RuleOf(Outcome, 0));
    finally
      Outcome.Free;
    end;
  finally
    Person.Free;
  end;
end;

procedure Step3_AllErrorsAtOnce;
var
  Person: TPerson;
  Outcome: TJsonValidationResult;
begin
  Section('3. ALL errors are reported, not just the first');
  Person := BuildPerson;
  try
    Person.Name := 'X';
    Person.Age := 7;
    Person.PostalAddress.ZipCode := 'ABC';
    Person.PostalAddress.City := 'V';

    Outcome := JsonConvert.Validate(Person);
    try
      ShowAll(Outcome);
      Check('Four errors', 4, Outcome.Count);
      CheckContains('Name is included', '/Name', Outcome.ToString);
      CheckContains('Age is included', '/Age', Outcome.ToString);
      CheckContains('ZipCode is included', '/PostalAddress/ZipCode', Outcome.ToString);
      CheckContains('City is included', '/PostalAddress/City', Outcome.ToString);
    finally
      Outcome.Free;
    end;
  finally
    Person.Free;
  end;
end;

procedure Step4_PathsInLists;
var
  Person: TPerson;
  P: TLineItem;
  Outcome: TJsonValidationResult;
  I: Integer;
begin
  Section('4. The path points to the position in the list');
  Person := BuildPerson;
  try
    for I := 1 to 2 do
    begin
      P := TLineItem.Create;
      P.Article := 'ART-' + IntToStr(I);
      P.Quantity := 1.0;
      Person.LineItems.Add(P);
    end;
    // The third line item (index 2) gets an odd quantity.
    Person.LineItems[2].Quantity := 1.3;

    Outcome := JsonConvert.Validate(Person);
    try
      ShowAll(Outcome);
      Check('One error', 1, Outcome.Count);
      Check('Path with index', '/LineItems/2/Quantity', PathOf(Outcome, 0));
      Check('Rule', 'multipleOf', RuleOf(Outcome, 0));
    finally
      Outcome.Free;
    end;
  finally
    Person.Free;
  end;
end;

procedure Step5_ListLength;
var
  Person: TPerson;
  P: TLineItem;
  Outcome: TJsonValidationResult;
  I: Integer;
begin
  Section('5. How many elements a list may have');
  Person := BuildPerson;
  try
    Person.LineItems.Clear;
    Outcome := JsonConvert.Validate(Person);
    try
      Check('Empty list is reported', 'minItems', RuleOf(Outcome, 0));
      Show('Msg', Report(Outcome, 0));
    finally
      Outcome.Free;
    end;

    for I := 1 to 6 do
    begin
      P := TLineItem.Create;
      P.Article := 'A' + IntToStr(I);
      P.Quantity := 1.0;
      Person.LineItems.Add(P);
    end;
    Outcome := JsonConvert.Validate(Person);
    try
      Check('Too many is reported', 'maxItems', RuleOf(Outcome, 0));
      Show('Msg', Report(Outcome, 0));
    finally
      Outcome.Free;
    end;
  finally
    Person.Free;
  end;
end;

procedure Step6_Duplicates;
var
  Person: TPerson;
  Outcome: TJsonValidationResult;
begin
  Section('6. Duplicate entries in the array');
  Person := BuildPerson;
  try
    Person.Abbreviation := ['SB', 'SEL', 'SB'];
    Outcome := JsonConvert.Validate(Person);
    try
      ShowAll(Outcome);
      Check('Duplicate entry is reported', 'uniqueItems', RuleOf(Outcome, 0));
      Check('Path', '/Abbreviation', PathOf(Outcome, 0));
    finally
      Outcome.Free;
    end;
  finally
    Person.Free;
  end;
end;

procedure Step7_CharsNotUnits;
var
  Person: TPerson;
  Outcome: TJsonValidationResult;
  Smiley: string;
begin
  Section('7. Length counts characters, not UTF-16 units');
  // A smiley is ONE character but takes TWO elements
  // of the string in Delphi. Length() would say 2 here and let the check
  // pass by mistake.
  Smiley := #$D83D#$DE00;
  Show('Length() says', IntToStr(Length(Smiley)));
  Show('Characters', IntToStr(CountCodePoints(Smiley)));
  CheckTrue('CountCodePoints counts code points', CountCodePoints(Smiley) = 1,
    IntToStr(CountCodePoints(Smiley)));

  Person := BuildPerson;
  try
    // City requires at least 2 characters. A single smiley is one,
    // even if Length() claims two.
    Person.PostalAddress.City := Smiley;
    Outcome := JsonConvert.Validate(Person);
    try
      ShowAll(Outcome);
      Check('One smiley is too short', 'minLength', RuleOf(Outcome, 0));
    finally
      Outcome.Free;
    end;

    Person.PostalAddress.City := Smiley + Smiley;
    Outcome := JsonConvert.Validate(Person);
    try
      CheckTrue('Two smileys are enough', Outcome.IsValid, Outcome.ToString);
    finally
      Outcome.Free;
    end;
  finally
    Person.Free;
  end;
end;

procedure Step8_PatternIsNotAnchored;
var
  PostalAddress: TPostalAddress;
  Outcome: TJsonValidationResult;
begin
  Section('8. Patterns - and why ^ and $ belong in them');
  PostalAddress := TPostalAddress.Create;
  try
    PostalAddress.City := 'Exampletown';

    PostalAddress.ZipCode := '12345';
    Outcome := JsonConvert.Validate(PostalAddress);
    try
      CheckTrue('Five digits are fine', Outcome.IsValid, Outcome.ToString);
    finally
      Outcome.Free;
    end;

    PostalAddress.ZipCode := 'D-12345';
    Outcome := JsonConvert.Validate(PostalAddress);
    try
      CheckContains('With prefix it fails', 'pattern', Outcome.ToString);
      Show('Msg', Report(Outcome, 0));
    finally
      Outcome.Free;
    end;
    Writeln('       The pattern is ^\d{5}$. Without ^ and $');
    Writeln('       "D-12345" would pass too - according to the specification');
    Writeln('       pattern only checks WHETHER the string matches somewhere.');
  finally
    PostalAddress.Free;
  end;
end;

procedure Step9_EmptyValuesAndNil;
var
  Person: TPerson;
  Outcome: TJsonValidationResult;
begin
  Section('9. Empty values and missing sub-objects');
  Person := BuildPerson;
  try
    // An empty string is shorter than the minimum - that is an error,
    // not an exception. "Missing entirely" is a matter for [JsonRequired] when reading.
    Person.Name := '';
    Outcome := JsonConvert.Validate(Person);
    try
      Check('Empty name is reported', 'minLength', RuleOf(Outcome, 0));
    finally
      Outcome.Free;
    end;

    Person.Name := 'Selahattin';
    Person.Abbreviation := nil;
    Outcome := JsonConvert.Validate(Person);
    try
      Check('Empty array is reported', 'minItems', RuleOf(Outcome, 0));
      Show('Msg', Report(Outcome, 0));
    finally
      Outcome.Free;
    end;
  finally
    Person.Free;
  end;
end;

procedure Step10_CycleDoesNotHang;
var
  A, B: TRing;
  Outcome: TJsonValidationResult;
begin
  Section('10. An object cycle must not hang the validation');
  A := TRing.Create;
  B := TRing.Create;
  try
    // Both names must satisfy their own rule (at least two
    // characters), otherwise the step does not test the cycle but only
    // my own carelessness.
    A.Name := 'AA';
    B.Name := 'BB';
    A.Neighbor := B;
    B.Neighbor := A;

    Outcome := JsonConvert.Validate(A);
    try
      CheckTrue('Runs through and reports nothing', Outcome.IsValid, Outcome.ToString);
    finally
      Outcome.Free;
    end;

    B.Name := 'X';
    Outcome := JsonConvert.Validate(A);
    try
      ShowAll(Outcome);
      Check('The neighbor is validated', '/Neighbor/Name', PathOf(Outcome, 0));
    finally
      Outcome.Free;
    end;
  finally
    A.Neighbor := nil;
    B.Neighbor := nil;
    B.Free;
    A.Free;
  end;
end;

procedure Step11_PathFollowsJsonName;
var
  Person: TPerson;
  Outcome: TJsonValidationResult;
  Settings: TJsonSettings;
begin
  Section('11. The path uses the JSON names, not the Delphi names');
  Person := BuildPerson;
  Settings := TJsonSettings.Create;
  try
    Person.Age := 5;
    Settings.CaseStyle := TJsonCaseStyle.jcSnake;

    Outcome := JsonConvert.Validate(Person, Settings);
    try
      ShowAll(Outcome);
      Check('Path in SnakeCase', '/age', PathOf(Outcome, 0));
      Writeln('       Otherwise the error points to a key that');
      Writeln('       the partner has never seen.');
    finally
      Outcome.Free;
    end;
  finally
    Settings.Free;
    Person.Free;
  end;
end;

procedure Step12_ShortForm;
var
  Person: TPerson;
  Failure: string;
begin
  Section('12. The short form for everyday use');
  Person := BuildPerson;
  try
    CheckTrue('IsValid for clean data', JsonConvert.IsValid(Person), '');

    Person.Age := 3;
    CheckTrue('IsValid reports False', not JsonConvert.IsValid(Person, Failure), '');
    CheckTrue('Error text is filled', Failure <> '', Failure);
    Show('ErrorText', Failure);
  finally
    Person.Free;
  end;
end;

// ---------------------------------------------------------------------------

begin
  try
    Title('DEMO 12 - VALIDATION RULES FROM ATTRIBUTES');

    Step1_CleanIsClean;
    Step2_AgeBelow18;
    Step3_AllErrorsAtOnce;
    Step4_PathsInLists;
    Step5_ListLength;
    Step6_Duplicates;
    Step7_CharsNotUnits;
    Step8_PatternIsNotAnchored;
    Step9_EmptyValuesAndNil;
    Step10_CycleDoesNotHang;
    Step11_PathFollowsJsonName;
    Step12_ShortForm;

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
