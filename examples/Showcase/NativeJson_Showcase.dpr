{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
program NativeJson_Showcase;

{$I NativeJson.inc}

{$APPTYPE CONSOLE}

uses
  SysUtils,
  Demo.Assert in '..\Demos\Demo.Assert.pas',
  NativeJson.Main,
  NativeJson.Attributes,
  NativeJson.Settings,
  NativeJson.NamingStrategy,
  NativeJson.Schema.Attributes,
  NativeJson.Validation,
  NativeJson.Dom.Value,
  NativeJson.Dom.Primitive,
  NativeJson.Dom.JsonArray,
  NativeJson.Dom.Io,
  NativeJson.Linq,
  NativeJson.CodeGen,
  NativeJson.Xml,
  NativeJson.Cbor,
  NativeJson.Cbor.Convert;

type
  TAddress = class
  private
    FCity: string;
    FZip: string;
  public
    property City: string read FCity write FCity;
    property Zip: string read FZip write FZip;
  end;

  TCustomer = class
  private
    FName: string;
    FAge: Integer;
    FBalance: Currency;
    FAddress: TAddress;
  public
    constructor Create;
    destructor Destroy; override;
    [JsonProperty('full_name')]
    property Name: string read FName write FName;
    [JsonRange(18, 120)]
    property Age: Integer read FAge write FAge;
    property Balance: Currency read FBalance write FBalance;
    property Address: TAddress read FAddress;
  end;

constructor TCustomer.Create;
begin
  inherited Create;
  FAddress := TAddress.Create;
end;

destructor TCustomer.Destroy;
begin
  FAddress.Free;
  inherited;
end;

function NewCustomer(const AName: string; AAge: Integer; const ACity, AZip: string): TCustomer;
begin
  Result := TCustomer.Create;
  try
    Result.Name := AName;
    Result.Age := AAge;
    Result.Address.City := ACity;
    Result.Address.Zip := AZip;
  except
    Result.Free;
    raise;
  end;
end;

procedure Step1_ObjectsAndJson;
var
  Customer, Clone: TCustomer;
  Settings: TJsonSettings;
  Json: string;
begin
  Section('1. Objects to JSON and back');
  Customer := NewCustomer('Anna Weber', 34, 'Exampletown', '12345');
  try
    Customer.Balance := StrToCurr('1234567890123.4567', TFormatSettings.Invariant);
    Json := JsonConvert.SerializeObject(Customer);
    Check('Compact output',
      '{"full_name":"Anna Weber","Age":34,"Balance":1234567890123.4567,"Address":{"City":"Exampletown","Zip":"12345"}}',
      Json);
    Clone := JsonConvert.DeserializeObject<TCustomer>(Json);
    try
      Check('Name', 'Anna Weber', Clone.Name);
      Check('Nested object', 'Exampletown', Clone.Address.City);
      CheckTrue('Currency is exact', Clone.Balance = Customer.Balance, CurrToStr(Clone.Balance));
    finally
      Clone.Free;
    end;

    Settings := TJsonSettings.Create;
    try
      Settings.NamingStrategy := TSnakeCaseNamingStrategy;
      Check('Naming strategy, explicit names win',
        '{"full_name":"Anna Weber","age":34,"balance":1234567890123.4567,"address":{"city":"Exampletown","zip":"12345"}}',
        JsonConvert.SerializeObject(Customer, Settings));
    finally
      Settings.Free;
    end;
  finally
    Customer.Free;
  end;
end;

procedure Step2_ObjectDiffAndPatch;
var
  OldCustomer, NewValue, Updated: TCustomer;
  Patch: TJsonArray;
begin
  Section('2. Delphi object to JSON Patch to Delphi object');
  OldCustomer := NewCustomer('Anna Weber', 34, 'Exampletown', '12345');
  NewValue := NewCustomer('Anna Weber', 35, 'Hamburg', '12345');
  try
    Patch := JsonConvert.CreatePatch<TCustomer>(OldCustomer, NewValue);
    try
      Check('RFC 6902 patch',
        '[{"op":"replace","path":"/Age","value":35},{"op":"replace","path":"/Address/City","value":"Hamburg"}]',
        Patch.ToJson);
      Updated := JsonConvert.ApplyPatch<TCustomer>(OldCustomer, Patch);
      try
        Check('Patched age', 35, Updated.Age);
        Check('Patched nested city', 'Hamburg', Updated.Address.City);
        Check('Source object is unchanged', 34, OldCustomer.Age);
        CheckTrue('A new instance is returned', Updated <> OldCustomer, '');
      finally
        Updated.Free;
      end;
    finally
      Patch.Free;
    end;
  finally
    NewValue.Free;
    OldCustomer.Free;
  end;
end;

const
  Catalog =
    '{"article":[' +
    '{"name":"Widget","price":120,"stock":5},' +
    '{"name":"Gadget","price":15,"stock":0},' +
    '{"name":"Gizmo","price":45,"stock":12},' +
    '{"name":"Sprocket","price":3,"stock":40}]}';

function Field(const Name: string): TJsonTransform;
begin
  Result := function(const Item: TJsonValue): TJsonValue
    begin
      Result := Item.Values[Name];
    end;
end;

procedure Step3_Queries;
var
  Dom: TJsonValue;
  Items: TJsonLinq;
  Names: TJsonArray;
  NewPrice: TJsonNumber;
begin
  Section('3. LINQ-style queries that can also change the document');
  Dom := DomFromText(Catalog);
  try
    Items := Dom.Q.Select('article').Children;
    Check('Articles', 4, Items.Count);
    Check('Price of what is in stock', 168.0,
      Items.Where(function(const I: TJsonValue): Boolean
        begin
          Result := I.Values['stock'].AsInteger > 0;
        end).Transform(Field('price')).Sum);

    Names := Items.OrderByDescending(Field('price')).Take(2).Transform(Field('name')).ToJsonArray;
    try
      Check('Two most expensive', '["Widget","Gizmo"]', Names.ToJson);
    finally
      Names.Free;
    end;

    Items.Where(function(const I: TJsonValue): Boolean
      begin
        Result := I.Values['stock'].AsInteger = 0;
      end).Remove;
    Check('Sold out article removed', 3, Dom.Q.Select('article').Children.Count);

    NewPrice := TJsonNumber.Create(4);
    try
      Dom.Q.Select('article').Children.Where(function(const I: TJsonValue): Boolean
        begin
          Result := I.Values['name'].AsString = 'Sprocket';
        end).Select('price').Replace(NewPrice);
    finally
      NewPrice.Free;
    end;
    Check('Price replaced in place',
      '{"article":[{"name":"Widget","price":120,"stock":5},' +
      '{"name":"Gizmo","price":45,"stock":12},{"name":"Sprocket","price":4,"stock":40}]}',
      DomToText(Dom));
  finally
    Dom.Free;
  end;
end;

procedure Step4_SchemaAndExactNumbers;
var
  Schema: TJsonValue;
  Outcome: TJsonSchemaValidationResult;
begin
  Section('4. Schema from a class, validation with exact numbers');
  Schema := JsonConvert.GenerateSchema<TCustomer>;
  try
    Outcome := JsonConvert.ValidateJsonSchema(
      '{"full_name":"Max","Age":12,"Balance":0,"Address":{"City":"X","Zip":"1"}}', Schema.ToJson);
    CheckTrue('Age 12 violates the generated schema', not Outcome.IsValid, '');
    Check('One error', 1, Outcome.ErrorCount);
    Check('Where', '/Age', Outcome.Errors[0].InstancePath);
    Check('Which rule', 'minimum', Outcome.Errors[0].Keyword);
  finally
    Schema.Free;
  end;

  CheckTrue('19.99 is a multiple of 0.01',
    JsonConvert.ValidateJsonSchema('19.99', '{"multipleOf":0.01}').IsValid, '');
  CheckTrue('19.995 is not',
    not JsonConvert.ValidateJsonSchema('19.995', '{"multipleOf":0.01}').IsValid, '');
  CheckTrue('9007199254740993 is above 9007199254740992',
    not JsonConvert.ValidateJsonSchema('9007199254740993', '{"maximum":9007199254740992}').IsValid, '');
end;

procedure Step5_CodeGeneration;
const
  AddressSchema = '{"type":"object","additionalProperties":false,"properties":{"city":{"type":"string"}}}';
  OrderSchema = '{"type":"object","additionalProperties":false,"properties":{"address":{"$ref":"https://example.org/address.json"}}}';
  OpenApi =
    '{"openapi":"3.0.3","info":{"title":"x","version":"1"},"paths":{},"components":{"schemas":' +
    '{"Customer":{"type":"object","additionalProperties":false,"properties":{"name":{"type":"string"}}},' +
    '"Order":{"type":"object","additionalProperties":false,"properties":{"total":{"type":"number"}}}}}}';
var
  Generator: TNativeJsonSchemaCodeGenerator;
  Code: string;
begin
  Section('5. Schema and OpenAPI to a Delphi unit');
  Generator := TNativeJsonSchemaCodeGenerator.Create;
  try
    Generator.RegisterSchema('https://example.org/address.json', AddressSchema);
    Generator.LoadSchema(OrderSchema, 'https://example.org/order.json');
    Code := Generator.GenerateUnit('Shop.Model');
    CheckContains('Unit header', 'unit Shop.Model;', Code);
    CheckContains('Field from the external schema', 'FCity: string;', Code);
  finally
    Generator.Free;
  end;
  Code := TNativeJsonSchemaCodeGenerator.SchemaToTypes(OpenApi);
  CheckContains('OpenAPI component Customer becomes a class', 'TCustomer = class', Code);
  CheckContains('OpenAPI component Order becomes a class', 'TOrder = class', Code);
end;

procedure Step6_SequentialReading;
var
  Seen, AgeSum: Integer;
begin
  Section('6. A large array, one element at a time');
  Seen := 0;
  AgeSum := 0;
  Check('Elements handled',
    3,
    JsonConvert.DeserializeSequence<TCustomer>(
      '[{"full_name":"A","Age":20},{"full_name":"B","Age":30},{"full_name":"C","Age":40}]',
      procedure(Item: TCustomer)
      begin
        Inc(Seen);
        AgeSum := AgeSum + Item.Age;
        Item.Free;
      end));
  Check('Handler ran for each', 3, Seen);
  Check('Sum of ages', 90, AgeSum);
end;

procedure Step7_RuntimeValidation;
var
  Customer: TCustomer;
  Outcome: TJsonValidationResult;
begin
  Section('7. Validation rules from attributes');
  Customer := NewCustomer('Max', 12, 'Exampletown', '12345');
  try
    Outcome := JsonConvert.Validate(Customer);
    try
      Check('One violation', 1, Outcome.Count);
      Check('Path', '/Age', Outcome[0].Path);
      Check('Rule', 'minimum', Outcome[0].Rule);
    finally
      Outcome.Free;
    end;
  finally
    Customer.Free;
  end;
end;

procedure Step8_Xml;
begin
  Section('8. XML and JSON');
  Check('JSON to XML',
    '<customer id="7"><name>Anna</name></customer>',
    JsonToXml('{"customer":{"@id":"7","name":"Anna"}}'));
  Check('XML to JSON',
    '{"customer":{"@id":"7","name":"Anna"}}',
    XmlToJson('<customer id="7"><name>Anna</name></customer>'));
end;

procedure Step9_Cbor;
var
  Cbor: TBytes;
  Customer, Back: TCustomer;
begin
  Section('9. CBOR');
  Cbor := JsonToCbor('{"id":7,"temp":21.5}');
  Check('JSON to CBOR', 'a2626964076474656d70f94d60', CborToHex(Cbor));
  Check('CBOR to JSON', '{"id":7,"temp":21.5}', CborToJson(Cbor));
  Check('A decimal a Double cannot hold stays exact',
    '1.00000000000000000001',
    CborToJson(JsonToCbor('1.00000000000000000001')));
  Customer := NewCustomer('Anna Weber', 34, 'Exampletown', '12345');
  try
    Customer.Balance := StrToCurr('1234567890123.4567', TFormatSettings.Invariant);
    Back := CborConvert.DeserializeObject<TCustomer>(CborConvert.SerializeObject(Customer));
    try
      CheckTrue('Object round trip keeps the Currency', Back.Balance = Customer.Balance, CurrToStr(Back.Balance));
      Check('Object round trip keeps the nested city', 'Exampletown', Back.Address.City);
    finally
      Back.Free;
    end;
  finally
    Customer.Free;
  end;
end;

begin
  {$IFNDEF FPC}
  ReportMemoryLeaksOnShutdown := True;
  {$ENDIF}
  try
    Title('NATIVEJSON - SHOWCASE');
    Step1_ObjectsAndJson;
    Step2_ObjectDiffAndPatch;
    Step3_Queries;
    Step4_SchemaAndExactNumbers;
    Step5_CodeGeneration;
    Step6_SequentialReading;
    Step7_RuntimeValidation;
    Step8_Xml;
    Step9_Cbor;
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
