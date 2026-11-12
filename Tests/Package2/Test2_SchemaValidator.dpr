{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
program Test2_SchemaValidator;

{$I NativeJson.inc}

// TEST PACKAGE 2 - JSON SCHEMA VALIDATION
//
//   Modeled on the structure of the official JSON Schema test suite:
//   one schema, plus several instances with an expected result.
//
//   The last section closes the loop: GenerateSchema<T> creates
//   a schema, the serializer creates an instance, the validator must
//   consider both compatible. If generator and serializer
//   drift apart, this is exactly where it shows up and nowhere else.

{$APPTYPE CONSOLE}

uses
  SysUtils,
  Generics.Collections,
  Demo.Assert in '..\..\examples\Demos\Demo.Assert.pas',
  NativeJson.Main,
  NativeJson.Dom.JsonObject,
  NativeJson.Attributes,
  NativeJson.Schema.Attributes,
  NativeJson.Schema.Validation,
  NativeJson.Schema.Validator,
  NativeJson.Schema.Decimal;

type
  TCustomer = class
  private
    FName: string;
    FAge: Integer;
    FCredit: Currency;
    FActive: Boolean;
  published
    property Name: string read FName write FName;
    property Age: Integer read FAge write FAge;
    property Credit: Currency read FCredit write FCredit;
    property Active: Boolean read FActive write FActive;
  end;

  TLineItem = class
  private
    FArticle: string;
    FQuantity: Integer;
  published
    property Article: string read FArticle write FArticle;
    property Quantity: Integer read FQuantity write FQuantity;
  end;

  TPurchaseOrder = class
  private
    FNumber: string;
    FLineItems: TObjectList<TLineItem>;
  public
    constructor Create;
    destructor Destroy; override;
  published
    property Number: string read FNumber write FNumber;
    property LineItems: TObjectList<TLineItem> read FLineItems;
  end;

constructor TPurchaseOrder.Create;
begin
  inherited Create;
  FLineItems := TObjectList<TLineItem>.Create(True);
end;

destructor TPurchaseOrder.Destroy;
begin
  FLineItems.Free;
  inherited;
end;

// ---------------------------------------------------------------------------

var
  GSchema: string;

procedure ExpectValid(const Name, Json: string);
var
  R: TJsonSchemaValidationResult;
begin
  R := JsonConvert.ValidateJsonSchema(Json, GSchema);
  CheckTrue(Name, R.IsValid, R.ToString);
end;

procedure ExpectInvalid(const Name, Json, KeywordName: string);
var
  R: TJsonSchemaValidationResult;
  E: TJsonSchemaValidationError;
  Hits: Boolean;
begin
  R := JsonConvert.ValidateJsonSchema(Json, GSchema);
  if R.IsValid then
  begin
    CheckTrue(Name, False, 'was wrongly accepted');
    Exit;
  end;
  Hits := KeywordName = '';
  for E in R.Errors do
    if E.Keyword = KeywordName then Hits := True;
  CheckTrue(Name, Hits, R.ToString);
end;

// ---------------------------------------------------------------------------

const
  Smiley = #$D83D#$DE00;

function Emojis(ItemCount: Integer): string;
var
  I: Integer;
begin
  Result := '"';
  for I := 1 to ItemCount do Result := Result + Smiley;
  Result := Result + '"';
end;

procedure Step1_Types;
begin
  Section('1. type - what counts as integer');
  GSchema := '{"type":"integer"}';

  ExpectValid('Integer', '5');
  ExpectValid('Negative integer', '-5');
  ExpectInvalid('Fraction', '5.5', 'type');
  ExpectInvalid('Text', '"5"', 'type');

  // According to the specification 5.0 IS an integer - the zero fraction
  // does not change the value. Whoever looks at the token type instead of the
  // value fails here.
  ExpectValid('5.0 counts as integer', '5.0');
  ExpectValid('1e2 counts as integer', '1e2');
  ExpectInvalid('1e-2 does not', '1e-2', 'type');

  GSchema := '{"type":["string","null"]}';
  ExpectValid('Union: text', '"a"');
  ExpectValid('Union: null', 'null');
  ExpectInvalid('Union: number', '1', 'type');
end;

procedure Step2_NumberLimits;
begin
  Section('2. Number limits without floating point loss');
  GSchema := '{"type":"integer","minimum":18}';
  ExpectValid('exactly 18', '18');
  ExpectInvalid('17', '17', 'minimum');

  GSchema := '{"maximum":33}';
  ExpectValid('33 percent', '33');
  ExpectInvalid('33.01 percent', '33.01', 'maximum');

  GSchema := '{"exclusiveMinimum":0}';
  ExpectInvalid('0 is excluded', '0', 'exclusiveMinimum');
  ExpectValid('smallest positive value', '1e-30');

  // This is exactly where every validator that compares via Double fails:
  // both numbers round to the same Double.
  GSchema := '{"maximum":9007199254740992}';
  ExpectInvalid('9007199254740993 is larger', '9007199254740993', 'maximum');

  GSchema := '{"minimum":-9223372036854775808}';
  ExpectValid('Int64 lower bound', '-9223372036854775808');
  ExpectInvalid('one below', '-9223372036854775809', 'minimum');

  GSchema := '{"multipleOf":0.1}';
  ExpectValid('0.3 is a multiple of 0.1', '0.3');
  ExpectInvalid('0.35 is not', '0.35', 'multipleOf');
  // In Double 0.1 + 0.2 <> 0.3 - computed exactly it is correct.
  ExpectValid('1e3 as well', '1e3');

  GSchema := '{"multipleOf":3}';
  ExpectValid('9', '9');
  ExpectInvalid('10', '10', 'multipleOf');
end;

procedure Step3_Strings;
begin
  Section('3. Strings - length counts code points');
  GSchema := '{"type":"string","minLength":2,"maxLength":4}';
  ExpectValid('two characters', '"ab"');
  ExpectInvalid('one character', '"a"', 'minLength');

  // An emoji is ONE code point, but two UTF-16 units in Delphi.
  // Whoever uses Length() counts 2 instead of 1 here. The character is written as a
  // surrogate pair in the source, so that no file encoding interferes.
  ExpectInvalid('one emoji is one code point', Emojis(1), 'minLength');
  ExpectValid('two emojis are two', Emojis(2));
  ExpectValid('four emojis are four', Emojis(4));
  ExpectInvalid('five are too many', Emojis(5), 'maxLength');

  // pattern is NOT anchored - it searches, it does not compare.
  GSchema := '{"pattern":"ab"}';
  ExpectValid('Match in the middle', '"xxabxx"');
  ExpectInvalid('no match', '"xxxx"', 'pattern');

  GSchema := '{"pattern":"^ab$"}';
  ExpectValid('anchored and exact', '"ab"');
  ExpectInvalid('anchored, but longer', '"xxabxx"', 'pattern');

  // pattern only applies to strings, everything else passes.
  GSchema := '{"pattern":"^[0-9]+$"}';
  ExpectValid('A number is not a string, so untouched', '12.5');
end;

procedure Step4_ObjectsAndRequiredFields;
begin
  Section('4. Objects, required fields, additional fields');
  GSchema := '{"type":"object","properties":{"Name":{"type":"string"},' +
             '"Age":{"type":"integer","minimum":18}},"required":["Name"]}';

  ExpectValid('complete', '{"Name":"Anna","Age":40}');
  ExpectValid('Age missing - not required', '{"Name":"Anna"}');
  ExpectInvalid('Name missing', '{"Age":40}', 'required');
  ExpectInvalid('too young', '{"Name":"Kim","Age":17}', 'minimum');
  ExpectValid('unknown field is allowed', '{"Name":"Anna","Extra":1}');

  GSchema := '{"type":"object","properties":{"Name":{"type":"string"}},' +
             '"additionalProperties":false}';
  ExpectValid('only known fields', '{"Name":"Anna"}');
  ExpectInvalid('now the extra field is in the way', '{"Name":"Anna","Extra":1}', 'false');

  // additionalProperties may ONLY see what properties and
  // patternProperties leave over.
  GSchema := '{"properties":{"a":true},"patternProperties":{"^x":true},' +
             '"additionalProperties":false}';
  ExpectValid('a from properties, xy from patternProperties', '{"a":1,"xy":2}');
  ExpectInvalid('b from neither', '{"b":1}', 'false');

  GSchema := '{"dependentRequired":{"Card":["Holder"]}}';
  ExpectValid('without card no holder needed', '{"Amount":1}');
  ExpectInvalid('with card it is', '{"Card":"x"}', 'dependentRequired');
  ExpectValid('both present', '{"Card":"x","Holder":"Anna"}');
end;

procedure Step5_Lists;
begin
  Section('5. Lists');
  GSchema := '{"type":"array","items":{"type":"integer"},"minItems":1,"maxItems":3}';
  ExpectValid('three integers', '[1,2,3]');
  ExpectInvalid('empty', '[]', 'minItems');
  ExpectInvalid('four', '[1,2,3,4]', 'maxItems');
  ExpectInvalid('a text in between', '[1,"a",3]', 'type');

  GSchema := '{"type":"array","uniqueItems":true}';
  ExpectValid('distinct', '[1,2,3]');
  ExpectInvalid('duplicate', '[1,2,1]', 'uniqueItems');
  // 1 and 1.0 are the same value - the comparison must use the numeric
  // value, not the text.
  ExpectInvalid('1 and 1.0 are equal', '[1,1.0]', 'uniqueItems');
  ExpectValid('1 and "1" are not', '[1,"1"]');
  ExpectInvalid('equal objects, different order',
    '[{"a":1,"b":2},{"b":2,"a":1}]', 'uniqueItems');
  ExpectValid('different objects', '[{"a":1},{"a":2}]');

  GSchema := '{"prefixItems":[{"type":"string"},{"type":"integer"}],"items":false}';
  ExpectValid('Text, then number', '["a",1]');
  ExpectInvalid('swapped', '[1,"a"]', 'type');
  ExpectInvalid('one element too many', '["a",1,2]', 'false');

  GSchema := '{"contains":{"type":"integer","minimum":10}}';
  ExpectValid('one is large enough', '[1,2,50]');
  ExpectInvalid('none', '[1,2,3]', 'contains');
end;

procedure Step6_Logic;
begin
  Section('6. Logic - oneOf means EXACTLY one');
  GSchema := '{"oneOf":[{"type":"integer"},{"type":"number","minimum":5}]}';
  // 7 satisfies both branches - with oneOf that is an error.
  ExpectInvalid('7 matches both', '7', 'oneOf');
  ExpectValid('3 matches only the first', '3');
  ExpectValid('7.5 matches only the second', '7.5');
  ExpectInvalid('Text matches neither', '"a"', 'oneOf');

  GSchema := '{"anyOf":[{"type":"integer"},{"minimum":5}]}';
  ExpectValid('with anyOf both are fine', '7');

  GSchema := '{"allOf":[{"type":"integer"},{"minimum":5}]}';
  ExpectValid('both satisfied', '7');
  ExpectInvalid('only one', '3', 'minimum');

  GSchema := '{"not":{"type":"string"}}';
  ExpectValid('Number', '1');
  ExpectInvalid('Text', '"a"', 'not');

  GSchema := '{"if":{"properties":{"Country":{"const":"DE"}},"required":["Country"]},' +
             '"then":{"required":["TaxId"]},"else":{"required":["Vat"]}}';
  ExpectValid('DE with TaxId', '{"Country":"DE","TaxId":"DE1"}');
  ExpectInvalid('DE without TaxId', '{"Country":"DE"}', 'required');
  ExpectValid('other country with Vat', '{"Country":"FR","Vat":"FR1"}');

  GSchema := '{"enum":[1,"a",null,{"x":1}]}';
  ExpectValid('Number from the list', '1');
  ExpectValid('Object from the list', '{"x":1}');
  ExpectInvalid('not in the list', '2', 'enum');
  ExpectValid('1.0 is the same value as 1', '1.0');
end;

procedure Step7_References;
begin
  Section('7. $ref and recursion');
  GSchema := '{"$defs":{"Pos":{"type":"object","properties":' +
             '{"Quantity":{"type":"integer","minimum":1}},"required":["Quantity"]}},' +
             '"type":"object","properties":{"Lines":{"type":"array",' +
             '"items":{"$ref":"#/$defs/Pos"}}}}';
  ExpectValid('two good lines', '{"Lines":[{"Quantity":1},{"Quantity":5}]}');
  ExpectInvalid('Quantity 0', '{"Lines":[{"Quantity":0}]}', 'minimum');
  ExpectInvalid('Quantity missing', '{"Lines":[{}]}', 'required');

  // A schema that references itself. Without cycle protection
  // the validator hangs here instead of giving an answer.
  GSchema := '{"$defs":{"Node":{"type":"object","properties":' +
             '{"Val":{"type":"integer"},"Child":{"$ref":"#/$defs/Node"}}}},' +
             '"$ref":"#/$defs/Node"}';
  ExpectValid('three levels deep', '{"Val":1,"Child":{"Val":2,"Child":{"Val":3}}}');
  ExpectInvalid('Error on the third level',
    '{"Val":1,"Child":{"Val":2,"Child":{"Val":"x"}}}', 'type');
end;

procedure Step8_ErrorPaths;
var
  R: TJsonSchemaValidationResult;
begin
  Section('8. The error must say WHERE it is');
  GSchema := '{"type":"object","properties":{"Lines":{"type":"array",' +
             '"items":{"type":"object","properties":{"Quantity":{"type":"integer"}}}}}}';

  R := JsonConvert.ValidateJsonSchema('{"Lines":[{"Quantity":1},{"Quantity":"x"}]}', GSchema);
  CheckTrue('is rejected', not R.IsValid, R.ToString);
  if R.ErrorCount > 0 then
  begin
    Show('Msg', R.ToString);
    Check('JSON pointer to the second element', '/Lines/1/Quantity',
      R.Errors[0].InstancePath);
    Check('KeywordName', 'type', R.Errors[0].Keyword);
  end
  else
    CheckTrue('Error list is not empty', False, '0 entries');

  // A name with / and ~ must be escaped in the pointer.
  GSchema := '{"properties":{"a/b~c":{"type":"integer"}}}';
  R := JsonConvert.ValidateJsonSchema('{"a/b~c":"x"}', GSchema);
  if R.ErrorCount > 0 then
    Check('Escaped pointer', '/a~1b~0c', R.Errors[0].InstancePath)
  else
    CheckTrue('Escaped pointer', False, 'no error reported');
end;

procedure Step9_Limits;
var
  Opts: TJsonSchemaValidationOptions;
  R: TJsonSchemaValidationResult;
begin
  Section('9. Options - stop, upper limits, broken schemas');
  GSchema := '{"type":"object","properties":{"a":{"type":"integer"},' +
             '"b":{"type":"integer"},"c":{"type":"integer"}}}';

  R := JsonConvert.ValidateJsonSchema('{"a":"x","b":"x","c":"x"}', GSchema);
  Check('without a limit all three', 3, R.ErrorCount);

  Opts := TJsonSchemaValidationOptions.Create;
  try
    Opts.StopOnFirstError := True;
    R := JsonConvert.ValidateJsonSchema('{"a":"x","b":"x","c":"x"}', GSchema, Opts);
    Check('with stop only one', 1, R.ErrorCount);

    Opts.StopOnFirstError := False;
    Opts.MaxErrors := 2;
    R := JsonConvert.ValidateJsonSchema('{"a":"x","b":"x","c":"x"}', GSchema, Opts);
    Check('with upper limit two', 2, R.ErrorCount);
  finally
    Opts.Free;
  end;

  // A schema that is itself broken must be noticed on creation
  // - not somewhere in the middle of a validation.
  CheckError('minLength as text is rejected',
    procedure
    begin
      JsonConvert.ValidateJsonSchema('"a"', '{"minLength":"two"}');
    end);

  CheckError('broken regular expression is rejected',
    procedure
    begin
      JsonConvert.ValidateJsonSchema('"a"', '{"pattern":"["}');
    end);

  CheckError('type with an unknown name is rejected',
    procedure
    begin
      JsonConvert.ValidateJsonSchema('"a"', '{"type":"num"}');
    end);

  // By default formats are only descriptive, not binding.
  GSchema := '{"type":"string","format":"date"}';
  ExpectValid('Format is not checked by default', '"no date"');

  Opts := TJsonSchemaValidationOptions.Create;
  try
    Opts.AssertFormats := True;
    R := JsonConvert.ValidateJsonSchema('"no date"', GSchema, Opts);
    CheckTrue('when enabled it is', not R.IsValid, R.ToString);
    R := JsonConvert.ValidateJsonSchema('"2026-09-09"', GSchema, Opts);
    CheckTrue('valid date passes', R.IsValid, R.ToString);
    R := JsonConvert.ValidateJsonSchema('"2026-02-30"', GSchema, Opts);
    CheckTrue('February 30 does not', not R.IsValid, R.ToString);
  finally
    Opts.Free;
  end;
end;

procedure Step10_ExactNumbers;
var
  A, B: TJsonExactNumber;
begin
  Section('10. The number core directly');

  CheckTrue('1e2 = 100', TJsonExactNumber.TryParse('1e2', A) and
    TJsonExactNumber.TryParse('100', B) and A.Equals(B), '');

  CheckTrue('1.0 = 1', TJsonExactNumber.TryParse('1.0', A) and
    TJsonExactNumber.TryParse('1', B) and A.Equals(B), '');

  CheckTrue('1.0 is an integer',
    TJsonExactNumber.TryParse('1.0', A) and A.IsInteger, '');
  CheckTrue('1.5 is not',
    TJsonExactNumber.TryParse('1.5', A) and not A.IsInteger, '');

  CheckTrue('9007199254740993 > 9007199254740992',
    TJsonExactNumber.TryParse('9007199254740993', A) and
    TJsonExactNumber.TryParse('9007199254740992', B) and (A.Compare(B) > 0),
    'in Double both would be equal');

  CheckTrue('0.3 is a multiple of 0.1',
    TJsonExactNumber.TryParse('0.3', A) and
    TJsonExactNumber.TryParse('0.1', B) and A.IsMultipleOf(B), '');
  CheckTrue('0.35 is not',
    TJsonExactNumber.TryParse('0.35', A) and
    TJsonExactNumber.TryParse('0.1', B) and not A.IsMultipleOf(B), '');

  CheckTrue('1 is a multiple of 0.5',
    TJsonExactNumber.TryParse('1', A) and
    TJsonExactNumber.TryParse('0.5', B) and A.IsMultipleOf(B), '');
  CheckTrue('2 is not a multiple of 4',
    TJsonExactNumber.TryParse('2', A) and
    TJsonExactNumber.TryParse('4', B) and not A.IsMultipleOf(B), '');
  CheckTrue('100 is not a multiple of 1000',
    TJsonExactNumber.TryParse('100', A) and
    TJsonExactNumber.TryParse('1000', B) and not A.IsMultipleOf(B), '');

  CheckTrue('leading zero is rejected',
    not TJsonExactNumber.TryParse('01', A), '');
  CheckTrue('dot without a fraction digit is rejected',
    not TJsonExactNumber.TryParse('1.', A), '');
  CheckTrue('e without digits is rejected',
    not TJsonExactNumber.TryParse('1e', A), '');
  CheckTrue('hexadecimal is rejected',
    not TJsonExactNumber.TryParse('0x10', A), '');
end;

procedure Step11_ClosedLoop;
var
  Customer: TCustomer;
  PurchaseOrder: TPurchaseOrder;
  Pos: TLineItem;
  SchemaObj: TJsonObject;
  Schema, Json: string;
  R: TJsonSchemaValidationResult;
begin
  Section('11. Generator, serializer and validator in a closed loop');
  Writeln('       GenerateSchema<T> creates the schema, SerializeObject the');
  Writeln('       instance. If the two drift apart, you can only see it');
  Writeln('       here.');

  SchemaObj := JsonConvert.GenerateSchema<TCustomer>;
  try
    Schema := SchemaObj.ToJson;
  finally
    SchemaObj.Free;
  end;
  Show('Schema', Schema);

  Customer := TCustomer.Create;
  try
    Customer.Name := 'Anna';
    Customer.Age := 40;
    Customer.Credit := 1234.56;
    Customer.Active := True;
    Json := JsonConvert.SerializeObject(Customer);
  finally
    Customer.Free;
  end;
  Show('Instance', Json);

  R := JsonConvert.ValidateJsonSchema(Json, Schema);
  CheckTrue('own output matches its own schema', R.IsValid, R.ToString);

  // Bent by hand: the type no longer matches.
  R := JsonConvert.ValidateJsonSchema('{"Name":"Anna","Age":"forty",' +
    '"Credit":1234.56,"Active":true}', Schema);
  CheckTrue('bent type is noticed', not R.IsValid, R.ToString);

  // Nested, with $ref to the line item class.
  SchemaObj := JsonConvert.GenerateSchema<TPurchaseOrder>;
  try
    Schema := SchemaObj.ToJson;
  finally
    SchemaObj.Free;
  end;
  Show('Schema with $ref', Schema);

  PurchaseOrder := TPurchaseOrder.Create;
  try
    PurchaseOrder.Number := 'A-1';
    Pos := TLineItem.Create;
    Pos.Article := 'Widget';
    Pos.Quantity := 2;
    PurchaseOrder.LineItems.Add(Pos);
    Json := JsonConvert.SerializeObject(PurchaseOrder);
  finally
    PurchaseOrder.Free;
  end;
  Show('Instance', Json);

  R := JsonConvert.ValidateJsonSchema(Json, Schema);
  CheckTrue('nested output matches too', R.IsValid, R.ToString);
end;

// ---------------------------------------------------------------------------

begin
  try
    Title('TEST PACKAGE 2 - JSON SCHEMA VALIDATION');

    Step1_Types;
    Step2_NumberLimits;
    Step3_Strings;
    Step4_ObjectsAndRequiredFields;
    Step5_Lists;
    Step6_Logic;
    Step7_References;
    Step8_ErrorPaths;
    Step9_Limits;
    Step10_ExactNumbers;
    Step11_ClosedLoop;

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
