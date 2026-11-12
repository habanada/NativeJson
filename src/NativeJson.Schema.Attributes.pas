{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit NativeJson.Schema.Attributes;

interface

{$I NativeJson.inc}

uses
  {$IFDEF FPC}
  SysUtils;
  {$ELSE}
  System.SysUtils;
  {$ENDIF}

type
  TJsonSchemaAttribute = class(TCustomAttribute)
  public
    constructor Create;
  end;

  JsonTitleAttribute = class(TJsonSchemaAttribute)
  private
    FTitle: string;
  public
    constructor Create(const Title: string);
    property Title: string read FTitle;
  end;

  JsonDescriptionAttribute = class(TJsonSchemaAttribute)
  private
    FText: string;
  public
    constructor Create(const Text: string);
    property Text: string read FText;
  end;

  JsonSchemaFormatAttribute = class(TJsonSchemaAttribute)
  private
    FFormatName: string;
  public
    constructor Create(const FormatName: string);
    property FormatName: string read FFormatName;
  end;

  JsonRequiredAttribute = class(TJsonSchemaAttribute);

  JsonRangeAttribute = class(TJsonSchemaAttribute)
  private
    FMin, FMax: Double;
    FHasMin, FHasMax: Boolean;
  public
    constructor Create(const Min, Max: string); overload;
    constructor Create(Min, Max: Double); overload;
    constructor CreateMin(Min: Double); overload;
    constructor CreateMax(Max: Double); overload;
    property Min: Double read FMin;
    property Max: Double read FMax;
    property HasMin: Boolean read FHasMin;
    property HasMax: Boolean read FHasMax;
  end;

  JsonExclusiveRangeAttribute = class(TJsonSchemaAttribute)
  private
    FMin, FMax: Double;
    FHasMin, FHasMax: Boolean;
  public
    constructor Create(const Min, Max: string); overload;
    constructor Create(Min, Max: Double); overload;
    constructor CreateMin(Min: Double); overload;
    constructor CreateMax(Max: Double); overload;
    property Min: Double read FMin;
    property Max: Double read FMax;
    property HasMin: Boolean read FHasMin;
    property HasMax: Boolean read FHasMax;
  end;

  JsonMultipleOfAttribute = class(TJsonSchemaAttribute)
  private
    FValue: Double;
  public
    constructor Create(const Value: string); overload;
    constructor Create(Value: Double); overload;
    property Value: Double read FValue;
  end;

  JsonPatternAttribute = class(TJsonSchemaAttribute)
  private
    FPattern: string;
  public
    constructor Create(const Pattern: string);
    property Pattern: string read FPattern;
  end;

  JsonMinLengthAttribute = class(TJsonSchemaAttribute)
  private
    FLength: Integer;
  public
    constructor Create(Length: Integer);
    property Length: Integer read FLength;
  end;

  JsonMaxLengthAttribute = class(TJsonSchemaAttribute)
  private
    FLength: Integer;
  public
    constructor Create(Length: Integer);
    property Length: Integer read FLength;
  end;

  JsonArrayLengthAttribute = class(TJsonSchemaAttribute)
  private
    FMin, FMax: Integer;
    FHasMin, FHasMax: Boolean;
  public
    constructor Create(Min, Max: Integer); overload;
    constructor CreateMin(Min: Integer); overload;
    constructor CreateMax(Max: Integer); overload;
    property Min: Integer read FMin;
    property Max: Integer read FMax;
    property HasMin: Boolean read FHasMin;
    property HasMax: Boolean read FHasMax;
  end;

  JsonUniqueItemsAttribute = class(TJsonSchemaAttribute);

  JsonReadOnlyAttribute = class(TJsonSchemaAttribute);

  JsonWriteOnlyAttribute = class(TJsonSchemaAttribute);

  JsonDeprecatedAttribute = class(TJsonSchemaAttribute)
  private
    FReason: string;
  public
    constructor Create(const Reason: string = '');
    property Reason: string read FReason;
  end;

  JsonExampleAttribute = class(TJsonSchemaAttribute)
  private
    FValue: string;
  public
    constructor Create(const Value: string);
    property Value: string read FValue;
  end;

  JsonSchemaExtensionAttribute = class(TJsonSchemaAttribute)
  private
    FKey, FValue: string;
  public
    constructor Create(const Key, Value: string);
    property Key: string read FKey;
    property Value: string read FValue;
  end;



implementation

constructor TJsonSchemaAttribute.Create;
begin
  inherited Create;
end;

{ JsonTitleAttribute }

constructor JsonTitleAttribute.Create(const Title: string);
begin
  FTitle := Title;
end;

{ JsonDescriptionAttribute }

constructor JsonDescriptionAttribute.Create(const Text: string);
begin
  FText := Text;
end;

{ JsonSchemaFormatAttribute }

constructor JsonSchemaFormatAttribute.Create(const FormatName: string);
begin
  FFormatName := FormatName;
end;

function ParseInvariantFloat(const Value, AttributeName: string): Double;
var
  FormatSettings: TFormatSettings;
begin
  FormatSettings := TFormatSettings.Invariant;
  if not TryStrToFloat(Value, Result, FormatSettings) then
    raise EConvertError.CreateFmt('%s: invalid invariant floating-point value "%s"', [AttributeName, Value]);
end;

{ JsonRangeAttribute }

constructor JsonRangeAttribute.Create(const Min, Max: string);
begin
  FMin := ParseInvariantFloat(Min, 'JsonRange');
  FMax := ParseInvariantFloat(Max, 'JsonRange');
  FHasMin := True;
  FHasMax := True;
end;

constructor JsonRangeAttribute.Create(Min, Max: Double);
begin
  FMin := Min;
  FMax := Max;
  FHasMin := True;
  FHasMax := True;
end;

constructor JsonRangeAttribute.CreateMin(Min: Double);
begin
  FMin := Min;
  FHasMin := True;
  FHasMax := False;
  FMax := 0;
end;

constructor JsonRangeAttribute.CreateMax(Max: Double);
begin
  FMax := Max;
  FHasMin := False;
  FHasMax := True;
  FMin := 0;
end;

{ JsonExclusiveRangeAttribute }

constructor JsonExclusiveRangeAttribute.Create(const Min, Max: string);
begin
  FMin := ParseInvariantFloat(Min, 'JsonExclusiveRange');
  FMax := ParseInvariantFloat(Max, 'JsonExclusiveRange');
  FHasMin := True;
  FHasMax := True;
end;

constructor JsonExclusiveRangeAttribute.Create(Min, Max: Double);
begin
  FMin := Min;
  FMax := Max;
  FHasMin := True;
  FHasMax := True;
end;

constructor JsonExclusiveRangeAttribute.CreateMin(Min: Double);
begin
  FMin := Min;
  FHasMin := True;
  FHasMax := False;
  FMax := 0;
end;

constructor JsonExclusiveRangeAttribute.CreateMax(Max: Double);
begin
  FMax := Max;
  FHasMin := False;
  FHasMax := True;
  FMin := 0;
end;

{ JsonMultipleOfAttribute }

constructor JsonMultipleOfAttribute.Create(const Value: string);
begin
  FValue := ParseInvariantFloat(Value, 'JsonMultipleOf');
end;

constructor JsonMultipleOfAttribute.Create(Value: Double);
begin
  FValue := Value;
end;

{ JsonPatternAttribute }

constructor JsonPatternAttribute.Create(const Pattern: string);
begin
  FPattern := Pattern;
end;

{ JsonMinLengthAttribute }

constructor JsonMinLengthAttribute.Create(Length: Integer);
begin
  FLength := Length;
end;

{ JsonMaxLengthAttribute }

constructor JsonMaxLengthAttribute.Create(Length: Integer);
begin
  FLength := Length;
end;

{ JsonArrayLengthAttribute }

constructor JsonArrayLengthAttribute.Create(Min, Max: Integer);
begin
  FMin := Min;
  FMax := Max;
  FHasMin := True;
  FHasMax := True;
end;

constructor JsonArrayLengthAttribute.CreateMin(Min: Integer);
begin
  FMin := Min;
  FHasMin := True;
  FHasMax := False;
  FMax := 0;
end;

constructor JsonArrayLengthAttribute.CreateMax(Max: Integer);
begin
  FMax := Max;
  FHasMin := False;
  FHasMax := True;
  FMin := 0;
end;

{ JsonDeprecatedAttribute }

constructor JsonDeprecatedAttribute.Create(const Reason: string);
begin
  FReason := Reason;
end;

{ JsonExampleAttribute }

constructor JsonExampleAttribute.Create(const Value: string);
begin
  FValue := Value;
end;

{ JsonSchemaExtensionAttribute }

constructor JsonSchemaExtensionAttribute.Create(const Key, Value: string);
begin
  FKey := Key;
  FValue := Value;
end;



end.