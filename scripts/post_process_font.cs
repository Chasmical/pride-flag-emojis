using System.Text;
using System.Buffers.Binary;

if (args.Length != 2) {
    Console.WriteLine("[ERROR] Expected 2 arguments: merged-pre.ttf merged.ttf");
    Console.WriteLine($"Got {args.Length} arguments: {string.Join(" ", args.Select(x => $"\"{x}\""))}");
    Environment.Exit(1);
}

// This script inserts a non-standard table into the font, that just has ASCII text in it, so that
// if someone opens it in a text/hex editor they'll see some ASCII art with a link to this repo!

var dir = Path.GetDirectoryName(Directory.GetCurrentDirectory());
var noticeTextPath = Path.Join(dir, "notice.txt");
var noticeText = File.Exists(noticeTextPath) ? File.ReadAllLines(noticeTextPath).ToList() : null;

var fontPath = Path.Join(dir, args[0]); // merged-pre.ttf
var saveAs = Path.Join(dir, args[1]); // merged.ttf

// If you don't have /notice.txt in the repository, it won't change the font at all.
if (noticeText is null) {
    File.Copy(fontPath, saveAs, true);
    return;
}

MemoryStream font = new(File.ReadAllBytes(fontPath));

// First line specifies the table tag. Don't be too crazy, the code here is really naive.
var noticeName = noticeText[0];
noticeText.RemoveAt(0);

MemoryStream newFont = new();
using BigEndianReader reader = new(font, Encoding.UTF8, true);
using BigEndianWriter writer = new(newFont, Encoding.UTF8, true);

writer.Write(reader.ReadUInt32());
var numTables = reader.ReadUInt16();
var searchRange = reader.ReadUInt16();
var entrySelector = reader.ReadUInt16();
var rangeShift = reader.ReadUInt16();

var newNumTables = numTables + 1;
var newEntrySelector = Math.Floor(Math.Log2(newNumTables));
var newSearchRange = (int)Math.Pow(2, newEntrySelector) * 16;
var newRangeShift = newNumTables * 16 - newSearchRange;

writer.Write((ushort)newNumTables);
writer.Write((ushort)newSearchRange);
writer.Write((ushort)newEntrySelector);
writer.Write((ushort)newRangeShift);

var recordsStart = writer.BaseStream.Position;
var dataStart = recordsStart + 16 * newNumTables;

List<TableRecord> tables = [];
for (int i = 0; i < numTables; i++) {
    var table = new TableRecord() {
        tag = reader.ReadBytes(4),
        checksum = reader.ReadUInt32(),
        offset = reader.ReadUInt32(),
        length = reader.ReadUInt32(),
    };

    var prevPos = reader.BaseStream.Position;
    reader.BaseStream.Position = table.offset;
    table.data = reader.ReadBytes((int)table.length);
    reader.BaseStream.Position = prevPos;
    tables.Add(table);
}

TableRecord CreateNoticeTable() {
    var tag = Encoding.UTF8.GetBytes(noticeName);

    var dataList = Encoding.UTF8.GetBytes(string.Join('\n', noticeText)).ToList();
    while ((dataList.Count % 4) != 0) dataList.Add(0);
    var data = dataList.ToArray();

    uint checksum = 0;
    for (int i = 0; i < data.Length / 4; i++) {
        checksum += BinaryPrimitives.ReadUInt32BigEndian(data[(i * 4)..((i + 1) * 4)]);
    }

    return new TableRecord() { tag = tag, data = data, checksum = checksum, length = (uint)data.Length };
}

var noticeTable = CreateNoticeTable();

var tablesInOrderOfData = tables.ToList();
tablesInOrderOfData.Sort((a, b) => a.offset.CompareTo(b.offset));
tablesInOrderOfData.Insert(0, noticeTable);

writer.BaseStream.Position = dataStart;
foreach (var table in tablesInOrderOfData) {
    table.offset = (uint)writer.BaseStream.Position;
    writer.Write(table.data);
    while ((writer.BaseStream.Position % 4) != 0)
        writer.Write((byte)0);
}

writer.BaseStream.Position = recordsStart;
tables.Remove(noticeTable);
tables.Add(noticeTable);
foreach (var table in tables) {
    writer.Write(table.tag);
    writer.Write(table.checksum);
    writer.Write(table.offset);
    writer.Write(table.length);
}

font = newFont;

font.Position = 0;
File.WriteAllBytes(saveAs, font.ToArray());

class TableRecord {
    public byte[] tag = [];
    public uint checksum;
    public byte[] data = [];
    public uint offset;
    public uint length;
}

class BigEndianReader : BinaryReader {
    public BigEndianReader(Stream input) : base(input) {}
    public BigEndianReader(Stream input, Encoding encoding) : base(input, encoding) {}
    public BigEndianReader(Stream input, Encoding encoding, bool leaveOpen) : base(input, encoding, leaveOpen) {}

    public override ushort ReadUInt16() {
        Span<byte> buffer = stackalloc byte[2];
        if (Read(buffer) != buffer.Length) throw new Exception();
        return BinaryPrimitives.ReadUInt16BigEndian(buffer);
    }
    public override uint ReadUInt32() {
        Span<byte> buffer = stackalloc byte[4];
        if (Read(buffer) != buffer.Length) throw new Exception();
        return BinaryPrimitives.ReadUInt32BigEndian(buffer);
    }
}
class BigEndianWriter : BinaryWriter {
    public BigEndianWriter(Stream output) : base(output) {}
    public BigEndianWriter(Stream output, Encoding encoding) : base(output, encoding) {}
    public BigEndianWriter(Stream output, Encoding encoding, bool leaveOpen) : base(output, encoding, leaveOpen) {}

    public override void Write(ushort value) {
        Span<byte> buffer = stackalloc byte[2];
        BinaryPrimitives.WriteUInt16BigEndian(buffer, value);
        Write(buffer);
    }
    public override void Write(uint value) {
        Span<byte> buffer = stackalloc byte[4];
        BinaryPrimitives.WriteUInt32BigEndian(buffer, value);
        Write(buffer);
    }
}
