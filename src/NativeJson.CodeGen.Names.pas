{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit NativeJson.CodeGen.Names;

interface

{$I NativeJson.inc}

uses
  {$IFDEF FPC}
  SysUtils,
  Character,
  Generics.Collections;
  {$ELSE}
  System.SysUtils,
  System.Character,
  System.Generics.Collections;
  {$ENDIF}

type
  TJsonCodeGenNameAllocator = class
  private
    FUsedTypes: TDictionary<string, Boolean>;
    class function IsReservedWord(const Value: string): Boolean; static;
    class function IsReservedMember(const Value: string): Boolean; static;
    class function NormalizeIdentifier(const Value: string; PascalCase: Boolean): string; static;
  public
    constructor Create;
    destructor Destroy; override;
    function AllocateTypeName(const Hint, Prefix: string): string;
    function AllocateMemberName(const JsonName: string; Used: TDictionary<string, Boolean>; ForClass: Boolean): string;
    class function DelphiIdentifier(const Value: string; PascalCase: Boolean = True): string; static;
    class function DelphiString(const Value: string): string; static;
    class function JsonPointerToken(const Value: string): string; static;
  end;

implementation

const
  ReservedWords: array[0..118] of string = (
    'absolute','abstract','and','array','as','asm','assembler','automated','begin','case','cdecl','class','const','constructor','contains','default','deprecated','destructor','dispid','dispinterface','div','do','downto','dynamic','else','end','except','experimental','export','exports','external','far','file','final','finalization','finally','for','forward','function','generic','goto','helper','if','implementation','implements','in','index','inherited','initialization','inline','interface','is','label','library','local','message','mod','name','near','nil','nodefault','not','object','of','on','operator','or','out','overload','override','package','packed','pascal','platform','private','procedure','program','property','protected','public','published','raise','read','readonly','record','reference','register','reintroduce','repeat','requires','resident','resourcestring','safecall','sealed','set','shl','shr','static','stdcall','stored','strict','string','then','threadvar','to','try','type','unit','unsafe','until','uses','var','varargs','virtual','while','with','write','writeonly','xor'
  );

  ReservedMembers: array[0..20] of string = (
    'afterconstruction','beforedestruction','classname','classinfo','classparent','classtype','cleanupinstance','create','defaultHandler','destroy','dispatch','disposeof','equals','free','freeinstance','gethashcode','inheritsfrom','initinstance','instancesize','newinstance','tostring'
  );

constructor TJsonCodeGenNameAllocator.Create;
begin
  inherited Create;
  FUsedTypes := TDictionary<string, Boolean>.Create;
end;

destructor TJsonCodeGenNameAllocator.Destroy;
begin
  FUsedTypes.Free;
  inherited;
end;

class function TJsonCodeGenNameAllocator.IsReservedWord(const Value: string): Boolean;
var
  S: string;
begin
  for S in ReservedWords do if SameText(S, Value) then Exit(True);
  Result := False;
end;

class function TJsonCodeGenNameAllocator.IsReservedMember(const Value: string): Boolean;
var
  S: string;
begin
  for S in ReservedMembers do if SameText(S, Value) then Exit(True);
  Result := False;
end;

class function TJsonCodeGenNameAllocator.NormalizeIdentifier(const Value: string; PascalCase: Boolean): string;
var
  C: Char;
  UpperNext, LowerRest: Boolean;
begin
  Result := '';
  UpperNext := PascalCase;
  LowerRest := PascalCase and (Pos('_', Value) > 0) and (AnsiUpperCase(Value) = Value);
  for C in Value do
  begin
    if PascalCase and (C = '_') then UpperNext := True
    else if C.IsLetterOrDigit or (C = '_') then
    begin
      if UpperNext and C.IsLetter then Result := Result + TCharacter.ToUpper(C)
      else if LowerRest and C.IsLetter then Result := Result + TCharacter.ToLower(C)
      else Result := Result + C;
      UpperNext := False;
    end
    else if PascalCase then UpperNext := True
    else if (Result <> '') and (Result[Length(Result)] <> '_') then Result := Result + '_';
  end;
  while (Result <> '') and (Result[Length(Result)] = '_') do Delete(Result, Length(Result), 1);
  if Result = '' then Result := '_';
  if Result[1].IsDigit then Result := '_' + Result;
end;

class function TJsonCodeGenNameAllocator.DelphiIdentifier(const Value: string; PascalCase: Boolean): string;
begin
  Result := NormalizeIdentifier(Value, PascalCase);
  if IsReservedWord(Result) then Result := '&' + Result;
end;

function HasTypePrefix(const Name, Prefix: string): Boolean;
begin
  Result := (Length(Name) > Length(Prefix)) and (Copy(Name, 1, Length(Prefix)) = Prefix) and
    not TCharacter.IsLower(Name[Length(Prefix) + 1]);
end;

function TJsonCodeGenNameAllocator.AllocateTypeName(const Hint, Prefix: string): string;
var
  Base: string;
  I: Integer;
begin
  Base := NormalizeIdentifier(Hint, True);
  if (Prefix <> '') and not HasTypePrefix(Base, Prefix) then Base := Prefix + Base;
  if Base = Prefix then Base := Prefix + 'Value';
  if IsReservedWord(Base) then Base := Base + 'Type';
  Result := Base;
  I := 2;
  while FUsedTypes.ContainsKey(UpperCase(Result)) do
  begin
    Result := Base + IntToStr(I);
    Inc(I);
  end;
  FUsedTypes.Add(UpperCase(Result), True);
end;

function TJsonCodeGenNameAllocator.AllocateMemberName(const JsonName: string; Used: TDictionary<string, Boolean>; ForClass: Boolean): string;
var
  Base, Plain: string;
  I: Integer;
begin
  Plain := NormalizeIdentifier(JsonName, True);
  if ForClass and IsReservedMember(Plain) then Plain := Plain + 'Value';
  Base := Plain;
  I := 2;
  while Used.ContainsKey(UpperCase(Plain)) do
  begin
    Plain := Base + IntToStr(I);
    Inc(I);
  end;
  Used.Add(UpperCase(Plain), True);
  if IsReservedWord(Plain) then Result := '&' + Plain else Result := Plain;
end;

class function TJsonCodeGenNameAllocator.DelphiString(const Value: string): string;
var
  I, Start: Integer;
  Part: string;
  procedure AddText(const S: string);
  begin
    if S = '' then Exit;
    if Result <> '' then Result := Result + ' + ';
    Result := Result + QuotedStr(S);
  end;
  procedure AddCode(Code: Integer);
  begin
    if Result <> '' then Result := Result + ' + ';
    Result := Result + '#' + IntToStr(Code);
  end;
begin
  Result := '';
  Start := 1;
  I := 1;
  while I <= Length(Value) do
  begin
    if Ord(Value[I]) < 32 then
    begin
      Part := Copy(Value, Start, I - Start);
      AddText(Part);
      AddCode(Ord(Value[I]));
      Inc(I);
      Start := I;
    end
    else Inc(I);
  end;
  AddText(Copy(Value, Start, MaxInt));
  if Result = '' then Result := '''''';
end;

class function TJsonCodeGenNameAllocator.JsonPointerToken(const Value: string): string;
begin
  Result := StringReplace(StringReplace(Value, '~', '~0', [rfReplaceAll]), '/', '~1', [rfReplaceAll]);
end;

end.
