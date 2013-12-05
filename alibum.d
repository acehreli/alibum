module alibum;

import magickwand;
import html;

import std.exception;
import std.string;
import std.file;
import std.stdio;
import std.path;
import std.parallelism;
import std.conv;
import std.array;
import std.algorithm;
import std.range;

pragma(lib, "MagickWand");

enum size_t pictureSize = 1024;
enum size_t thumbnailSize = 64;
enum size_t thumbnailForward = pictureSize / thumbnailSize / 2 - 1;
enum size_t thumbnailBackward = thumbnailForward;
enum string imageExt = ".JPG";
enum size_t compressionQuality = 70;

enum size_t cellWidth = thumbnailSize + 4;
enum size_t cellHeight = cellWidth;

enum string padColor = "#f0f0f0";
enum string linkBgColor = "#c0c0ff";
enum string tableCellStyle = format("td { width:%spx; height:%spx;" ~
                                    " padding:4px 0px 0px 0px; border:0px;" ~
                                    " margin:0px; vertical-align:center; }",
                                    cellWidth, cellHeight);

struct Image
{
    MagickWand *wand;

    this(string fileName)
    {
        this.wand = NewMagickWand();
        enforce(this.wand);
        scope (failure) cleanup();

        auto status = MagickReadImage(wand, fileName.toStringz);
        if (status != MagickBooleanType.MagickTrue) {
            throw new Exception(format("Failed to open %s", fileName));
        }
    }

    this(this)
    {
        wand = CloneMagickWand(wand);
    }

    void cleanup()
    {
        if (IsMagickWand(wand) == MagickBooleanType.MagickTrue) {
            wand = DestroyMagickWand(wand);
            enforce(wand is null);
        }
    }

    ~this()
    {
        cleanup();
    }

    /* Returns the calculated (shorter) size. */
    size_t resize(ulong size)
    {
        const imageHeight = MagickGetImageHeight(wand).to!double;
        const imageWidth = MagickGetImageWidth(wand).to!double;
        ulong width;
        ulong height;
        ulong toReturn;

        const double ratio = imageHeight / imageWidth;

        if (imageHeight < imageWidth) {
            width = size;
            height = cast(ulong)(width * ratio);
            toReturn = height;

        } else {
            height = size;
            width = cast(ulong)(height / ratio);
            toReturn = width;
        }

        auto status =
            MagickSetImageCompressionQuality(wand, compressionQuality);
        enforce(status == MagickBooleanType.MagickTrue);

        MagickThumbnailImage(wand, width, height);
            // MagickResizeImage(wand, width, height,
            //                   FilterTypes.LanczosFilter, 1.0);
            // MagickAdaptiveResizeImage(wand, width, height);

        return toReturn;
    }

    void write(string fileName)
    {
        auto status = MagickWriteImages(
            wand, fileName.toStringz, MagickBooleanType.MagickTrue);
        enforce(status == MagickBooleanType.MagickTrue);
    }

    string getProperty(string propertyName)
    {
        char * propertyValue_raw =
            MagickGetImageProperty(wand, propertyName.toStringz);
        scope (exit) MagickRelinquishMemory(propertyValue_raw);
        auto propertyValue = propertyValue_raw.to!string;
        return propertyValue;
    }
}

struct OutputInfo
{
    string fileName;
    string dateTimeOriginal;
}

string pictureName(string fileName)
{
    string ext = fileName.extension;
    string base = fileName.baseName(ext);
    return format("%s%s", base, ext);
}

string thumbnailName(string fileName)
{
    string ext = fileName.extension;
    string base = fileName.baseName(ext);
    return format("%s.thumb%s", base, ext);
}

shared string g_outputDir;

OutputInfo processImage(string fileName)
{
    writefln("Processing %s", fileName);

    auto image = Image(fileName);
    auto dateTimeOriginal = image.getProperty("exif:DateTimeOriginal");

    image.resize(pictureSize);
    const pictName = format("./%s/%s", g_outputDir, pictureName(fileName));
    writefln("Writing %s", pictName);
    image.write(pictName);

    image.resize(thumbnailSize);
    const thumbnailName = format("./%s/%s",
                                 g_outputDir, thumbnailName(fileName));
    writefln("Writing %s", thumbnailName);
    image.write(thumbnailName);


    return OutputInfo(format("%s/%s", g_outputDir, pictureName(fileName)),
                      dateTimeOriginal);
}

TableCell paddingCell()
{
    return new TableCell([ "align" : "center", "bgcolor" : padColor ]);
}

string pictureHtml(string fileName)
{
    auto result = fileName.findSplit(imageExt);
    return format("%s%s", result[0], ".html");
}

Table makeThumbnailStrip(OutputInfo[] pictures, size_t index)
{
    size_t beg = index - thumbnailBackward;
    size_t end = index + thumbnailForward + 1;
    OutputInfo[] padBefore;
    OutputInfo[] padAfter;

    if (index < thumbnailBackward) {
        padBefore.length = thumbnailBackward - index;
        beg = 0;
    }

    if (end > pictures.length) {
        // Order matters here
        padAfter.length = end - pictures.length;
        end = pictures.length;
    }

    auto row = new TableRow;

    foreach (_; padBefore) {
        row.add(paddingCell());
    }

    foreach (i; beg .. end) {
        if (i == index) {
            auto cell = new TableCell([ "align" : "center" ]);

            auto img = makeImg(thumbnailName(pictures[i].fileName));
            auto span = new Span([ "style" : "opacity:0.5;" ]);
            span.add(img);
            cell.add(span);
            row.add(cell);
        } else {
            auto cell = new TableCell([ "align" : "center",
                                        "bgcolor" : linkBgColor ]);
            cell.add(
                makeLink(pictureHtml(pictures[i].fileName),
                         makeImg(thumbnailName(pictures[i].fileName)).text));
            row.add(cell);
        }
    }

    foreach (_; padAfter) {
        row.add(paddingCell());
    }

    auto table = new Table;
    table.add(row);

    return table;
}

TableRow makePictureRow(string fileName)
{
    auto cell = new TableCell([ "align" : "center" ]);
    cell.add(makeImg(fileName));

    auto row = new TableRow;
    row.add(cell);

    return row;
}

TableRow makePictureDateTimeRow(string dateTimeOriginal)
{
    auto cell = new TableCell([ "align" : "center" ]);
    cell.add(dateTimeOriginal);

    auto row = new TableRow;
    row.add(cell);

    return row;
}

Table makePictureTable(OutputInfo outputInfo)
{
    auto table = new Table;

    table.add(makePictureRow(outputInfo.fileName));
    table.add(makePictureDateTimeRow(outputInfo.dateTimeOriginal));

    return table;
}

void makePages(OutputInfo[] pictures)
{
    foreach (i, picture; pictures.parallel) {
        auto docBody = new Body;
        docBody.add([ makeThumbnailStrip(pictures, i),
                      makePictureTable(picture)].centered);

        const pictureHtmlFileName =
            format(".%s", pictureHtml(picture.fileName));
        auto file = File(pictureHtmlFileName, "w");

        auto style = new Style;
        style.add(tableCellStyle);
        auto head = new Head;
        head.add(style);
        auto html = new Html;
        html.add([ head, cast(XmlElement)docBody ]);
        auto doc = new Document(html);

        writefln("Writing %s", pictureHtmlFileName);
        file.writeln(doc);

        if (i == 0) {
            file.close;
            auto indexFile = format("%s/index.html",
                                    pictureHtmlFileName.dirName);
            writefln("Copying %s", indexFile);
            std.file.copy(pictureHtmlFileName, indexFile);
        }
    }
}

void printUsage(string[] args)
{
    const progName = baseName(args[0]);

    writefln("Usage  : %s <input-directory> <url-prefix>", progName);
    writeln();
    writefln("Example: %s ~/Pictures/birthday /photo/bday", progName);
}

int main(string[] args)
{
    if (args.length != 3) {
        printUsage(args);
        return 1;
    }

    string inputDir = args[1];
    string outputDir = args[2];

    MagickWandGenesis();
    scope (exit) MagickWandTerminus();

    writefln("Creating directory %s", outputDir);
    mkdirRecurse(format("./%s", outputDir));

    g_outputDir = outputDir;

    auto imageFiles = inputDir
                      .dirEntries(SpanMode.shallow)
                      .map!(a => a.name)
                      .filter!(a => a.endsWith(imageExt));

    auto pictures = taskPool.map!processImage(imageFiles)
                    .array;

    pictures.sort!((a, b) => (a.dateTimeOriginal < b.dateTimeOriginal));

    makePages(pictures);

    return 0;
}
