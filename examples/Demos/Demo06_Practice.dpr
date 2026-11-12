{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
program Demo06_Practice;

{$I NativeJson.inc}

{
  DEMO 6 - Practice: interface to a third-party system

  Shows typical tasks from everyday ERP/EDI work:
    - reading foreign JSON with unknown fields
    - enforcing required fields
    - partial update of an existing document
    - mapping foreign field names and date formats
    - catching broken JSON cleanly
    - writing JSON to a stream or a file and reading it back
}

{$APPTYPE CONSOLE}

uses
  SysUtils,
  Classes,
  Rtti,
  System.IOUtils,
  DateUtils,
  Generics.Collections,
  Demo.Assert in 'Demo.Assert.pas',
  Demo.Model in 'Demo.Model.pas',
  NativeJson.Main,
  NativeJson.Attributes,
  NativeJson.Fluent,
  NativeJson.Serializer.Writer;

type
  TCustomerList = TObjectList<TCustomer>;

const
  // This is how the partner delivers its orders - with extra fields
  // we are not interested in.
  PartnerJson =
    '{' +
    '"OrderNo":"P-77001",' +
    '"Status":"bsNew",' +
    '"Customer":{"Number":"K-4711","Name":"Sample Corp",' +
    '"Address":{"Street":"Industrial Ring 5","ZipCode":"28195","City":"Bremen","Country":"DE"}},' +
    '"LineItems":[' +
    '{"LineNo":10,"ArticleNo":"ART-400-24","Quantity":3,"UnitPrice":129.5},' +
    '{"LineNo":20,"ArticleNo":"ART-2X1.5","Quantity":50,"UnitPrice":1.25}' +
    '],' +
    '"PartnerReference":"XYZ-99",' +
    '"UnknownField":true' +
    '}';

// ---------------------------------------------------------------------------

procedure Step1_ReadForeignJson;
var
  Order: TOrder;
  Settings: TJsonSettings;
begin
  Section('1. Reading foreign JSON with extra fields');
  Settings := TJsonSettings.Create;
  try
    // Default: unknown fields are silently skipped
    Settings.MissingMemberHandling := TJsonMissingMemberHandling.Ignore;
    Settings.TypeNameHandling := TJsonTypeNameHandling.Auto;

    Order := JsonConvert.DeserializeObject<TOrder>(PartnerJson, Settings);
    try
      Check('Order number', 'P-77001', Order.OrderNo);
      CheckTrue('Status read', Order.Status = bsNew, 'bsNew');
      Check('Customer number', 'K-4711', Order.Customer.Number);
      Check('City', 'Bremen', Order.Customer.Address.City);
      Check('Line item count', 2, Order.LineItems.Count);
      Check('LineNo of the second line item', 20, Order.LineItems[1].LineNo);
    finally
      Order.Free;
    end;
  finally
    Settings.Free;
  end;
end;

procedure Step2_ReportUnknownFields;
var
  Settings: TJsonSettings;
begin
  Section('2. Report unknown fields as errors');
  Settings := TJsonSettings.Create;
  try
    Settings.MissingMemberHandling := TJsonMissingMemberHandling.Error;

    CheckError('Extra field now raises an exception',
      procedure
      var
        B: TOrder;
      begin
        B := JsonConvert.DeserializeObject<TOrder>(PartnerJson, Settings);
        B.Free;
      end);

    Writeln('       Benefit: you notice when the partner changes its format.');
  finally
    Settings.Free;
  end;
end;

procedure Step3_RequiredFields;
var
  Settings: TJsonSettings;
  Customer: TCustomer;
begin
  Section('3. Enforcing required fields');
  Settings := TJsonSettings.Create;
  try
    Settings.Fluent.Entity<TCustomer>
      .Map('Number').Required(True).EndMember;

    // Case A: field is present -> all good
    Customer := JsonConvert.DeserializeObject<TCustomer>(
      '{"Number":"K-1","Name":"Present"}', Settings);
    try
      Check('Complete record passes', 'K-1', Customer.Number);
    finally
      Customer.Free;
    end;

    // Case B: field is missing -> exception
    CheckError('Missing required field is reported',
      procedure
      var
        K: TCustomer;
      begin
        K := JsonConvert.DeserializeObject<TCustomer>('{"Name":"Without number"}', Settings);
        K.Free;
      end);
  finally
    Settings.Free;
  end;
end;

procedure Step4_PartialUpdate;
var
  Order: TOrder;
  Change: string;
begin
  Section('4. Partial update of an existing document');
  Order := CreateSampleOrder;
  try
    CheckTrue('Status before', Order.Status = bsConfirmed, 'bsConfirmed');
    Check('Customer name before', 'Example Trading GmbH', Order.Customer.Name);

    // Only change the status - everything else stays
    Change := '{"Status":"bsDelivered"}';
    JsonConvert.PopulateObject(Order, Change);

    CheckTrue('Status after', Order.Status = bsDelivered, 'bsDelivered');
    Check('Customer name unchanged', 'Example Trading GmbH', Order.Customer.Name);
    Check('Line items unchanged', 3, Order.LineItems.Count);

    // Note: if a list is sent along in the patch, it replaces the content
    JsonConvert.PopulateObject(Order, '{"LineItems":[]}');
    Check('List sent along replaces the content', 0, Order.LineItems.Count);
  finally
    Order.Free;
  end;
end;

procedure Step5_ForeignFieldNames;
var
  Customer: TCustomer;
  Settings: TJsonSettings;
  Foreign: string;
begin
  Section('5. Mapping foreign field names');
  Settings := TJsonSettings.Create;
  try
    // The partner names the fields differently
    Settings.Fluent.Entity<TCustomer>
      .Map('Number').Name('customer_no').EndMember
      .Map('Name').Name('customer_name').EndMember
      .Map('Email').Name('contact_mail').EndMember;

    Foreign := '{"customer_no":"K-9","customer_name":"Foreign Ltd","contact_mail":"a@b.de"}';

    Customer := JsonConvert.DeserializeObject<TCustomer>(Foreign, Settings);
    try
      Check('Number', 'K-9', Customer.Number);
      Check('Name', 'Foreign Ltd', Customer.Name);
      Check('Email', 'a@b.de', Customer.Email);
    finally
      Customer.Free;
    end;

    // and the same way back
    Customer := TCustomer.Create;
    try
      Customer.Number := 'K-9';
      Customer.Name := 'Foreign Ltd';
      CheckContains('Reply in partner format', '"customer_no":"K-9"',
        JsonConvert.SerializeObject(Customer, Settings));
    finally
      Customer.Free;
    end;
  finally
    Settings.Free;
  end;
end;

procedure Step6_ForeignDateFormat;
var
  Settings: TJsonSettings;
  Order: TOrder;
  Json: string;
begin
  Section('6. Foreign date format');
  Settings := TJsonSettings.Create;
  Order := TOrder.Create;
  try
    Settings.DateFormat := 'dd.mm.yyyy';
    Order.OrderNo := 'B-1';
    Order.Date := EncodeDate(2026, 12, 24);

    Json := JsonConvert.SerializeObject(Order, Settings);
    Show('JSON', Json);
    CheckContains('German date', '"Date":"24.12.2026"', Json);

    Order.Date := 0;
    JsonConvert.PopulateObject(Order, Json, Settings);
    Check('Read back: year', 2026, YearOf(Order.Date));
    Check('Read back: month', 12, MonthOf(Order.Date));
    Check('Read back: day', 24, DayOf(Order.Date));
  finally
    Order.Free;
    Settings.Free;
  end;
end;

procedure Step7_BrokenJson;
begin
  Section('7. Catching broken JSON cleanly');

  CheckError('Missing brace',
    procedure
    var
      K: TCustomer;
    begin
      K := JsonConvert.DeserializeObject<TCustomer>('{"Name":"Broken"');
      K.Free;
    end);

  CheckError('Comma instead of colon',
    procedure
    var
      K: TCustomer;
    begin
      K := JsonConvert.DeserializeObject<TCustomer>('{"Name","Broken"}');
      K.Free;
    end);

  CheckError('Empty text',
    procedure
    var
      K: TCustomer;
    begin
      K := JsonConvert.DeserializeObject<TCustomer>('');
      K.Free;
    end);

  CheckError('Unknown enumeration value',
    procedure
    var
      B: TOrder;
    begin
      B := JsonConvert.DeserializeObject<TOrder>('{"Status":"doesNotExist"}');
      B.Free;
    end);
end;

procedure Step8_StreamAndFile;
var
  Order, CopyObj: TOrder;
  Stream: TMemoryStream;
  Settings: TJsonSettings;
  RawData: TBytes;
  Content, FileName: string;
begin
  Section('8. Writing to a stream and a file');
  Order := CreateSampleOrder;
  Stream := TMemoryStream.Create;
  Settings := TJsonSettings.Create;
  try
    Settings.TypeNameHandling := TJsonTypeNameHandling.Auto;
    Settings.Formatting := TJsonFormatting.Indented;

    JsonConvert.SerializeObjectToStream(Order, Stream, Settings);
    CheckTrue('Stream is filled', Stream.Size > 0, Format('%d bytes', [Stream.Size]));

    SetLength(RawData, Integer(Stream.Size));
    Stream.Position := 0;
    if Length(RawData) > 0 then Stream.ReadBuffer(RawData[0], Length(RawData));
    Content := TEncoding.UTF8.GetString(RawData);
    CheckContains('Order number in the stream', 'B-2026-0815', Content);

    // ... and into a file
    FileName := TPath.Combine(TPath.GetTempPath, 'nativejson_demo_order.json');
    TFile.WriteAllText(FileName, JsonConvert.SerializeObject(Order, Settings), TEncoding.UTF8);
    CheckTrue('File was created', TFile.Exists(FileName), FileName);

    CopyObj := JsonConvert.DeserializeObject<TOrder>(
      TFile.ReadAllText(FileName, TEncoding.UTF8), Settings);
    try
      Check('Read from file: order number', 'B-2026-0815', CopyObj.OrderNo);
      Check('Read from file: line items', 3, CopyObj.LineItems.Count);
      Check('Read from file: total', Order.Total, CopyObj.Total, 0.001);
    finally
      CopyObj.Free;
    end;

    if TFile.Exists(FileName) then TFile.Delete(FileName);
  finally
    Settings.Free;
    Stream.Free;
    Order.Free;
  end;
end;

procedure Step9_BulkData;
var
  TheList: TObjectList<TCustomer>;
  CopyObj: TObjectList<TCustomer>;
  K: TCustomer;
  I: Integer;
  Json: string;
  Start: TDateTime;
begin
  Section('9. Larger amount of data (1000 customers)');
  TheList := TObjectList<TCustomer>.Create(True);
  try
    for I := 1 to 1000 do
    begin
      K := TCustomer.Create;
      K.Number := Format('K-%.5d', [I]);
      K.Name := 'Customer number ' + IntToStr(I);
      K.Address.City := 'City ' + IntToStr(I mod 50);
      TheList.Add(K);
    end;

    Start := Now;
    Json := JsonConvert.SerializeObject(TheList);
    Show('Length', Format('%d chars in %d ms', [Length(Json), MilliSecondsBetween(Now, Start)]));

    Start := Now;
    CopyObj := JsonConvert.DeserializeObject<TCustomerList>(Json);
    try
      CopyObj.OwnsObjects := True;
      Show('Read', Format('%d ms', [MilliSecondsBetween(Now, Start)]));

      Check('ItemCount', 1000, CopyObj.Count);
      Check('First record', 'K-00001', CopyObj[0].Number);
      Check('Last record', 'K-01000', CopyObj[999].Number);
      Check('Nested address', 'City 0', CopyObj[999].Address.City);
    finally
      CopyObj.Free;
    end;
  finally
    TheList.Free;
  end;
end;

// ---------------------------------------------------------------------------

begin
  try
    Title('DEMO 6 - PRACTICE: INTERFACE TO A THIRD-PARTY SYSTEM');

    Step1_ReadForeignJson;
    Step2_ReportUnknownFields;
    Step3_RequiredFields;
    Step4_PartialUpdate;
    Step5_ForeignFieldNames;
    Step6_ForeignDateFormat;
    Step7_BrokenJson;
    Step8_StreamAndFile;
    Step9_BulkData;

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
