{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
program NativeJson_Xml;

{$I NativeJson.inc}

{$APPTYPE CONSOLE}

uses
  SysUtils,
  NativeJson.Compat,
  Demo.Assert in '..\examples\Demos\Demo.Assert.pas',
  NativeJson.Dom.Value,
  NativeJson.Dom.Io,
  NativeJson.Xml;

function ErrorText(const Xml: string): string;
begin
  Result := '';
  try
    XmlToJson(Xml);
  except
    on E: EJsonXmlError do Result := E.Message;
  end;
end;

function Nested(Depth: Integer): string;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Depth do Result := Result + '<a>';
  for I := 1 to Depth do Result := Result + '</a>';
end;

procedure Step1_XmlToJson;
var
  Options: TJsonXmlOptions;
  Dom: TJsonValue;
begin
  Section('1. XML to JSON');
  Check('Elements become properties',
    '{"person":{"name":"Anna","age":"42"}}',
    XmlToJson('<person><name>Anna</name><age>42</age></person>'));
  Check('Attributes and text',
    '{"price":{"@currency":"EUR","#text":"12.50"}}',
    XmlToJson('<price currency="EUR">12.50</price>'));
  Check('Repeated elements become an array',
    '{"list":{"item":["a","b"]}}',
    XmlToJson('<list><item>a</item><item>b</item></list>'));
  Check('Empty elements become null',
    '{"a":{"b":null,"c":null}}',
    XmlToJson('<a><b/><c></c></a>'));
  Check('Mixed content',
    '{"p":{"#text":["Hello ","!"],"b":"World"}}',
    XmlToJson('<p>Hello <b>World</b>!</p>'));
  Check('Whitespace between elements is ignored',
    '{"r":{"a":"1","b":"2"}}',
    XmlToJson('<r>' + sLineBreak + '  <a>1</a>' + sLineBreak + '  <b>2</b>' + sLineBreak + '</r>'));
  Check('Prolog, comments, processing instructions and DOCTYPE are skipped',
    '{"note":"x"}',
    XmlToJson('<?xml version="1.0" encoding="UTF-8"?>' + sLineBreak + '<!-- c --><!DOCTYPE note>' +
      '<note><?pi data?>x<!-- inner --></note><!-- end -->'));
  Check('Namespace prefixes are kept',
    '{"a:root":{"@xmlns:a":"urn:x","a:v":"1"}}',
    XmlToJson('<a:root xmlns:a="urn:x"><a:v>1</a:v></a:root>'));
  Check('Encoded names are decoded',
    '{"first name":"A"}',
    XmlToJson('<first_x0020_name>A</first_x0020_name>'));

  Dom := XmlToDom('<t>a &amp; b &lt;c&gt; &quot;&apos; &#228; &#x1F600;</t>');
  try
    Check('Entities and character references', 'a & b <c> "'' ' + #$E4 + ' ' + #$D83D#$DE00, Dom.Values['t'].AsString);
  finally
    Dom.Free;
  end;
  Dom := XmlToDom('<c><![CDATA[<x> & ]]y]]></c>');
  try
    Check('CDATA section', '<x> & ]]y', Dom.Values['c'].AsString);
  finally
    Dom.Free;
  end;
  Dom := XmlToDom('<t v="a' + #9 + 'b' + #13#10 + 'c">x' + #13#10 + 'y' + #13 + 'z</t>');
  try
    Check('Attribute value normalization', 'a b c', Dom.Values['t'].Values['@v'].AsString);
    Check('Line ends in text become LF', 'x' + #10 + 'y' + #10 + 'z', Dom.Values['t'].Values['#text'].AsString);
  finally
    Dom.Free;
  end;
  Dom := XmlToDom(#$FEFF + '<t> </t>');
  try
    Check('BOM is skipped, whitespace-only leaf text is kept', ' ', Dom.Values['t'].AsString);
  finally
    Dom.Free;
  end;

  Options := TJsonXmlOptions.Create;
  try
    Options.ForceArrays.Add('item');
    Check('ForceArrays by element name',
      '{"list":{"item":["a"]}}',
      XmlToJson('<list><item>a</item></list>', Options));
    Options.ForceArrays.Clear;
    Options.ForceArrays.Add('list/item');
    Check('ForceArrays by path',
      '{"list":{"item":["a"],"other":{"item":"b"}}}',
      XmlToJson('<list><item>a</item><other><item>b</item></other></list>', Options));
  finally
    Options.Free;
  end;

  Options := TJsonXmlOptions.Create;
  try
    Options.InferTypes := True;
    Check('InferTypes',
      '{"r":{"@id":7,"n":42,"f":1.5e3,"b":true,"s":"007","t":"True","big":18446744073709551615}}',
      XmlToJson('<r id="7"><n>42</n><f>1.5e3</f><b>true</b><s>007</s><t>True</t><big>18446744073709551615</big></r>', Options));
    Options.AttributePrefix := '-';
    Options.TextKey := '$';
    Check('Custom attribute prefix and text key',
      '{"p":{"-c":"EUR","$":1}}',
      XmlToJson('<p c="EUR">1</p>', Options));
  finally
    Options.Free;
  end;
end;

procedure Step2_XmlErrors;
var
  Options: TJsonXmlOptions;
begin
  Section('2. Malformed and unsafe XML');
  CheckError('Empty input', procedure begin XmlToJson(''); end);
  CheckError('Text without element', procedure begin XmlToJson('hello'); end);
  CheckError('End tag does not match', procedure begin XmlToJson('<a><b></a></b>'); end);
  CheckError('Unterminated element', procedure begin XmlToJson('<a><b>x</b>'); end);
  CheckError('Two document elements', procedure begin XmlToJson('<a/><b/>'); end);
  CheckError('Duplicate attribute', procedure begin XmlToJson('<a x="1" x="2"/>'); end);
  CheckError('Unquoted attribute', procedure begin XmlToJson('<a x=1/>'); end);
  CheckError('"<" in attribute value', procedure begin XmlToJson('<a x="<"/>'); end);
  CheckError('Unknown entity', procedure begin XmlToJson('<a>&nbsp;</a>'); end);
  CheckError('Character reference to U+0000', procedure begin XmlToJson('<a>&#0;</a>'); end);
  CheckError('Entity from an internal DTD subset is not expanded',
    procedure begin XmlToJson('<!DOCTYPE x [<!ENTITY e "boom">]><x>&e;</x>'); end);
  CheckError('External entity is not resolved',
    procedure begin XmlToJson('<!DOCTYPE x [<!ENTITY e SYSTEM "file:///c:/windows/win.ini">]><x>&e;</x>'); end);
  CheckError('Nesting deeper than MaxDepth', procedure begin XmlToJson(Nested(300)); end);
  CheckTrue('Nesting at MaxDepth is accepted', XmlToJson(Nested(256)) <> '');
  CheckContains('Error position', 'line 2, column 4', ErrorText('<a>' + #10 + '<b></c></a>'));

  Options := TJsonXmlOptions.Create;
  try
    Options.MaxDepth := 3;
    Check('Custom MaxDepth accepts 3 levels', '{"a":{"a":{"a":null}}}', XmlToJson(Nested(3), Options));
    CheckError('Custom MaxDepth rejects 4 levels', procedure begin XmlToJson(Nested(4), Options); end);
  finally
    Options.Free;
  end;
end;

procedure Step3_JsonToXml;
var
  Options: TJsonXmlOptions;
begin
  Section('3. JSON to XML');
  Check('Properties become elements',
    '<person><name>Anna</name><age>42</age></person>',
    JsonToXml('{"person":{"name":"Anna","age":42}}'));
  Check('Attributes and text',
    '<price currency="EUR">12.50</price>',
    JsonToXml('{"price":{"@currency":"EUR","#text":"12.50"}}'));
  Check('Arrays become repeated elements',
    '<list><item>a</item><item>b</item></list>',
    JsonToXml('{"list":{"item":["a","b"]}}'));
  Check('null and empty object become empty elements',
    '<a><b/><c/></a>',
    JsonToXml('{"a":{"b":null,"c":{}}}'));
  Check('Numbers keep their notation, booleans as text',
    '<n><a>1.50e2</a><b>18446744073709551615</b><c>true</c></n>',
    JsonToXml('{"n":{"a":1.50e2,"b":18446744073709551615,"c":true}}'));
  Check('Text escaping',
    '<t>a&lt;b &amp; "c" &gt;</t>',
    JsonToXml('{"t":"a<b & \"c\" >"}'));
  Check('Attribute escaping',
    '<t v="&quot;x&quot;&#xA;&#x9;&lt;&amp;"/>',
    JsonToXml('{"t":{"@v":"\"x\"\n\t<&"}}'));
  Check('Carriage return is kept as a reference',
    '<t>a&#xD;b</t>',
    JsonToXml('{"t":"a\rb"}'));
  Check('Invalid names are encoded',
    '<r><first_x0020_name>A</first_x0020_name><_x0031_x>B</_x0031_x><a_x005F_x0041_b>C</a_x005F_x0041_b></r>',
    JsonToXml('{"r":{"first name":"A","1x":"B","a_x0041_b":"C"}}'));
  Check('null attribute is left out',
    '<t a="1"/>',
    JsonToXml('{"t":{"@a":1,"@b":null}}'));
  Check('Unicode passes through',
    '<t>' + #$E4 + #$D83D#$DE00 + '</t>',
    JsonToXml('{"t":"\u00e4\ud83d\ude00"}'));

  Options := TJsonXmlOptions.Create;
  try
    Options.RootName := 'root';
    Check('RootName wraps the value',
      '<root><a>1</a><b>2</b></root>',
      JsonToXml('{"a":1,"b":2}', Options));
    Check('RootName with a scalar',
      '<root>x</root>',
      JsonToXml('"x"', Options));
    Options.RootName := '';
    Options.WriteDeclaration := True;
    Options.Indent := True;
    Check('Declaration and indentation',
      '<?xml version="1.0" encoding="UTF-8"?>' + sLineBreak +
      '<r>' + sLineBreak +
      '  <a>1</a>' + sLineBreak +
      '  <b x="y">' + sLineBreak +
      '    <c>2</c>' + sLineBreak +
      '    <c>3</c>' + sLineBreak +
      '  </b>' + sLineBreak +
      '  <m>t<i>u</i></m>' + sLineBreak +
      '</r>',
      JsonToXml('{"r":{"a":"1","b":{"@x":"y","c":[2,3]},"m":{"#text":"t","i":"u"}}}', Options));
  finally
    Options.Free;
  end;

  CheckError('Several properties without RootName', procedure begin JsonToXml('{"a":1,"b":2}'); end);
  CheckError('Array as document element', procedure begin JsonToXml('{"a":[1,2]}'); end);
  CheckError('Array inside an array', procedure begin JsonToXml('{"r":{"a":[[1]]}}'); end);
  CheckError('Object as attribute', procedure begin JsonToXml('{"r":{"@a":{}}}'); end);
  CheckError('Empty key', procedure begin JsonToXml('{"r":{"":1}}'); end);
  CheckError('Control character', procedure begin JsonToXml('{"r":"\u0001"}'); end);
  CheckError('nil value', procedure begin DomToXml(nil); end);
end;

procedure Step4_RoundTrips;
const
  Catalog = '<catalog><book id="1"><title>A &amp; B</title><price currency="EUR">12.50</price></book>' +
    '<book id="2"><title>C</title><note/></book></catalog>';
  Order = '{"order":{"@id":7,"items":{"item":[{"sku":"A1","qty":2},{"sku":"B2","qty":1.25}]},"paid":true,"note":null}}';
var
  Reader, Writer: TJsonXmlOptions;
begin
  Section('4. Round trips');
  Check('XML -> JSON -> XML', Catalog, JsonToXml(XmlToJson(Catalog)));
  Reader := TJsonXmlOptions.Create;
  Writer := TJsonXmlOptions.Create;
  try
    Reader.InferTypes := True;
    Writer.Indent := True;
    Check('JSON -> XML -> JSON with InferTypes', Order, XmlToJson(JsonToXml(Order), Reader));
    Check('Indented XML reads back the same', Order, XmlToJson(JsonToXml(Order, Writer), Reader));
  finally
    Writer.Free;
    Reader.Free;
  end;
end;

begin
  {$IFNDEF FPC}
  ReportMemoryLeaksOnShutdown := True;
  {$ENDIF}
  try
    Title('NATIVEJSON - XML AND JSON');
    Step1_XmlToJson;
    Step2_XmlErrors;
    Step3_JsonToXml;
    Step4_RoundTrips;
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
