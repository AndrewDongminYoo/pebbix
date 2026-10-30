// 🎯 Dart imports:
import 'dart:typed_data';

/// Reads the character-to-glyph map out of a TrueType file.
///
/// The point is to answer "does this font actually carry the characters the
/// app renders" from the file itself. Loading the font and measuring text
/// cannot answer it: a missing glyph still lays out, either as tofu or
/// through a fallback the test host happens to have, and both produce a
/// width an assertion would accept.
///
/// Only the two `cmap` subtable formats a modern font ships are handled —
/// format 4 for the BMP and format 12 for the full range. Hangul syllables
/// sit at U+AC00–U+D7A3, inside the BMP, so format 4 alone would do; format
/// 12 is here because a font that ships only it would otherwise read as
/// covering nothing.
Set<int> supportedCodePoints(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  final numTables = data.getUint16(4);
  var cmapOffset = -1;
  for (var i = 0; i < numTables; i++) {
    final record = 12 + i * 16;
    final tag = String.fromCharCodes(bytes.sublist(record, record + 4));
    if (tag == 'cmap') {
      cmapOffset = data.getUint32(record + 8);
      break;
    }
  }
  if (cmapOffset < 0) return const {};

  // Prefer a format 12 subtable when one is present: it is a superset of
  // whatever format 4 in the same font encodes.
  final subtables = data.getUint16(cmapOffset + 2);
  var best = -1;
  var bestFormat = -1;
  for (var i = 0; i < subtables; i++) {
    final record = cmapOffset + 4 + i * 8;
    final offset = cmapOffset + data.getUint32(record + 4);
    final format = data.getUint16(offset);
    if ((format == 12 && bestFormat != 12) || (format == 4 && bestFormat < 0)) {
      best = offset;
      bestFormat = format;
    }
  }
  return switch (bestFormat) {
    12 => _readFormat12(data, best),
    4 => _readFormat4(data, best),
    _ => const {},
  };
}

Set<int> _readFormat4(ByteData data, int offset) {
  final segCount = data.getUint16(offset + 6) ~/ 2;
  final endCodes = offset + 14;
  final startCodes = endCodes + segCount * 2 + 2;
  final idDeltas = startCodes + segCount * 2;
  final idRangeOffsets = idDeltas + segCount * 2;

  final covered = <int>{};
  for (var seg = 0; seg < segCount; seg++) {
    final end = data.getUint16(endCodes + seg * 2);
    final start = data.getUint16(startCodes + seg * 2);
    if (start > end) continue;
    final rangeOffset = data.getUint16(idRangeOffsets + seg * 2);
    final delta = data.getInt16(idDeltas + seg * 2);
    for (var code = start; code <= end && code != 0xFFFF; code++) {
      // Both branches end at the same test — glyph 0 is `.notdef`, which is
      // exactly the tofu this parser exists to detect — but they reach it
      // differently. With no range offset the delta alone maps the code;
      // with one, the array entry is consulted first and is only shifted by
      // the delta when it is itself nonzero.
      int glyph;
      if (rangeOffset == 0) {
        glyph = (code + delta) & 0xFFFF;
      } else {
        final glyphIndex = idRangeOffsets + seg * 2 + rangeOffset + (code - start) * 2;
        if (glyphIndex + 1 >= data.lengthInBytes) continue;
        final entry = data.getUint16(glyphIndex);
        glyph = entry == 0 ? 0 : (entry + delta) & 0xFFFF;
      }
      if (glyph != 0) covered.add(code);
    }
  }
  return covered;
}

Set<int> _readFormat12(ByteData data, int offset) {
  final groups = data.getUint32(offset + 12);
  final covered = <int>{};
  for (var i = 0; i < groups; i++) {
    final group = offset + 16 + i * 12;
    final start = data.getUint32(group);
    final end = data.getUint32(group + 4);
    final startGlyph = data.getUint32(group + 8);
    for (var code = start; code <= end; code++) {
      // Glyph ids run sequentially from startGlyphID, so a group beginning
      // at 0 leaves only its first code point unmapped — the rest land on
      // 1, 2 and up. Discarding the whole group would report those as
      // missing.
      if (startGlyph + (code - start) != 0) covered.add(code);
    }
  }
  return covered;
}
