{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit NativeJson.Comparer;

interface

{$I NativeJson.inc}

uses
  NativeJson.Dom.Value;

type
  // Semantic JSON equality.
  //
  // Objects are compared independent of member order, arrays keep their
  // order, and JSON numbers are compared by exact numeric value rather than
  // through Double or their original textual representation.
  TJsonComparer = record
  public
    class function DeepEquals(const Left, Right: TJsonValue): Boolean; static;
  end;

implementation

uses
  {$IFDEF FPC}
  Generics.Collections,
  {$ELSE}
  System.Generics.Collections,
  {$ENDIF}
  NativeJson.Dom.JsonObject,
  NativeJson.Dom.JsonArray,
  NativeJson.ExactNumber;

function IsNumberType(JsonType: TJsonType): Boolean;
begin
  Result := JsonType in [TJsonType.jtInteger, TJsonType.jtFloat];
end;

function NumbersEqual(const Left, Right: TJsonValue): Boolean;
var
  LeftNumber, RightNumber: TJsonExactNumber;
  LeftText, RightText: string;
begin
  LeftText := Left.AsRawText;
  RightText := Right.AsRawText;

  if LeftText = RightText then
    Exit(True);

  if TJsonExactNumber.TryParse(LeftText, LeftNumber) and
     TJsonExactNumber.TryParse(RightText, RightNumber) then
    Exit(LeftNumber.Equals(RightNumber));

  // A caller can construct a custom/non-standard numeric DOM node directly.
  // Do not fall back to Double here: that could turn distinct large values
  // into equal ones. Raw equality is deterministic and lossless.
  Result := LeftText = RightText;
end;

class function TJsonComparer.DeepEquals(const Left, Right: TJsonValue): Boolean;
var
  LeftType, RightType: TJsonType;
  LeftObject, RightObject: TJsonObject;
  LeftArray, RightArray: TJsonArray;
  Pair: TPair<string, TJsonValue>;
  OtherValue: TJsonValue;
  I: Integer;
begin
  if Left = Right then
    Exit(True);
  if (Left = nil) or (Right = nil) then
    Exit(False);

  LeftType := Left.GetJsonType;
  RightType := Right.GetJsonType;

  // JSON has one number domain. jtInteger/jtFloat are NativeJson storage
  // details and must not make 1 different from 1.0 or 1e0.
  if IsNumberType(LeftType) or IsNumberType(RightType) then
  begin
    if not (IsNumberType(LeftType) and IsNumberType(RightType)) then
      Exit(False);
    Exit(NumbersEqual(Left, Right));
  end;

  if LeftType <> RightType then
    Exit(False);

  case LeftType of
    TJsonType.jtObject:
      begin
        if not (Left is TJsonObject) or not (Right is TJsonObject) then
          Exit(False);

        LeftObject := TJsonObject(Left);
        RightObject := TJsonObject(Right);
        if LeftObject.Count <> RightObject.Count then
          Exit(False);

        for Pair in LeftObject do
        begin
          if not RightObject.TryGetValue(Pair.Key, OtherValue) then
            Exit(False);
          if not DeepEquals(Pair.Value, OtherValue) then
            Exit(False);
        end;
        Result := True;
      end;

    TJsonType.jtArray:
      begin
        if not (Left is TJsonArray) or not (Right is TJsonArray) then
          Exit(False);

        LeftArray := TJsonArray(Left);
        RightArray := TJsonArray(Right);
        if LeftArray.Count <> RightArray.Count then
          Exit(False);

        for I := 0 to LeftArray.Count - 1 do
          if not DeepEquals(LeftArray[I], RightArray[I]) then
            Exit(False);
        Result := True;
      end;

    TJsonType.jtString,
    TJsonType.jtDate,
    TJsonType.jtBytes:
      Result := Left.AsRawText = Right.AsRawText;

    TJsonType.jtBoolean:
      Result := Left.AsBoolean = Right.AsBoolean;

    TJsonType.jtNull:
      Result := True;

    TJsonType.jtNone:
      // jtNone is not a normal JSON value. Keep equality conservative for
      // custom nodes while still allowing semantically identical values.
      Result := Left.ToJson = Right.ToJson;
  else
    Result := False;
  end;
end;

end.
