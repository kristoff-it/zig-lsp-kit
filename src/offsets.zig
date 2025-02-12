const std = @import("std");
const types = @import("lsp").types;

pub const Encoding = enum {
    /// Character offsets count UTF-8 code units (e.g. bytes).
    @"utf-8",
    /// Character offsets count UTF-16 code units.
    ///
    /// This is the default and must always be supported
    /// by servers
    @"utf-16",
    /// Character offsets count UTF-32 code units.
    ///
    /// Implementation note: these are the same as Unicode codepoints,
    /// so this `PositionEncodingKind` may also be used for an
    /// encoding-agnostic representation of character offsets.
    @"utf-32",
};

pub const Loc = std.zig.Token.Loc;

pub fn indexToPosition(text: []const u8, index: usize, encoding: Encoding) types.Position {
    const last_line_start = if (std.mem.lastIndexOfScalar(u8, text[0..index], '\n')) |line| line + 1 else 0;
    const line_count = std.mem.count(u8, text[0..last_line_start], "\n");

    return .{
        .line = @intCast(line_count),
        .character = @intCast(countCodeUnits(text[last_line_start..index], encoding)),
    };
}

pub fn maybePositionToIndex(text: []const u8, position: types.Position, encoding: Encoding) ?usize {
    var line: u32 = 0;
    var line_start_index: usize = 0;
    for (text, 0..) |c, i| {
        if (line == position.line) break;
        if (c == '\n') {
            line += 1;
            line_start_index = i + 1;
        }
    }

    if (line != position.line) return null;

    const line_text = std.mem.sliceTo(text[line_start_index..], '\n');
    const line_byte_length = getNCodeUnitByteCount(line_text, position.character, encoding);

    return line_start_index + line_byte_length;
}

pub fn positionToIndex(text: []const u8, position: types.Position, encoding: Encoding) usize {
    var line: u32 = 0;
    var line_start_index: usize = 0;
    for (text, 0..) |c, i| {
        if (line == position.line) break;
        if (c == '\n') {
            line += 1;
            line_start_index = i + 1;
        }
    }
    std.debug.assert(line == position.line);

    const line_text = std.mem.sliceTo(text[line_start_index..], '\n');
    const line_byte_length = getNCodeUnitByteCount(line_text, position.character, encoding);

    return line_start_index + line_byte_length;
}

pub fn locLength(text: []const u8, loc: Loc, encoding: Encoding) usize {
    return countCodeUnits(text[loc.start..loc.end], encoding);
}

pub fn rangeLength(text: []const u8, range: types.Range, encoding: Encoding) usize {
    const loc = rangeToLoc(text, range, encoding);
    return locLength(text, loc, encoding);
}

pub fn locToSlice(text: []const u8, loc: Loc) []const u8 {
    return text[loc.start..loc.end];
}

pub fn locToRange(text: []const u8, loc: Loc, encoding: Encoding) types.Range {
    std.debug.assert(loc.start <= loc.end and loc.end <= text.len);
    const start = indexToPosition(text, loc.start, encoding);
    return .{
        .start = start,
        .end = advancePosition(text, start, loc.start, loc.end, encoding),
    };
}

pub fn rangeToSlice(text: []const u8, range: types.Range, encoding: Encoding) []const u8 {
    return locToSlice(text, rangeToLoc(text, range, encoding));
}

pub fn rangeToLoc(text: []const u8, range: types.Range, encoding: Encoding) Loc {
    return .{
        .start = positionToIndex(text, range.start, encoding),
        .end = positionToIndex(text, range.end, encoding),
    };
}

pub fn lineLocAtIndex(text: []const u8, index: usize) Loc {
    return .{
        .start = if (std.mem.lastIndexOfScalar(u8, text[0..index], '\n')) |idx| idx + 1 else 0,
        .end = std.mem.indexOfScalarPos(u8, text, index, '\n') orelse text.len,
    };
}

pub fn lineSliceAtIndex(text: []const u8, index: usize) []const u8 {
    return locToSlice(text, lineLocAtIndex(text, index));
}

pub fn lineLocAtPosition(text: []const u8, position: types.Position, encoding: Encoding) Loc {
    return lineLocAtIndex(text, positionToIndex(text, position, encoding));
}

pub fn lineSliceAtPosition(text: []const u8, position: types.Position, encoding: Encoding) []const u8 {
    return locToSlice(text, lineLocAtPosition(text, position, encoding));
}

pub fn lineLocUntilIndex(text: []const u8, index: usize) Loc {
    return .{
        .start = if (std.mem.lastIndexOfScalar(u8, text[0..index], '\n')) |idx| idx + 1 else 0,
        .end = index,
    };
}

pub fn lineSliceUntilIndex(text: []const u8, index: usize) []const u8 {
    return locToSlice(text, lineLocUntilIndex(text, index));
}

pub fn lineLocUntilPosition(text: []const u8, position: types.Position, encoding: Encoding) Loc {
    return lineLocUntilIndex(text, positionToIndex(text, position, encoding));
}

pub fn lineSliceUntilPosition(text: []const u8, position: types.Position, encoding: Encoding) []const u8 {
    return locToSlice(text, lineLocUntilPosition(text, position, encoding));
}

pub fn convertPositionEncoding(text: []const u8, position: types.Position, from_encoding: Encoding, to_encoding: Encoding) types.Position {
    if (from_encoding == to_encoding) return position;

    const line_loc = lineLocUntilPosition(text, position, from_encoding);

    return .{
        .line = position.line,
        .character = @intCast(locLength(text, line_loc, to_encoding)),
    };
}

pub fn convertRangeEncoding(text: []const u8, range: types.Range, from_encoding: Encoding, to_encoding: Encoding) types.Range {
    if (from_encoding == to_encoding) return range;
    return .{
        .start = convertPositionEncoding(text, range.start, from_encoding, to_encoding),
        .end = convertPositionEncoding(text, range.end, from_encoding, to_encoding),
    };
}

/// returns true if a and b intersect
pub fn locIntersect(a: Loc, b: Loc) bool {
    std.debug.assert(a.start <= a.end and b.start <= b.end);
    return a.start < b.end and a.end > b.start;
}

/// returns true if a is inside b
pub fn locInside(inner: Loc, outer: Loc) bool {
    std.debug.assert(inner.start <= inner.end and outer.start <= outer.end);
    return outer.start <= inner.start and inner.end <= outer.end;
}

/// returns the union of a and b
pub fn locMerge(a: Loc, b: Loc) Loc {
    std.debug.assert(a.start <= a.end and b.start <= b.end);
    return .{
        .start = @min(a.start, b.start),
        .end = @max(a.end, b.end),
    };
}

// Helper functions

/// advance `position` which starts at `from_index` to `to_index` accounting for line breaks
pub fn advancePosition(text: []const u8, position: types.Position, from_index: usize, to_index: usize, encoding: Encoding) types.Position {
    var line = position.line;

    for (text[from_index..to_index]) |c| {
        if (c == '\n') {
            line += 1;
        }
    }

    const line_loc = lineLocUntilIndex(text, to_index);

    return .{
        .line = line,
        .character = @intCast(locLength(text, line_loc, encoding)),
    };
}

/// returns the number of code units in `text`
pub fn countCodeUnits(text: []const u8, encoding: Encoding) usize {
    switch (encoding) {
        .@"utf-8" => return text.len,
        .@"utf-16" => {
            var iter: std.unicode.Utf8Iterator = .{ .bytes = text, .i = 0 };

            var utf16_len: usize = 0;
            while (iter.nextCodepoint()) |codepoint| {
                if (codepoint < 0x10000) {
                    utf16_len += 1;
                } else {
                    utf16_len += 2;
                }
            }
            return utf16_len;
        },
        .@"utf-32" => return std.unicode.utf8CountCodepoints(text) catch unreachable,
    }
}

/// returns the number of (utf-8 code units / bytes) that represent `n` code units in `text`
/// if `text` has less than `n` code units then the number of code units in
/// `text` are returned, i.e. the result is being clamped.
pub fn getNCodeUnitByteCount(text: []const u8, n: usize, encoding: Encoding) usize {
    switch (encoding) {
        .@"utf-8" => return @min(text.len, n),
        .@"utf-16" => {
            if (n == 0) return 0;
            var iter: std.unicode.Utf8Iterator = .{ .bytes = text, .i = 0 };

            var utf16_len: usize = 0;
            while (iter.nextCodepoint()) |codepoint| {
                if (codepoint < 0x10000) {
                    utf16_len += 1;
                } else {
                    utf16_len += 2;
                }
                if (utf16_len >= n) break;
            }
            return iter.i;
        },
        .@"utf-32" => {
            var i: usize = 0;
            var count: usize = 0;
            while (count != n) : (count += 1) {
                if (i >= text.len) break;
                i += std.unicode.utf8ByteSequenceLength(text[i]) catch unreachable;
            }
            return i;
        },
    }
}

pub fn rangeLessThan(a: types.Range, b: types.Range) bool {
    return positionLessThan(a.start, b.start) or positionLessThan(a.end, b.end);
}

pub fn positionLessThan(a: types.Position, b: types.Position) bool {
    if (a.line < b.line) {
        return true;
    }
    if (a.line > b.line) {
        return false;
    }

    if (a.character < b.character) {
        return true;
    }

    return false;
}
