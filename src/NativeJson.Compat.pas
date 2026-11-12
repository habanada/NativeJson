{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit NativeJson.Compat;

interface

{$I NativeJson.inc}

uses
  {$IFDEF FPC}
  SysUtils,
  TypInfo,
  Rtti,
  Generics.Defaults;
  {$ELSE}
  System.SysUtils,
  System.TypInfo,
  System.Rtti,
  System.Generics.Defaults;
  {$ENDIF}

type
  TJsonStringBuilder = {$IFDEF FPC}TUnicodeStringBuilder{$ELSE}TStringBuilder{$ENDIF};
  TJsonIStringComparer = {$IFDEF FPC}TIUnicodeStringComparer{$ELSE}TIStringComparer{$ENDIF};
  TJsonHashCode = {$IFDEF FPC}UInt32{$ELSE}Integer{$ENDIF};
  TJsonToStringResult = {$IFDEF FPC}RTLString{$ELSE}string{$ENDIF};

{$IFDEF FPC}
  TJsonUtf8NoBomEncoding = class(TUTF8Encoding)
  public
    function GetPreamble: TBytes; override;
  end;
{$ENDIF}

{$IFDEF FPC}
  TProc = reference to procedure;
  TProc<T> = reference to procedure(Arg1: T);
  TProc<T1, T2> = reference to procedure(Arg1: T1; Arg2: T2);
  TFunc<TResult> = reference to function: TResult;
  TFunc<T, TResult> = reference to function(Arg1: T): TResult;
  TFunc<T1, T2, TResult> = reference to function(Arg1: T1; Arg2: T2): TResult;
  TPredicate<T> = reference to function(Arg1: T): Boolean;

  TLightweightMREW = record
  private
    FLock: TRTLCriticalSection;
  public
    class operator Initialize(var Target: TLightweightMREW);
    class operator Finalize(var Target: TLightweightMREW);
    procedure BeginRead;
    procedure EndRead;
    procedure BeginWrite;
    procedure EndWrite;
  end;

const
  MaxComp = 9.223372036854775807e18;
{$ENDIF}

function JsonTypeKind(ATypeInfo: PTypeInfo): TTypeKind; overload; inline;
function JsonTypeKind(const AValue: TValue): TTypeKind; overload; inline;
function JsonTypeKind(AType: TRttiType): TTypeKind; overload; inline;
function JsonDynArrayElementType(ATypeInfo: PTypeInfo): PTypeInfo;
function JsonSetElementType(ATypeInfo: PTypeInfo): PTypeInfo;
function JsonSetOrdinals(const AValue: TValue): TArray<Integer>;
function JsonSetFromOrdinals(ATypeInfo: PTypeInfo; const AOrdinals: TArray<Integer>): TValue;
function JsonRttiFindType(const ACtx: TRttiContext; const AQualifiedName: string): TRttiType;
function JsonRttiGetTypes(const ACtx: TRttiContext): TArray<TRttiType>;
function JsonCreateUtf8NoBom: TEncoding;
function JsonValueAsString(const AValue: TValue): string;
function JsonPropertyGetValue(AProperty: TRttiProperty; AInstance: Pointer): TValue;
procedure JsonPropertySetValue(AProperty: TRttiProperty; AInstance: Pointer; const AValue: TValue);

implementation

{$IFDEF FPC}
procedure NormalizeTypeKind(var Art: TTypeKind);
begin
  case Art of
    tkBool: Art := tkEnumeration;
    tkQWord: Art := tkInt64;
    tkAString: Art := tkLString;
  end;
end;
{$ENDIF}

function JsonTypeKind(ATypeInfo: PTypeInfo): TTypeKind;
begin
  Result := ATypeInfo^.Kind;
  {$IFDEF FPC}
  NormalizeTypeKind(Result);
  {$ENDIF}
end;

function JsonTypeKind(const AValue: TValue): TTypeKind;
begin
  Result := AValue.Kind;
  {$IFDEF FPC}
  NormalizeTypeKind(Result);
  {$ENDIF}
end;

function JsonTypeKind(AType: TRttiType): TTypeKind;
begin
  Result := AType.TypeKind;
  {$IFDEF FPC}
  NormalizeTypeKind(Result);
  {$ENDIF}
end;

function JsonDynArrayElementType(ATypeInfo: PTypeInfo): PTypeInfo;
{$IFNDEF FPC}
var
  Element: PPTypeInfo;
{$ENDIF}
begin
  Result := nil;
  if (ATypeInfo = nil) or (ATypeInfo^.Kind <> tkDynArray) then Exit;
  {$IFDEF FPC}
  Result := GetTypeData(ATypeInfo)^.ElType2;
  {$ELSE}
  Element := GetTypeData(ATypeInfo)^.elType2;
  if Element <> nil then Result := Element^;
  {$ENDIF}
end;

function JsonSetElementType(ATypeInfo: PTypeInfo): PTypeInfo;
{$IFNDEF FPC}
var
  Element: PPTypeInfo;
{$ENDIF}
begin
  Result := nil;
  if (ATypeInfo = nil) or (ATypeInfo^.Kind <> tkSet) then Exit;
  {$IFDEF FPC}
  Result := GetTypeData(ATypeInfo)^.CompType;
  {$ELSE}
  Element := GetTypeData(ATypeInfo)^.CompType;
  if Element <> nil then Result := Element^;
  {$ENDIF}
end;

function JsonSetBaseOrdinal(ATypeInfo: PTypeInfo): Integer;
var
  Element: PTypeInfo;
begin
  Result := 0;
  Element := JsonSetElementType(ATypeInfo);
  if (Element <> nil) and (Element^.Kind in [tkEnumeration, tkInteger, tkChar, tkWChar]) then
    Result := (GetTypeData(Element)^.MinValue div 8) * 8;
end;

function JsonSetOrdinals(const AValue: TValue): TArray<Integer>;
var
  Buffer: array[0..31] of Byte;
  Base, I, Count, Size: Integer;
begin
  Result := nil;
  if AValue.IsEmpty or (AValue.Kind <> tkSet) then Exit;
  Size := AValue.DataSize;
  if Size > SizeOf(Buffer) then Size := SizeOf(Buffer);
  FillChar(Buffer, SizeOf(Buffer), 0);
  Move(PByte(AValue.GetReferenceToRawData)^, Buffer[0], Size);
  Base := JsonSetBaseOrdinal(AValue.TypeInfo);
  Count := 0;
  SetLength(Result, Size * 8);
  for I := 0 to Size * 8 - 1 do
    if (Buffer[I shr 3] and (1 shl (I and 7))) <> 0 then
    begin
      Result[Count] := I + Base;
      Inc(Count);
    end;
  SetLength(Result, Count);
end;

function JsonSetFromOrdinals(ATypeInfo: PTypeInfo; const AOrdinals: TArray<Integer>): TValue;
var
  Buffer: array[0..31] of Byte;
  Base, Bit, Ordinal: Integer;
begin
  FillChar(Buffer, SizeOf(Buffer), 0);
  Base := JsonSetBaseOrdinal(ATypeInfo);
  for Ordinal in AOrdinals do
  begin
    Bit := Ordinal - Base;
    if (Bit < 0) or (Bit > 255) then raise ERangeError.CreateFmt('Set element %d is out of range', [Ordinal]);
    Buffer[Bit shr 3] := Buffer[Bit shr 3] or (1 shl (Bit and 7));
  end;
  TValue.Make(@Buffer[0], ATypeInfo, Result);
end;

function JsonRttiFindType(const ACtx: TRttiContext; const AQualifiedName: string): TRttiType;
begin
  {$IFDEF FPC}
  Result := nil;
  {$ELSE}
  Result := ACtx.FindType(AQualifiedName);
  {$ENDIF}
end;

function JsonRttiGetTypes(const ACtx: TRttiContext): TArray<TRttiType>;
begin
  {$IFDEF FPC}
  Result := nil;
  {$ELSE}
  Result := ACtx.GetTypes;
  {$ENDIF}
end;

{$IFDEF FPC}
type
  TCurrencyGetter = function: Currency of object;
  TIndexedCurrencyGetter = function(Index: Integer): Currency of object;
  TCurrencySetter = procedure(const InputValue: Currency) of object;
  TIndexedCurrencySetter = procedure(Index: Integer; InputValue: Currency) of object;

function IsCurrencyProperty(AProperty: TRttiProperty): Boolean;
var
  PropType: TRttiType;
begin
  PropType := AProperty.PropertyType;
  Result := (AProperty.Handle <> nil) and (PropType <> nil) and (PropType.Handle^.Kind = tkFloat) and
    (GetTypeData(PropType.Handle)^.FloatType = ftCurr);
end;
{$ENDIF}

{$IFDEF FPC}
function TJsonUtf8NoBomEncoding.GetPreamble: TBytes;
begin
  Result := nil;
end;
{$ENDIF}

function JsonCreateUtf8NoBom: TEncoding;
begin
  {$IFDEF FPC}
  Result := TJsonUtf8NoBomEncoding.Create;
  {$ELSE}
  Result := TUTF8Encoding.Create(False);
  {$ENDIF}
end;

function JsonValueAsString(const AValue: TValue): string;
begin
  {$IFDEF FPC}
  case AValue.Kind of
    tkWChar: Result := WideChar(AValue.AsOrdinal);
    tkChar: Result := string(AnsiChar(AValue.AsOrdinal));
    tkSString, tkAString, tkWString, tkUString: Result := AValue.AsUnicodeString;
  else
    Result := AValue.AsString;
  end;
  {$ELSE}
  Result := AValue.AsString;
  {$ENDIF}
end;

function JsonPropertyGetValue(AProperty: TRttiProperty; AInstance: Pointer): TValue;
{$IFDEF FPC}
var
  Info: PPropInfo;
  Method: TMethod;
  InputValue: Currency;
  Wide: WideString;
{$ENDIF}
begin
  {$IFDEF FPC}
  if (AProperty.Handle <> nil) and (AProperty.PropertyType <> nil) and
     (AProperty.PropertyType.Handle^.Kind = tkWString) then
  begin
    Wide := GetWideStrProp(TObject(AInstance), PPropInfo(AProperty.Handle));
    TValue.Make(@Wide, AProperty.PropertyType.Handle, Result);
    Exit;
  end;
  if IsCurrencyProperty(AProperty) then
  begin
    Info := PPropInfo(AProperty.Handle);
    case Info^.PropProcs and 3 of
      ptField:
        InputValue := PCurrency(PByte(AInstance) + PtrUInt(Info^.GetProc))^;
      ptStatic, ptVirtual:
        begin
          if (Info^.PropProcs and 3) = ptStatic then
            Method.Code := Info^.GetProc
          else
            Method.Code := PCodePointer(PByte(TObject(AInstance).ClassType) + PtrUInt(Info^.GetProc))^;
          Method.Data := AInstance;
          if ((Info^.PropProcs shr 6) and 1) = 0 then
            InputValue := TCurrencyGetter(Method)()
          else
            InputValue := TIndexedCurrencyGetter(Method)(Info^.Index);
        end;
    else
      Exit(AProperty.GetValue(AInstance));
    end;
    TValue.Make(@InputValue, AProperty.PropertyType.Handle, Result);
    Exit;
  end;
  {$ENDIF}
  Result := AProperty.GetValue(AInstance);
end;

procedure JsonPropertySetValue(AProperty: TRttiProperty; AInstance: Pointer; const AValue: TValue);
{$IFDEF FPC}
var
  Info: PPropInfo;
  Method: TMethod;
  InputValue: Currency;
{$ENDIF}
begin
  {$IFDEF FPC}
  if IsCurrencyProperty(AProperty) then
  begin
    Info := PPropInfo(AProperty.Handle);
    InputValue := AValue.AsType<Currency>;
    case (Info^.PropProcs shr 2) and 3 of
      ptField:
        begin
          PCurrency(PByte(AInstance) + PtrUInt(Info^.SetProc))^ := InputValue;
          Exit;
        end;
      ptStatic, ptVirtual:
        begin
          if ((Info^.PropProcs shr 2) and 3) = ptStatic then
            Method.Code := Info^.SetProc
          else
            Method.Code := PCodePointer(PByte(TObject(AInstance).ClassType) + PtrUInt(Info^.SetProc))^;
          Method.Data := AInstance;
          if ((Info^.PropProcs shr 6) and 1) = 0 then
            TCurrencySetter(Method)(InputValue)
          else
            TIndexedCurrencySetter(Method)(Info^.Index, InputValue);
          Exit;
        end;
    end;
  end;
  {$ENDIF}
  AProperty.SetValue(AInstance, AValue);
end;

{$IFDEF FPC}

class operator TLightweightMREW.Initialize(var Target: TLightweightMREW);
begin
  InitCriticalSection(Target.FLock);
end;

class operator TLightweightMREW.Finalize(var Target: TLightweightMREW);
begin
  DoneCriticalSection(Target.FLock);
end;

procedure TLightweightMREW.BeginRead;
begin
  EnterCriticalSection(FLock);
end;

procedure TLightweightMREW.EndRead;
begin
  LeaveCriticalSection(FLock);
end;

procedure TLightweightMREW.BeginWrite;
begin
  EnterCriticalSection(FLock);
end;

procedure TLightweightMREW.EndWrite;
begin
  LeaveCriticalSection(FLock);
end;

initialization
  GlobalUsePublishedOnly := False;

{$ENDIF}

end.
