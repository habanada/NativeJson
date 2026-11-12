{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
program Test2_Json5;

{$I NativeJson.inc}

{$APPTYPE CONSOLE}

uses
  SysUtils,
  Math,
  NativeJson.Compat,
  Demo.Assert in '..\..\examples\Demos\Demo.Assert.pas',
  NativeJson.Main,
  NativeJson.Settings,
  NativeJson.Dom.Value;

type
  TConfig = class
  private
    FName: string;
    FItemCount: Integer;
    FFactor: Double;
    FLimit: UInt64;
    FAmount: Currency;
  public
    property Name: string read FName write FName;
    property ItemCount: Integer read FItemCount write FItemCount;
    property Factor: Double read FFactor write FFactor;
    property Limit: UInt64 read FLimit write FLimit;
    property Amount: Currency read FAmount write FAmount;
  end;

var
  Json5: TJsonSettings;

function Dom5(const Json: string): string;
var
  Dom: TJsonValue;
begin
  Dom := JsonConvert.DeserializeObject(Json, Json5);
  try
    Result := Dom.ToJson;
  finally
    Dom.Free;
  end;
end;

function DomStrict(const Json: string): string;
var
  Dom: TJsonValue;
begin
  Dom := JsonConvert.DeserializeObject(Json);
  try
    Result := Dom.ToJson;
  finally
    Dom.Free;
  end;
end;

procedure Step1_StrictStaysDefault;
var
  Standard: TJsonSettings;
begin
  Section('1. Without the switch everything stays strict');
  Standard := TJsonSettings.Create;
  try
    Check('Json5 is off', False, Standard.Json5);
  finally
    Standard.Free;
  end;
  Check('Comments as before', '{"a":1}', DomStrict('{"a":1 /* x */}'));
  CheckError('Trailing comma', procedure begin DomStrict('[1,2,]'); end);
  CheckError('Single quotes', procedure begin DomStrict('{''a'':1}'); end);
  CheckError('Key without quotes', procedure begin DomStrict('{a:1}'); end);
  CheckError('Hex number', procedure begin DomStrict('[0x10]'); end);
  CheckError('Leading dot', procedure begin DomStrict('[.5]'); end);
  CheckError('Plus sign', procedure begin DomStrict('[+1]'); end);
  CheckError('Infinity', procedure begin DomStrict('[Infinity]'); end);
  CheckError('Escape \x41', procedure begin DomStrict('["\x41"]'); end);
end;

procedure Step2_Syntax;
begin
  Section('2. JSON5 syntax');
  Check('Trailing comma in object', '{"a":1}', Dom5('{"a":1,}'));
  Check('Trailing comma in array', '[1,2]', Dom5('[1,2,]'));
  Check('Single quotes', '{"a":"b\"c"}', Dom5('{''a'':''b"c''}'));
  Check('Key as identifier', '{"a":1,"$b_2":2,"null":3}', Dom5('{a:1,$b_2:2,null:3}'));
  Check('Key with umlaut', '{"'#$00E4'":1}', Dom5('{'#$00E4':1}'));
  Check('Line and block comment', '{"a":1}', Dom5('// x'#10'{/* y */a:1}'));
  Check('Additional whitespace', '{"a":1}', Dom5(#$FEFF'{'#$A0'a'#11':'#12'1'#$2028'}'));
end;

procedure Step3_Numbers;
begin
  Section('3. Numbers become strict JSON');
  Check('Hexadecimal', '[255,-16,10]', Dom5('[0xFF,-0x10,0XA]'));
  Check('Leading and trailing dot', '[0.5,5,-0.25]', Dom5('[.5,5.,-.25]'));
  Check('Plus sign', '[1,1.5]', Dom5('[+1,+1.5]'));
  Check('Exponent after dot', '[5e2]', Dom5('[5.e2]'));
  CheckError('Hex number too large', procedure begin Dom5('[0x10000000000000000]'); end);
  CheckError('Leading zero', procedure begin Dom5('[01]'); end);
  CheckError('Only a dot', procedure begin Dom5('[.]'); end);
end;

procedure Step4_Strings;
begin
  Section('4. Strings');
  Check('Line continuation', '{"a":"xy"}', Dom5('{a:"x\'#13#10'y"}'));
  Check('Escapes \x \v \0 \''', '["A\u000b\u0000''"]', Dom5('["\x41\v\0\''"]'));
  Check('Unknown escape stands for itself', '["q"]', Dom5('["\q"]'));
  Check('Raw tab allowed', '["a\tb"]', Dom5('["a'#9'b"]'));
  CheckError('Raw line break', procedure begin Dom5('["a'#10'b"]'); end);
  CheckError('Escape \1', procedure begin Dom5('["\1"]'); end);
end;

procedure Step5_WhatIsStillWrong;
begin
  Section('5. Invalid even with Json5');
  CheckError('Value as identifier', procedure begin Dom5('{"a":foo}'); end);
  CheckError('Double comma', procedure begin Dom5('[1,,]'); end);
  CheckError('Only a comma', procedure begin Dom5('[,]'); end);
  CheckError('Number as key', procedure begin Dom5('{1:2}'); end);
end;

procedure Step6_InClasses;
var
  K: TConfig;
begin
  Section('6. Deserializing into a class');
  K := JsonConvert.DeserializeObject<TConfig>(
    '{ Name: ''Warehouse'', ItemCount: 0x10, Factor: .5, Limit: 0xFFFFFFFFFFFFFFFF, Amount: +1234.5678, /* End */ }', Json5);
  try
    Check('Name', 'Warehouse', K.Name);
    Check('ItemCount', 16, K.ItemCount);
    Check('Factor', 0.5, K.Factor);
    CheckTrue('Limit = High(UInt64)', K.Limit = High(UInt64), UIntToStr(K.Limit));
    CheckTrue('Amount exact', K.Amount = 1234.5678, CurrToStr(K.Amount));
    Check('Back as strict JSON', '{"Name":"Warehouse","ItemCount":16,"Factor":0.5,"Limit":18446744073709551615,"Amount":1234.5678}',
      JsonConvert.SerializeObject(K));
  finally
    K.Free;
  end;
  CheckError('Rejected without the switch', procedure begin JsonConvert.DeserializeObject<TConfig>('{Name:''x''}').Free; end);
end;

procedure Step7_InfinityAndNaN;
var
  K: TConfig;
begin
  Section('7. Infinity and NaN');
  K := JsonConvert.DeserializeObject<TConfig>('{Factor: -Infinity}', Json5);
  try
    CheckTrue('-Infinity read', IsInfinite(K.Factor) and (K.Factor < 0));
    CheckError('Writing refused', procedure begin JsonConvert.SerializeObject(K); end);
  finally
    K.Free;
  end;
  K := JsonConvert.DeserializeObject<TConfig>('{Factor: NaN}', Json5);
  try
    CheckTrue('NaN read', IsNan(K.Factor));
  finally
    K.Free;
  end;
  CheckError('DOM does not write Infinity', procedure begin Dom5('[Infinity]'); end);
  CheckError('Infinity not into an integer', procedure begin JsonConvert.DeserializeObject<TConfig>('{ItemCount: Infinity}', Json5).Free; end);
end;

begin
  Json5 := TJsonSettings.Create;
  try
    try
      Json5.Json5 := True;
      Title('TEST PACKAGE 2 - JSON5 AS A SWITCH');

      Step1_StrictStaysDefault;
      Step2_Syntax;
      Step3_Numbers;
      Step4_Strings;
      Step5_WhatIsStillWrong;
      Step6_InClasses;
      Step7_InfinityAndNaN;

      ExitCode := Summary;
    except
      on E: Exception do
      begin
        Writeln('ABORTED: ', E.ClassName, ': ', E.Message);
        ExitCode := 2;
      end;
    end;
  finally
    Json5.Free;
  end;
  if ParamCount = 0 then
  begin
    Writeln;
    Writeln('Press Enter ...');
    Readln;
  end;
end.
