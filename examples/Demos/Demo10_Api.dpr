{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
program Demo10_Api;

{$I NativeJson.inc}

// DEMO 10 - The four API extensions
//
//   1. Stream and file symmetry: whatever is written can also
//      be read back, without a detour through a string.
//   2. Settings without try/finally: an anonymous method configures,
//      the settings object lives and dies within the call.
//   3. TryDeserialize: errors as a return value instead of an exception.
//   4. JsonConvert.DefaultSettings: set once per application.

{$APPTYPE CONSOLE}

uses
  SysUtils,
  Classes,
  System.IOUtils,
  Rtti,
  Generics.Collections,
  Demo.Assert in 'Demo.Assert.pas',
  Demo.Model in 'Demo.Model.pas',
  NativeJson.Main,
  NativeJson.Attributes,
  NativeJson.Dom.Value,
  NativeJson.NamingStrategy,
  NativeJson.Fluent,
  NativeJson.Serializer.Writer;

type
  TCustomerList = TObjectList<TCustomer>;

type
  // Deliberately with compound names: only then can you see whether
  // CamelCase and SnakeCase really behave differently.
  TOrderHeader = class
  private
    FInvoiceNumber: string;
    FCustomerName: string;
    FTotalAmount: Double;
  public
    property InvoiceNumber: string read FInvoiceNumber write FInvoiceNumber;
    property CustomerName: string read FCustomerName write FCustomerName;
    property TotalAmount: Double read FTotalAmount write FTotalAmount;
  end;

function BuildCustomer: TCustomer;
begin
  Result := TCustomer.Create;
  Result.Number := '4711';
  Result.Name := 'Miller Meyer Ltd';
  Result.Email := 'purchasing@customer.example';
  Result.Address.Street := 'Example Street 1';
  Result.Address.ZipCode := '12345';
  Result.Address.City := 'Exampletown';
  Result.Address.Country := 'DE';
end;

function BuildHeader: TOrderHeader;
begin
  Result := TOrderHeader.Create;
  Result.InvoiceNumber := 'B-2026-0042';
  Result.CustomerName := 'Miller Meyer Ltd';
  Result.TotalAmount := 1234.5;
end;

function TargetFile: string;
begin
  Result := TPath.Combine(TPath.GetTempPath, 'nativejson_demo10.json');
end;

// ---------------------------------------------------------------------------

procedure Step1_FileRoundTrip;
var
  Original, ReadBack: TCustomer;
  TheFile: string;
begin
  Section('1. SerializeToFile and DeserializeFromFile');
  TheFile := TargetFile;
  Original := BuildCustomer;
  try
    JsonConvert.SerializeToFile(Original, TheFile);
    CheckTrue('File was created', TFile.Exists(TheFile), TheFile);
    Show('Size', Format('%d bytes', [Length(TFile.ReadAllBytes(TheFile))]));

    ReadBack := JsonConvert.DeserializeFromFile<TCustomer>(TheFile);
    try
      Check('Number', '4711', ReadBack.Number);
      Check('Name', 'Miller Meyer Ltd', ReadBack.Name);
      Check('City', 'Exampletown', ReadBack.Address.City);
    finally
      ReadBack.Free;
    end;
  finally
    Original.Free;
    if TFile.Exists(TheFile) then TFile.Delete(TheFile);
  end;
end;

procedure Step2_StreamRoundTrip;
var
  Original, ReadBack: TCustomer;
  Strm: TMemoryStream;
  Msg: string;
begin
  Section('2. The same route through a memory stream');
  Original := BuildCustomer;
  Strm := TMemoryStream.Create;
  try
    JsonConvert.SerializeObjectToStream(Original, Strm);
    Show('Bytes in the stream', IntToStr(Strm.Size));
    CheckTrue('Stream is not empty', Strm.Size > 0, IntToStr(Strm.Size));

    // Writing leaves the position at the end. Whoever forgets that reads
    // zero bytes; the error message says to reset the position.
    Msg := '';
    try
      JsonConvert.DeserializeFromStream<TCustomer>(Strm).Free;
    except
      on E: Exception do Msg := E.Message;
    end;
    Show('Without rewinding', Msg);
    CheckContains('Message names the cause', 'Position', Msg);

    Strm.Position := 0;

    ReadBack := JsonConvert.DeserializeFromStream<TCustomer>(Strm);
    try
      Check('Number', '4711', ReadBack.Number);
      Check('Street', 'Example Street 1', ReadBack.Address.Street);
    finally
      ReadBack.Free;
    end;
  finally
    Strm.Free;
    Original.Free;
  end;
end;

procedure Step3_BomIsUnderstood;
var
  Original, ReadBack: TCustomer;
  Strm: TMemoryStream;
  Raw, WithBom: TBytes;
  SpecialName: string;
begin
  Section('3. No own BOM, a foreign BOM is swallowed');
  SpecialName := 'Wholesaler ' + #$00C4 + #$00D6 + #$00DC + ' ' + #$20AC + ' AG';
  Original := BuildCustomer;
  Strm := TMemoryStream.Create;
  try
    Original.Name := SpecialName;
    JsonConvert.SerializeObjectToStream(Original, Strm);

    SetLength(Raw, Strm.Size);
    Strm.Position := 0;
    Strm.ReadBuffer(Raw[0], Length(Raw));

    // RFC 8259 forbids a leading BOM; the writer's own byte buffer writes none.
    CheckTrue('No BOM at the start',
      (Length(Raw) >= 3) and not ((Raw[0] = $EF) and (Raw[1] = $BB) and (Raw[2] = $BF)),
      Format('%.2x %.2x %.2x', [Raw[0], Raw[1], Raw[2]]));

    // Foreign tools write one anyway. The reader has to swallow it,
    // otherwise the invisible character sits before the opening brace.
    SetLength(WithBom, Length(Raw) + 3);
    WithBom[0] := $EF;
    WithBom[1] := $BB;
    WithBom[2] := $BF;
    Move(Raw[0], WithBom[3], Length(Raw));

    Strm.Clear;
    Strm.WriteBuffer(WithBom[0], Length(WithBom));
    Strm.Position := 0;

    ReadBack := JsonConvert.DeserializeFromStream<TCustomer>(Strm);
    try
      Check('Special characters intact despite BOM', SpecialName, ReadBack.Name);
    finally
      ReadBack.Free;
    end;
  finally
    Strm.Free;
    Original.Free;
  end;
end;

procedure Step4_SettingsWithoutTryFinally;
var
  Header: TOrderHeader;
  IndentedText, Standard: string;
begin
  Section('4. Settings as an anonymous method');
  Header := BuildHeader;
  try
    // The old way took five lines: create, try, set, finally, free.
    IndentedText := JsonConvert.SerializeObject(Header,
      procedure(S: TJsonSettings)
      begin
        S.Formatting := TJsonFormatting.Indented;
        S.CaseStyle := TJsonCaseStyle.jcSnake;
      end);

    Show('Indented', Copy(IndentedText, 1, 50) + ' ...');
    CheckContains('SnakeCase applies', '"invoice_number"', IndentedText);
    CheckContains('Indentation applies', sLineBreak, IndentedText);

    Standard := JsonConvert.SerializeObject(Header);
    Show('Without configuration', Standard);
    CheckContains('Without configuration the original stays', '"InvoiceNumber"', Standard);
    CheckNotContains('No indentation', sLineBreak, Standard);
  finally
    Header.Free;
  end;
end;

procedure Step5_TryDeserialize;
var
  Customer: TCustomer;
  Failure: string;
  Ok: Boolean;
begin
  Section('5. TryDeserialize instead of an exception');

  Customer := nil;
  Ok := JsonConvert.TryDeserializeObject<TCustomer>(
    '{"Number":"9","Name":"Clean"}', Customer, Failure);
  try
    CheckTrue('Valid JSON reports True', Ok, BoolToStr(Ok, True));
    Check('Error text is empty', '', Failure);
    CheckTrue('Object arrived', Customer <> nil, '');
    if Customer <> nil then Check('Name', 'Clean', Customer.Name);
  finally
    Customer.Free;
  end;

  Customer := nil;
  Ok := JsonConvert.TryDeserializeObject<TCustomer>('this is not json', Customer, Failure);
  try
    CheckTrue('Garbage reports False', not Ok, BoolToStr(Ok, True));
    CheckTrue('Error text is filled', Failure <> '', Failure);
    CheckTrue('No half object returned', Customer = nil, '');
    Show('Msg', Failure);
  finally
    Customer.Free;
  end;

  Customer := nil;
  Ok := JsonConvert.TryDeserializeObject<TCustomer>('{"Number":"1",', Customer, Failure);
  try
    CheckTrue('Truncated JSON reports False', not Ok, BoolToStr(Ok, True));
  finally
    Customer.Free;
  end;

  Customer := nil;
  Ok := JsonConvert.TryDeserializeFromFile<TCustomer>(
    TPath.Combine(TPath.GetTempPath, 'does_not_exist_4711.json'), Customer, Failure);
  try
    CheckTrue('Missing file reports False', not Ok, BoolToStr(Ok, True));
    CheckTrue('Error text names the file', Pos('4711', Failure) > 0, Failure);
  finally
    Customer.Free;
  end;
end;

procedure Step6_DefaultSettings;
var
  Header: TOrderHeader;
  Json: string;
begin
  Section('6. DefaultSettings apply to the whole application');
  Header := BuildHeader;
  try
    JsonConvert.DefaultSettings :=
      procedure(S: TJsonSettings)
      begin
        S.CaseStyle := TJsonCaseStyle.jcSnake;
      end;
    try
      Json := JsonConvert.SerializeObject(Header);
      Show('With default', Json);
      CheckContains('SnakeCase without settings on the call', '"invoice_number"', Json);

      // A custom configuration may override the default.
      Json := JsonConvert.SerializeObject(Header,
        procedure(S: TJsonSettings)
        begin
          S.CaseStyle := TJsonCaseStyle.jcCamel;
        end);
      Show('Call beats default', Json);
      CheckContains('CamelCase wins', '"invoiceNumber"', Json);
      CheckNotContains('SnakeCase is gone', '"invoice_number"', Json);
    finally
      JsonConvert.DefaultSettings := nil;
    end;

    Json := JsonConvert.SerializeObject(Header);
    CheckContains('Original again after the reset', '"InvoiceNumber"', Json);
  finally
    Header.Free;
  end;
end;

procedure Step7_DefaultAppliesBackwards;
var
  Header, Back: TOrderHeader;
  Json: string;
begin
  Section('7. The default must also apply when reading');
  Header := BuildHeader;
  try
    JsonConvert.DefaultSettings :=
      procedure(S: TJsonSettings)
      begin
        S.CaseStyle := TJsonCaseStyle.jcSnake;
      end;
    try
      Json := JsonConvert.SerializeObject(Header);
      Back := JsonConvert.DeserializeObject<TOrderHeader>(Json);
      try
        Check('Invoice number back', 'B-2026-0042', Back.InvoiceNumber);
        Check('Customer name back', 'Miller Meyer Ltd', Back.CustomerName);
        Check('Amount back', 1234.5, Back.TotalAmount);
      finally
        Back.Free;
      end;
    finally
      JsonConvert.DefaultSettings := nil;
    end;
  finally
    Header.Free;
  end;
end;

procedure Step8_ManyRecordsViaFile;
var
  TheList, Back: TObjectList<TCustomer>;
  I: Integer;
  K: TCustomer;
  TheFile: string;
begin
  Section('8. Many records via the file');
  TheFile := TargetFile;
  TheList := TObjectList<TCustomer>.Create(True);
  try
    for I := 1 to 2000 do
    begin
      K := BuildCustomer;
      K.Number := IntToStr(I);
      K.Name := 'Customer ' + IntToStr(I);
      TheList.Add(K);
    end;

    JsonConvert.SerializeToFile(TheList, TheFile);
    Show('File', Format('%d bytes for %d customers', [Length(TFile.ReadAllBytes(TheFile)), TheList.Count]));

    Back := JsonConvert.DeserializeFromFile<TCustomerList>(TheFile);
    try
      Check('ItemCount', TheList.Count, Back.Count);
      Check('First name', 'Customer 1', Back[0].Name);
      Check('Last name', 'Customer 2000', Back[Back.Count - 1].Name);
    finally
      Back.Free;
    end;
  finally
    TheList.Free;
    if TFile.Exists(TheFile) then TFile.Delete(TheFile);
  end;
end;

procedure Step9_DomFromFile;
var
  Customer: TCustomer;
  TheFile: string;
  Dom: TJsonValue;
  Hits: TJsonValue;
begin
  Section('9. DOM directly from the file');
  TheFile := TargetFile;
  Customer := BuildCustomer;
  try
    JsonConvert.SerializeToFile(Customer, TheFile);
    Dom := JsonConvert.DeserializeFromFile(TheFile);
    try
      CheckTrue('DOM arrived', Dom <> nil, '');
      Hits := Dom.SelectToken('Address.City');
      CheckTrue('Path found', Hits <> nil, '');
      if Hits <> nil then Check('Value from the DOM', 'Exampletown', Hits.AsString);
    finally
      Dom.Free;
    end;
  finally
    Customer.Free;
    if TFile.Exists(TheFile) then TFile.Delete(TheFile);
  end;
end;

procedure Step10_EmptyAndErrorCases;
var
  EmptyItem: TMemoryStream;
begin
  Section('10. Empty stream and missing file');

  EmptyItem := TMemoryStream.Create;
  try
    CheckError('Empty stream is reported',
      procedure
      var
        K: TCustomer;
      begin
        K := JsonConvert.DeserializeFromStream<TCustomer>(EmptyItem);
        K.Free;
      end);
  finally
    EmptyItem.Free;
  end;

  CheckError('Missing file raises without the Try variant',
    procedure
    var
      K: TCustomer;
    begin
      K := JsonConvert.DeserializeFromFile<TCustomer>(
        TPath.Combine(TPath.GetTempPath, 'not_there_either_0815.json'));
      K.Free;
    end);
end;

procedure Step11_BytesInsteadOfStream;
var
  Original, ReadBack: TCustomer;
  RawData: TBytes;
  Dom: TJsonValue;
begin
  Section('11. Bytes instead of a stream - the route without a position');
  Original := BuildCustomer;
  try
    // A TBytes has no position and therefore cannot be in the wrong place.
    // This is the same idea as SerializeToUtf8Bytes in .NET.
    RawData := JsonConvert.SerializeToBytes(Original);
    Show('Bytes', Format('%d bytes UTF-8', [Length(RawData)]));
    CheckTrue('Starts with the brace', (Length(RawData) > 0) and (RawData[0] = Ord('{')),
      Format('%.2x', [RawData[0]]));

    ReadBack := JsonConvert.DeserializeFromBytes<TCustomer>(RawData);
    try
      Check('Number', '4711', ReadBack.Number);
      Check('City', 'Exampletown', ReadBack.Address.City);
    finally
      ReadBack.Free;
    end;

    Dom := JsonConvert.DeserializeFromBytes(RawData);
    try
      CheckTrue('DOM from bytes', Dom <> nil, '');
    finally
      Dom.Free;
    end;

    // Reading twice in a row must work - with a stream it would not.
    ReadBack := JsonConvert.DeserializeFromBytes<TCustomer>(RawData);
    try
      Check('Second read returns the same', 'Miller Meyer Ltd', ReadBack.Name);
    finally
      ReadBack.Free;
    end;

    RawData := JsonConvert.SerializeToBytes(Original,
      procedure(S: TJsonSettings)
      begin
        S.CaseStyle := TJsonCaseStyle.jcSnake;
      end);
    CheckContains('Configuration applies here too', '"name"',
      TEncoding.UTF8.GetString(RawData));
  finally
    Original.Free;
  end;
end;

// ---------------------------------------------------------------------------

begin
  try
    Title('DEMO 10 - API EXTENSIONS');

    Step1_FileRoundTrip;
    Step2_StreamRoundTrip;
    Step3_BomIsUnderstood;
    Step4_SettingsWithoutTryFinally;
    Step5_TryDeserialize;
    Step6_DefaultSettings;
    Step7_DefaultAppliesBackwards;
    Step8_ManyRecordsViaFile;
    Step9_DomFromFile;
    Step10_EmptyAndErrorCases;
    Step11_BytesInsteadOfStream;

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
