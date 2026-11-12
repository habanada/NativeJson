{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit NativeJson.Deserializer.Activator;

interface

{$I NativeJson.inc}

uses
  {$IFDEF FPC}
  SysUtils,
  Rtti,
  TypInfo;
  {$ELSE}
  System.SysUtils,
  System.Rtti,
  System.TypInfo;
  {$ENDIF}

type
  EJsonActivatorError = class(Exception);

  TJsonActivator = record
  private
    class function CreateClass(RttiType: TRttiInstanceType): TValue; static;
    class function CreateRecord(RttiType: TRttiRecordType): TValue; static;
  public
    class function CreateInstance(TypeInfo: PTypeInfo): TValue; static;
  end;

implementation

class function TJsonActivator.CreateInstance(TypeInfo: PTypeInfo): TValue;
var
  Ctx: TRttiContext;
  RType: TRttiType;
begin
  if TypeInfo = nil then
    Exit(TValue.Empty);
  Ctx := TRttiContext.Create;
  try
    RType := Ctx.GetType(TypeInfo);
    if RType = nil then
      raise EJsonActivatorError.Create('Cannot resolve RTTI type');
    case RType.TypeKind of
      tkClass:
        Result := CreateClass(TRttiInstanceType(RType));
      tkRecord:
        Result := CreateRecord(TRttiRecordType(RType));
      tkDynArray, tkArray:
        TValue.Make(nil, TypeInfo, Result);
    else
      TValue.Make(nil, TypeInfo, Result);
    end;
  finally
    Ctx.Free;
  end;
end;

class function TJsonActivator.CreateClass(RttiType: TRttiInstanceType): TValue;
var
  Method: TRttiMethod;
  ConstructorFound: TRttiMethod;
  InstanceObj: TObject;
begin
  ConstructorFound := nil;
  for Method in RttiType.GetMethods do
  begin
    if Method.IsConstructor and (Length(Method.GetParameters) = 0) then
    begin
      ConstructorFound := Method;
      Break;
    end;
  end;
  if ConstructorFound <> nil then
    Result := ConstructorFound.Invoke(RttiType.MetaclassType, [])
  else if RttiType.MetaclassType <> nil then
  begin
    InstanceObj := RttiType.MetaclassType.Create;
    TValue.Make(@InstanceObj, RttiType.Handle, Result);
  end
  else
    raise EJsonActivatorError.CreateFmt('No parameterless constructor defined for class %s', [RttiType.Name]);
end;

class function TJsonActivator.CreateRecord(RttiType: TRttiRecordType): TValue;
begin
  TValue.Make(nil, RttiType.Handle, Result);
end;

end.
