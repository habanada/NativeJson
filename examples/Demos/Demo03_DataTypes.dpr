{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
program Demo03_DataTypes;

{$I NativeJson.inc}

{
  DEMO 3 - Data types

  Shows: date/time with and without a custom format, enumerations,
         TGUID, numbers, Currency, records, TStringList, streams (Base64),
         Variant and character escaping.
}

{$APPTYPE CONSOLE}

uses
  SysUtils,
  Classes,
  Rtti,
  DateUtils,
  Variants,
  Generics.Collections,
  Demo.Assert in 'Demo.Assert.pas',
  Demo.Model in 'Demo.Model.pas',
  NativeJson.Main,
  NativeJson.Attributes,
  NativeJson.Serializer.Writer;

type
  TInvoiceHeader = class
  private
    FNumber: string;
    FInvoiceDate: TDateTime;
  public
    property Number: string read FNumber write FNumber;
    property InvoiceDate: TDateTime read FInvoiceDate write FInvoiceDate;
  end;

  TAttachment = class
  private
    FFileName: string;
    FContent: TMemoryStream;
    FLines: TStringList;
  public
    constructor Create;
    destructor Destroy; override;
    property FileName: string read FFileName write FFileName;
    property Content: TMemoryStream read FContent;
    property Lines: TStringList read FLines;
  end;

constructor TAttachment.Create;
begin
  inherited Create;
  FContent := TMemoryStream.Create;
  FLines := TStringList.Create;
end;

destructor TAttachment.Destroy;
begin
  FLines.Free;
  FContent.Free;
  inherited;
end;

// ---------------------------------------------------------------------------

procedure Step1_DefaultDate;
var
  Header, CopyObj: TInvoiceHeader;
  Json: string;
begin
  Section('1. TDateTime in the default format (ISO 8601)');
  Header := TInvoiceHeader.Create;
  try
    Header.Number := 'RE-1000';
    Header.InvoiceDate := EncodeDateTime(2026, 3, 15, 14, 30, 0, 0);

    Json := JsonConvert.SerializeObject(Header);
    Show('JSON', Json);

    // Depending on the time zone the ISO format contains an offset,
    // so the complete string is not checked.
    CheckContains('Date part', '2026-03-15T14:30:00', Json);

    CopyObj := JsonConvert.DeserializeObject<TInvoiceHeader>(Json);
    try
      Check('Year', 2026, YearOf(CopyObj.InvoiceDate));
      Check('Month', 3, MonthOf(CopyObj.InvoiceDate));
      Check('Day', 15, DayOf(CopyObj.InvoiceDate));
      Check('Hour', 14, HourOf(CopyObj.InvoiceDate));
      Check('Minute', 30, MinuteOf(CopyObj.InvoiceDate));
    finally
      CopyObj.Free;
    end;
  finally
    Header.Free;
  end;
end;

procedure Step2_CustomDateFormat;
var
  Settings: TJsonSettings;
  Source, Back: TDateTime;
  Json: string;
begin
  Section('2. Custom date format (always invariant, never local)');
  Settings := TJsonSettings.Create;
  try
    Source := EncodeDate(2026, 9, 4);

    Settings.DateFormat := 'yyyy-MM-dd';
    Json := JsonConvert.SerializeObject(TValue.From<TDateTime>(Source), Settings);
    Check('ISO short form', '"2026-09-04"', Json);
    Back := JsonConvert.DeserializeObject<TDateTime>(Json, Settings);
    Check('Round trip day', 4, DayOf(Back));

    Settings.DateFormat := 'dd.mm.yyyy';
    Json := JsonConvert.SerializeObject(TValue.From<TDateTime>(Source), Settings);
    Check('German format', '"04.09.2026"', Json);
    Back := JsonConvert.DeserializeObject<TDateTime>(Json, Settings);
    Check('Round trip year', 2026, YearOf(Back));
    Check('Round trip month', 9, MonthOf(Back));
  finally
    Settings.Free;
  end;
end;

procedure Step3_Enumerations;
var
  Settings: TJsonSettings;
  Json: string;
  Status: TOrderStatus;
begin
  Section('3. Enumerations as name or as number');
  Settings := TJsonSettings.Create;
  try
    Settings.EnumHandling := TJsonEnumHandling.ByName;
    Json := JsonConvert.SerializeObject(TValue.From<TOrderStatus>(bsDelivered), Settings);
    Check('As name', '"bsDelivered"', Json);
    Status := JsonConvert.DeserializeObject<TOrderStatus>(Json, Settings);
    CheckTrue('Name read back', Status = bsDelivered, 'bsDelivered');

    Settings.EnumHandling := TJsonEnumHandling.ByInteger;
    Json := JsonConvert.SerializeObject(TValue.From<TOrderStatus>(bsDelivered), Settings);
    Check('As number', '2', Json);
    Status := JsonConvert.DeserializeObject<TOrderStatus>(Json, Settings);
    CheckTrue('Number read back', Status = bsDelivered, 'bsDelivered');

    // The library is tolerant when reading: both always work
    Status := JsonConvert.DeserializeObject<TOrderStatus>('"bsCancelled"');
    CheckTrue('Name readable despite ByInteger expectation', Status = bsCancelled, 'bsCancelled');
  finally
    Settings.Free;
  end;
end;

procedure Step4_Guid;
var
  Source, Back: TGUID;
  Json: string;
begin
  Section('4. TGUID');
  Source := StringToGUID('{2C1E4F0A-1234-4B5C-8D9E-0F1A2B3C4D5E}');

  Json := JsonConvert.SerializeObject(TValue.From<TGUID>(Source));
  Show('JSON', Json);

  Check('Without curly braces, upper case',
    '"2C1E4F0A-1234-4B5C-8D9E-0F1A2B3C4D5E"', Json);

  Back := JsonConvert.DeserializeObject<TGUID>(Json);
  CheckTrue('Round trip identical', IsEqualGUID(Source, Back), GUIDToString(Back));
end;

procedure Step5_Numbers;
var
  Json: string;
  D: Double;
  C: Currency;
  I64: Int64;
begin
  Section('5. Numbers (always with a dot as decimal separator)');

  Json := JsonConvert.SerializeObject(TValue.From<Double>(1234.5678));
  Check('Double', '1234.5678', Json);
  D := JsonConvert.DeserializeObject<Double>(Json);
  Check('Double back', 1234.5678, D);

  Json := JsonConvert.SerializeObject(TValue.From<Currency>(19.99));
  Check('Currency', '19.99', Json);
  C := JsonConvert.DeserializeObject<Currency>(Json);
  Check('Currency back', 19.99, C, 0.0001);

  Json := JsonConvert.SerializeObject(TValue.From<Int64>(9007199254740993));
  Check('Int64', '9007199254740993', Json);
  I64 := JsonConvert.DeserializeObject<Int64>(Json);
  CheckTrue('Int64 back exactly', I64 = 9007199254740993, IntToStr(I64));
end;

procedure Step6_Record;
var
  Source, Back: TGeoPoint;
  Json: string;
begin
  Section('6. Record (mapped through its fields)');
  Source.Width := 52.9231;
  Source.Len := 9.2350;

  Json := JsonConvert.SerializeObject(TValue.From<TGeoPoint>(Source));
  Show('JSON', Json);
  CheckContains('Width', '"Width":52.9231', Json);
  CheckContains('Len', '"Len":9.235', Json);

  Back := JsonConvert.DeserializeObject<TGeoPoint>(Json);
  Check('Width back', 52.9231, Back.Width);
  Check('Length back', 9.235, Back.Len);
end;

procedure Step7_StreamsAndStringLists;
var
  Attachment, CopyObj: TAttachment;
  RawData: TBytes;
  Json: string;
begin
  Section('7. TMemoryStream as Base64, TStringList as array');
  Attachment := TAttachment.Create;
  try
    Attachment.FileName := 'delivery_note.txt';
    RawData := TEncoding.UTF8.GetBytes('Hello World');
    Attachment.Content.WriteBuffer(RawData[0], Length(RawData));
    Attachment.Lines.Add('Line 1');
    Attachment.Lines.Add('Line 2');

    Json := JsonConvert.SerializeObject(Attachment);
    Show('JSON', Json);

    CheckContains('Base64 of "Hello World"', 'SGVsbG8gV29ybGQ=', Json);
    CheckContains('String list as array', '"Lines":["Line 1","Line 2"]', Json);

    CopyObj := JsonConvert.DeserializeObject<TAttachment>(Json);
    try
      Check('FileName', 'delivery_note.txt', CopyObj.FileName);
      Check('Stream size', Length(RawData), Integer(CopyObj.Content.Size));
      Check('Line count', 2, CopyObj.Lines.Count);
      Check('Second line', 'Line 2', CopyObj.Lines[1]);
    finally
      CopyObj.Free;
    end;
  finally
    Attachment.Free;
  end;
end;

procedure Step8_Variants;
var
  ValueList: TDictionary<string, Variant>;
  Json: string;
begin
  Section('8. Variant (typical EDI extra fields)');
  ValueList := TDictionary<string, Variant>.Create;
  try
    ValueList.Add('Priority', 1);
    ValueList.Add('Customer', 'Acme');
    ValueList.Add('Express', True);

    Json := JsonConvert.SerializeObject(ValueList);
    Show('JSON', Json);

    CheckContains('Integer stays a number', '"Priority":1', Json);
    CheckContains('String stays text', '"Customer":"Acme"', Json);
    CheckContains('Boolean stays bool', '"Express":true', Json);
  finally
    ValueList.Free;
  end;
end;

procedure Step9_Escaping;
var
  Json, Back: string;
begin
  Section('9. Character escaping');

  Json := JsonConvert.SerializeObject('He said "Hello"');
  Check('Quotes', '"He said \"Hello\""', Json);

  Json := JsonConvert.SerializeObject('C:\Temp\File.txt');
  Check('Backslash', '"C:\\Temp\\File.txt"', Json);

  Json := JsonConvert.SerializeObject('Line1'#13#10'Line2');
  Check('Line break', '"Line1\r\nLine2"', Json);

  Json := JsonConvert.SerializeObject('Tab'#9'End');
  Check('Tab', '"Tab\tEnd"', Json);

  // Umlauts are not escaped but written directly.
  // That is why only the in-memory round trip is compared here.
  Json := JsonConvert.SerializeObject('Gr'#$00FC#$00DF'e from M'#$00FC#$00F1'chen');
  Back := JsonConvert.DeserializeObject<string>(Json);
  Check('Umlaut round trip', 'Gr'#$00FC#$00DF'e from M'#$00FC#$00F1'chen', Back);

  Back := JsonConvert.DeserializeObject<string>('"\u00DCbergabe"');
  Check('\u sequence read', #$00DC'bergabe', Back);
end;

// ---------------------------------------------------------------------------

begin
  try
    Title('DEMO 3 - DATA TYPES');

    Step1_DefaultDate;
    Step2_CustomDateFormat;
    Step3_Enumerations;
    Step4_Guid;
    Step5_Numbers;
    Step6_Record;
    Step7_StreamsAndStringLists;
    Step8_Variants;
    Step9_Escaping;

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
