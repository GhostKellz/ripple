const std = @import("std");

pub const TemplatePlan = struct {
    static_parts: []const []const u8,
    placeholders: []const []const u8,

    pub fn placeholderCount(self: @This()) usize {
        return self.placeholders.len;
    }
};

pub const TemplateError = error{
    MismatchedValues,
} || std.mem.Allocator.Error;

fn findClosing(comptime template: []const u8, start: usize) usize {
    var i = start;
    while (i + 1 < template.len) : (i += 1) {
        if (template[i] == '}' and template[i + 1] == '}') {
            return i + 2;
        }
    }
    @compileError("unclosed placeholder '{{' in template");
}

fn countPlaceholders(comptime template: []const u8) usize {
    var count: usize = 0;
    var i: usize = 0;
    while (i < template.len) {
        if (template[i] == '{') {
            if (i + 1 >= template.len or template[i + 1] != '{') {
                @compileError("single '{' must be escaped as '{{' in templates");
            }
            const close_index = findClosing(template, i + 2);
            count += 1;
            i = close_index;
            continue;
        } else if (template[i] == '}') {
            if (i + 1 < template.len and template[i + 1] == '}') {
                @compileError("unexpected '}}' without matching '{{'");
            }
        }
        i += 1;
    }
    return count;
}

fn trimWhitespace(comptime value: []const u8) []const u8 {
    var start: usize = 0;
    var end: usize = value.len;
    while (start < end and std.ascii.isWhitespace(value[start])) : (start += 1) {}
    while (end > start and std.ascii.isWhitespace(value[end - 1])) : (end -= 1) {}
    return value[start..end];
}

fn splitTemplate(
    comptime template: []const u8,
    comptime placeholder_count: usize,
) [placeholder_count + 1][]const u8 {
    var parts: [placeholder_count + 1][]const u8 = undefined;
    var part_index: usize = 0;
    var last_index: usize = 0;
    var i: usize = 0;
    while (i < template.len) {
        if (template[i] == '{' and i + 1 < template.len and template[i + 1] == '{') {
            parts[part_index] = template[last_index..i];
            part_index += 1;
            const close_index = findClosing(template, i + 2);
            last_index = close_index;
            i = close_index;
            continue;
        }
        if (template[i] == '}' and i + 1 < template.len and template[i + 1] == '}') {
            @compileError("unexpected '}}' without matching '{{'");
        }
        i += 1;
    }
    parts[part_index] = template[last_index..];
    return parts;
}

fn extractPlaceholders(
    comptime template: []const u8,
    comptime placeholder_count: usize,
) [placeholder_count][]const u8 {
    var placeholders: [placeholder_count][]const u8 = undefined;
    var index: usize = 0;
    var i: usize = 0;
    while (i < template.len) {
        if (template[i] == '{' and i + 1 < template.len and template[i + 1] == '{') {
            const close_index = findClosing(template, i + 2);
            const raw = template[(i + 2)..(close_index - 2)];
            placeholders[index] = trimWhitespace(raw);
            index += 1;
            i = close_index;
            continue;
        }
        if (template[i] == '}' and i + 1 < template.len and template[i + 1] == '}') {
            @compileError("unexpected '}}' without matching '{{'");
        }
        i += 1;
    }
    return placeholders;
}

pub fn compileTemplate(comptime template: []const u8) TemplatePlan {
    const placeholders = comptime countPlaceholders(template);
    const static_parts = comptime splitTemplate(template, placeholders);
    const exprs = comptime extractPlaceholders(template, placeholders);
    return .{
        .static_parts = &static_parts,
        .placeholders = &exprs,
    };
}

pub fn render(
    plan: TemplatePlan,
    allocator: std.mem.Allocator,
    values: []const []const u8,
) TemplateError![]u8 {
    if (values.len != plan.placeholderCount()) return TemplateError.MismatchedValues;

    var total: usize = 0;
    for (plan.static_parts) |part| total += part.len;
    for (values) |value| total += value.len;

    const buffer = try allocator.alloc(u8, total);
    var offset: usize = 0;
    for (plan.static_parts, 0..) |part, idx| {
        std.mem.copyForwards(u8, buffer[offset..][0..part.len], part);
        offset += part.len;
        if (idx < values.len) {
            const value = values[idx];
            std.mem.copyForwards(u8, buffer[offset..][0..value.len], value);
            offset += value.len;
        }
    }

    return buffer;
}
