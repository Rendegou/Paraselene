/// Identical BMP source strings to the isolated CodeMirror baseline generator.
String fillFixture(String unit, int length) =>
    (unit * ((length / unit.length).ceil())).substring(0, length);

/// The returned strings never enter a production database or model request.
String editorFixture(String name) => switch (name) {
  '10k' => fillFixture('月光落在窗边，远处传来缓慢的钟声。故事中的人物转身望向河岸。\n', 10000),
  '200k' => fillFixture('月光落在窗边，远处传来缓慢的钟声。故事中的人物转身望向河岸。\n', 200000),
  'single-line' => fillFixture('月光落在窗边，远处传来钟声。', 200000),
  'empty' => '',
  _ => 'M3 合成输入法验收\r\n中文 · English · العربية · 👩‍💻 · e\u0301\r\n',
};
