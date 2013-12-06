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

enum size_t pictureSize = 800;
enum size_t thumbnailSize = 64;
enum size_t thumbnailForward = pictureSize / thumbnailSize / 2 - 1;
enum size_t thumbnailBackward = thumbnailForward;
enum string[] imageExtensions = [ ".JPG", ".jpg", ".jpeg" ];
enum size_t compressionQuality = 70;

enum size_t cellWidth = thumbnailSize + 4;
enum size_t cellHeight = cellWidth;

enum string previousPageText = "prev. page";
enum string nextPageText = "next page";
enum string padColor = "#eeeeee";
enum string linkBgColor = "#aaaaff";
enum tableCellStyle = CssStyleValue(
    "td",
    [ "width" : format("%spx", cellWidth),
      "height" : format("%spx", cellHeight),
      "padding" : "4px 0px 0px 0px",
      "border" : "0px",
      "margin" : "0px",
      "vertical-align" : "center" ]);

enum fontStyle = CssStyleValue(
    "body",
    [ "font-size" : format("%spx", thumbnailSize / 4) ]);

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
    string filePath;
    string dateTimeOriginal;
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
    const pictName = format("./%s/%s", g_outputDir, fileName.baseName);
    writefln("Writing %s", pictName);
    image.write(pictName);

    image.resize(thumbnailSize);
    const thumbnailName = format("./%s/%s",
                                 g_outputDir, thumbnailName(fileName));
    writefln("Writing %s", thumbnailName);
    image.write(thumbnailName);


    return OutputInfo(format("%s/%s", g_outputDir, fileName.baseName),
                      dateTimeOriginal);
}

TableCell paddingCell()
{
    return new TableCell([ "align" : "center", "bgcolor" : padColor ]);
}

string pictureFileName(string filePath)
{
    string ext = filePath.extension;
    string base = filePath.baseName(ext);
    return format("%s%s", base, ".html");
}

string pictureHtml(string filePath)
{
    string ext = filePath.extension;
    string base = filePath.baseName(ext);
    return format("%s/%s%s", filePath.dirName, base, ".html");
}

XmlElement makeThumbnailStrip(OutputInfo[] pictures, size_t index)
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

    if (beg > 0) {
        // There is a previous page
        const pageSize = thumbnailBackward + 1;
        size_t previousPageIndex = beg;

        if (previousPageIndex >= pageSize) {
            previousPageIndex -= pageSize;

        } else {
            previousPageIndex = 0;
        }

        row.add(new TableCell([ "align" : "center",
                                "bgcolor" : linkBgColor ])
                .add(makeLink(pictureFileName(pictures[previousPageIndex]
                                              .filePath),
                              previousPageText)));

    } else {
        row.add(new TableCell([ "align" : "center",
                                "bgcolor" : padColor ])
                .add(previousPageText));
    }

    foreach (_; padBefore) {
        row.add(paddingCell());
    }

    foreach (i; beg .. end) {
        if (i == index) {
            row.add(new TableCell([ "align" : "center" ])
                    .add(new Span([ "style" : "opacity:0.5;" ])
                         .add(makeImg(thumbnailName(pictures[i].filePath)))));

        } else {
            row.add(new TableCell([ "align" : "center",
                                    "bgcolor" : linkBgColor ])
                    .add(new Link([ "href" :
                                    pictureFileName(pictures[i].filePath) ])
                         .add(makeImg(thumbnailName(pictures[i].filePath)))));
        }
    }

    foreach (_; padAfter) {
        row.add(paddingCell());
    }

    if (end < pictures.length) {
        // There is a next page
        const pageSize = thumbnailBackward + 1;
        size_t nextPageIndex = end + thumbnailForward;

        if (nextPageIndex >= pictures.length) {
            nextPageIndex = pictures.length - 1;
        }

        row.add(new TableCell([ "align" : "center",
                                "bgcolor" : linkBgColor ])
                    .add(makeLink(pictureFileName(pictures[nextPageIndex]
                                                  .filePath),
                                  nextPageText)));
    } else {
        row.add(new TableCell([ "align" : "center",
                                "bgcolor" : padColor ])
                .add(nextPageText));
    }

    auto table = (new Table).add(row);

    return table;
}

XmlElement makePictureRow(string filePath)
{
    return (new TableRow).add(new TableCell([ "align" : "center" ])
                              .add(makeImg(filePath.baseName)));
}

XmlElement makePictureDateTimeRow(string dateTimeOriginal)
{
    return (new TableRow).add(new TableCell([ "align" : "center" ])
                              .add(dateTimeOriginal));
}

XmlElement makePictureTable(OutputInfo outputInfo)
{
    return (new Table).add(
        [ makePictureRow(outputInfo.filePath),
          makePictureDateTimeRow(outputInfo.dateTimeOriginal) ]);
}

void makeHtmlPages(OutputInfo[] pictures, string outputDir)
{
    foreach (i, picture; pictures.parallel) {
        auto docBody = (new Body).add([ makeThumbnailStrip(pictures, i),
                                        makePictureTable(picture)].centered);

        const pictureHtmlFileName =
            format(".%s", pictureHtml(picture.filePath));
        auto file = File(pictureHtmlFileName, "w");

        auto doc = (new Document).add(
            (new Html).add([ (new Head).add(
                                   [ makeTitle(picture.filePath.baseName),
                                     makeBase(outputDir ~ "/"),
                                     new Style([ "type" : "text/css" ])
                                     .add(tableCellStyle.to!string),
                                     new Style([ "type" : "text/css" ])
                                     .add(fontStyle.to!string) ]),

                             docBody ]));

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
                      .filter!(a => imageExtensions.canFind(a.extension));

    auto pictures = taskPool.map!processImage(imageFiles)
                    .array;

    pictures.sort!((a, b) => (a.dateTimeOriginal < b.dateTimeOriginal));

    makeHtmlPages(pictures, outputDir);

    return 0;
}
