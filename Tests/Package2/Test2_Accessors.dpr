{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
program Test2_Accessors;

{$I NativeJson.inc}

// TEST PACKAGE 2 - Redirected member access
//
//   [JsonGetter] and [JsonSetter] ONLY swap the access point.
//   The JSON name and the declared type stay as they are - that
//   is the difference from a converter, which transforms the value.
//
//   The most common case: a property without a setter should still be
//   filled when reading.

{$APPTYPE CONSOLE}

uses
  SysUtils,
  NativeJson.Compat,
  Rtti,
  Demo.Assert in '..\..\examples\Demos\Demo.Assert.pas',
  NativeJson.Main,
  NativeJson.Attributes,
  NativeJson.Schema.Attributes,
  NativeJson.Rtti.Cache,
  NativeJson.Serializer.Writer;

type
  // Property without a setter - without redirection it could only be written to JSON,
  // not filled from JSON.
  TInvoice = class
  private
    FNumber: string;
    FAmount: Currency;
  public
    [JsonSetter('FNumber')]
    property Number: string read FNumber;

    property Amount: Currency read FAmount write FAmount;
  end;

  // Access via methods instead of a field or property.
  TAccount = class
  private
    FBalance: Currency;
    FAccessCount: Integer;
  public
    function GetBalance: Currency;
    procedure SetBalance(const Val: Currency);

    [JsonGetter('GetBalance')]
    [JsonSetter('SetBalance')]
    property Balance: Currency read FBalance write FBalance;

    property AccessCount: Integer read FAccessCount;
  end;

  // The internal value and the external contract are separate.
  TArticle = class
  private
    FInternal: string;
  public
    [JsonGetter('FInternal')]
    [JsonSetter('FInternal')]
    property Designation: string read FInternal write FInternal;
  end;

  // The normal property value is empty, the redirected getter returns
  // something else. With [JsonMinLength(2)] both routes differ
  // in the result - removing the redirection would show up immediately.
  TDisplay = class
  private
    FRaw: string;
  public
    function Prepared: string;

    [JsonMinLength(2)]
    [JsonGetter('Prepared')]
    property Text: string read FRaw write FRaw;
  end;

  // The same class without redirection as a cross-check.
  TDisplayRaw = class
  private
    FRaw: string;
  public
    [JsonMinLength(2)]
    property Text: string read FRaw write FRaw;
  end;

  // Wrong target name - must be noticed when building the metadata.
  TWrongName = class
  private
    FValue: string;
  public
    [JsonSetter('DoesNotExist')]
    property Val: string read FValue;
  end;

  // Wrong type on the target field.
  TWrongType = class
  private
    FText: string;
    FNum: Integer;
  public
    [JsonSetter('FNum')]
    property Text: string read FText;
    property Num: Integer read FNum write FNum;
  end;

function TDisplay.Prepared: string;
begin
  // An empty raw value becomes a substitute text - the difference
  // by which the test recognizes the redirection.
  if FRaw = '' then Result := 'OK' else Result := FRaw;
end;

function TAccount.GetBalance: Currency;
begin
  Inc(FAccessCount);
  Result := FBalance;
end;

procedure TAccount.SetBalance(const Val: Currency);
begin
  Inc(FAccessCount);
  // A method can validate - a direct field access cannot.
  if Val < 0 then FBalance := 0 else FBalance := Val;
end;

function ErrorText(Action: TProc): string;
begin
  Result := '';
  try
    Action();
  except
    on E: Exception do Result := E.ClassName;
  end;
end;

// ---------------------------------------------------------------------------

procedure Step1_ReadOnlyBecomesFillable;
var
  B: TInvoice;
  Json: string;
begin
  Section('1. Property without a setter, with [JsonSetter] on the field');
  B := TInvoice.Create;
  try
    B.Amount := 99.95;
    Json := JsonConvert.SerializeObject(B);
    Show('written', Json);
    CheckContains('Number is written', '"Number":""', Json);
  finally
    B.Free;
  end;

  B := JsonConvert.DeserializeObject<TInvoice>('{"Number":"RE-4711","Amount":12.5}');
  try
    Check('Number arrives despite the missing setter', 'RE-4711', B.Number);
    CheckTrue('Amount as well', B.Amount = 12.5, CurrToStr(B.Amount));
  finally
    B.Free;
  end;
end;

procedure Step2_MethodsAsAccessors;
var
  K: TAccount;
  Json: string;
begin
  Section('2. Access via methods');
  K := JsonConvert.DeserializeObject<TAccount>('{"Balance":250.75}');
  try
    CheckTrue('Setter was called', K.AccessCount > 0, IntToStr(K.AccessCount));
    CheckTrue('Value arrived', K.Balance = 250.75, CurrToStr(K.Balance));
  finally
    K.Free;
  end;

  // The method may validate - exactly what a field access cannot do.
  K := JsonConvert.DeserializeObject<TAccount>('{"Balance":-5}');
  try
    CheckTrue('Setter corrected the value', K.Balance = 0, CurrToStr(K.Balance));
    Writeln('       A direct field access would have taken -5.');
  finally
    K.Free;
  end;

  K := TAccount.Create;
  try
    K.Balance := 42;
    Json := JsonConvert.SerializeObject(K);
    Show('written', Json);
    CheckContains('Getter returns the value', '"Balance":42', Json);
    CheckTrue('and was actually used', K.AccessCount > 0, IntToStr(K.AccessCount));
  finally
    K.Free;
  end;
end;

procedure Step3_JsonContractStaysTheSame;
var
  A, K: TArticle;
  Json: string;
begin
  Section('3. The JSON name does not change');
  A := TArticle.Create;
  try
    A.Designation := 'Widget 400';
    Json := JsonConvert.SerializeObject(A);
    Show('JSON', Json);
    CheckContains('The declared name is in the JSON', '"Designation"', Json);
    CheckNotContains('The field name is not', 'FInternal', Json);

    K := JsonConvert.DeserializeObject<TArticle>(Json);
    try
      Check('RoundTrip', 'Widget 400', K.Designation);
    finally
      K.Free;
    end;
  finally
    A.Free;
  end;
end;

procedure Step4_ErrorsShowUpImmediately;
begin
  Section('4. A wrong target must blow up, not stay silent');

  Check('Unknown name', 'EJsonRttiError',
    ErrorText(
      procedure
      var
        X: TWrongName;
      begin
        X := JsonConvert.DeserializeObject<TWrongName>('{"Val":"a"}');
        X.Free;
      end));

  Check('Wrong type on the target', 'EJsonRttiError',
    ErrorText(
      procedure
      var
        X: TWrongType;
      begin
        X := JsonConvert.DeserializeObject<TWrongType>('{"Text":"a"}');
        X.Free;
      end));

  Writeln('       Otherwise a typo in the target name would slip through');
  Writeln('       as "field missing in JSON" and never be noticed.');
end;

procedure Step5_ValidationSeesSameValue;
var
  WithRedirect: TDisplay;
  WithoutRedirect: TDisplayRaw;
  Failure, Json: string;
begin
  Section('5. Validation reads through the same access as the serializer');
  Writeln('       The raw value is empty, the getter returns "OK", the rule');
  Writeln('       requires at least two characters. So both routes must');
  Writeln('       differ in the result.');

  WithRedirect := TDisplay.Create;
  try
    WithRedirect.Text := '';
    Json := JsonConvert.SerializeObject(WithRedirect);
    Show('written', Json);
    CheckContains('The serializer uses the getter', '"Text":"OK"', Json);

    CheckTrue('Validation uses it too', JsonConvert.IsValid(WithRedirect, Failure),
      Failure);
  finally
    WithRedirect.Free;
  end;

  WithoutRedirect := TDisplayRaw.Create;
  try
    WithoutRedirect.Text := '';
    CheckTrue('Without redirection the same value fails',
      not JsonConvert.IsValid(WithoutRedirect, Failure), Failure);
    Show('Cross-check', Failure);
  finally
    WithoutRedirect.Free;
  end;

  // And the other way round: a raw value that violates the rule is NOT
  // rescued by the getter, because it passes it through unchanged.
  WithRedirect := TDisplay.Create;
  try
    WithRedirect.Text := 'X';
    CheckTrue('One character fails with redirection too',
      not JsonConvert.IsValid(WithRedirect, Failure), Failure);
  finally
    WithRedirect.Free;
  end;
end;

// ---------------------------------------------------------------------------

begin
  try
    Title('TEST PACKAGE 2 - REDIRECTED MEMBER ACCESS');

    Step1_ReadOnlyBecomesFillable;
    Step2_MethodsAsAccessors;
    Step3_JsonContractStaysTheSame;
    Step4_ErrorsShowUpImmediately;
    Step5_ValidationSeesSameValue;

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
