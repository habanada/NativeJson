{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit NativeJson.Serializer.Converter;
interface

{$I NativeJson.inc}
uses
  {$IFDEF FPC}
  SysUtils,
  TypInfo,
  Rtti,
  {$ELSE}
  System.SysUtils,
  System.TypInfo,
  System.Rtti,
  {$ENDIF}
  NativeJson.Core.Reader,
  NativeJson.Serializer.Writer;
type
  EJsonConverterError = class(Exception);
  // Forward declaration to avoid circular dependency with NativeJson.Serializer.Core
  // We use TObject in signatures, implementation casts to TJsonSerializer
  TJsonSerializerContext = TObject;
  TJsonConverter = class abstract
  public
    // Determines whether this converter can handle the given type
    function CanConvert(TypeInfo: PTypeInfo): Boolean; virtual; abstract;
    // Reads JSON and creates an object
    // Reader: the JSON reader (positioned on the start token of the value)
    // ObjectType: the target type
    // ExistingValue: when filling an existing object (e.g. for lists), otherwise Empty
    // Serializer: reference for recursive calls
    function ReadJson(Reader: TJsonReader;
                      ObjectType: PTypeInfo;
                      const ExistingValue: TValue;
                      Serializer: TJsonSerializerContext): TValue; virtual; abstract;
    // Writes an object as JSON
    // Writer: the output
    // Value: the value to write
    // Serializer: reference for recursive calls
    procedure WriteJson(Writer: TJsonWriter;
                        const Value: TValue;
                        Serializer: TJsonSerializerContext); virtual; abstract;
    // Optional: CanRead / CanWrite (default: True)
    function CanRead: Boolean; virtual;
    function CanWrite: Boolean; virtual;
  end;
  // Type definition for converter classes
  TJsonConverterClass = class of TJsonConverter;
implementation
{ TJsonConverter }
function TJsonConverter.CanRead: Boolean;
begin
  Result := True;
end;
function TJsonConverter.CanWrite: Boolean;
begin
  Result := True;
end;
end.
