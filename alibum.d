/*
 * This module implements a minimalistic web picture album.
 */

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
import std.datetime;

pragma(lib, "MagickWand");

enum size_t thumbnailSize = 64;
enum size_t thumbnailCompressionQuality = 50;

enum size_t pictureLongEdgeSize = 960;
enum size_t pictureCompressionQuality = 85;

// The number of available thumbnails for pictures after the current picture
enum size_t thumbnailForward = pictureLongEdgeSize / thumbnailSize / 2;

// The number of available thumbnails for pictures before the current picture
enum size_t thumbnailBackward = thumbnailForward;

enum string[] supportedImageExtensions = [ ".JPG", ".jpg", ".jpeg" ];

enum string previousPictureText = "&lt;";
enum string nextPictureText = "&gt;";
enum string previousPageText = "&lt;&lt;";
enum string nextPageText = "&gt;&gt;";
enum string padColor = "#eeeeee";

enum tableCellStyle = CssStyleValue(
    "td",
    [ "width" : format("%spx", thumbnailSize),
      "height" : format("%spx", thumbnailSize),
      "padding" : "0px 0px 0px 0px",
      "border" : "0px",
      "margin" : "0px 0px 0px 0px",
      "vertical-align" : "center" ]);

enum mainPictureCellStyle = CssStyleValue(
    "td.main",
    [ "width" : format("%spx", pictureLongEdgeSize) ]);

enum arrowCellStyle = CssStyleValue(
    "td.arrow",
    [ "font-size" : format("%spx", thumbnailSize / 2) ]);

/* Represents an image file that is managed by ImageMagick's MagickWand. */
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

    /* Resize the image with the provided compression quality. */
    void resize(ulong size, size_t compressionQuality)
    {
        auto status =
            MagickSetImageCompressionQuality(wand, compressionQuality);
        enforce(status == MagickBooleanType.MagickTrue);

        const imageHeight = MagickGetImageHeight(wand).to!double;
        const imageWidth = MagickGetImageWidth(wand).to!double;
        const double ratio = imageHeight / imageWidth;

        ulong width;
        ulong height;

        if (imageHeight < imageWidth) {
            width = size;
            height = (width * ratio).to!ulong;

        } else {
            height = size;
            width = (height / ratio).to!ulong;
        }

        // Now resize the image
        status = MagickThumbnailImage(wand, width, height);
        enforce(status == MagickBooleanType.MagickTrue);
    }

    /* Convert the image to a thumbnail. */
    void thumbnail(ulong size)
    {
        auto status =
            MagickSetImageCompressionQuality(wand, thumbnailCompressionQuality);
        enforce(status == MagickBooleanType.MagickTrue);

        const imageHeight = MagickGetImageHeight(wand);
        const imageWidth = MagickGetImageWidth(wand);

        // First crop the center square of the image
        if (imageHeight < imageWidth) {
            status = MagickCropImage(wand, imageHeight, imageHeight,
                                     (imageWidth - imageHeight) / 2, 0);
            enforce(status == MagickBooleanType.MagickTrue);

        } else {
            status = MagickCropImage(wand, imageWidth, imageWidth,
                                     0, (imageHeight - imageWidth) / 2);
            enforce(status == MagickBooleanType.MagickTrue);
        }

        // Now resize the image
        status = MagickThumbnailImage(wand, thumbnailSize, thumbnailSize);
        enforce(status == MagickBooleanType.MagickTrue);
    }

    /* Write the image to disk. */
    void write(string fileName)
    {
        auto status = MagickWriteImages(
            wand, fileName.toStringz, MagickBooleanType.MagickTrue);
        enforce(status == MagickBooleanType.MagickTrue);
    }

    /* Return the provided property of the image. */
    string getProperty(string propertyName)
    {
        char * propertyValue_raw =
            MagickGetImageProperty(wand, propertyName.toStringz);
        scope (exit) MagickRelinquishMemory(propertyValue_raw);

        return propertyValue_raw.to!string;
    }
}

/* A collection of useful information useful post-processing of images. */
struct OutputInfo
{
    string originalFilePath;
    string processedFilePath;
    string dateTimeOriginal;
}

/* Returns the name of the thumbnail of the image. */
string thumbnailName(string fileName)
{
    string ext = fileName.extension;
    string base = fileName.baseName(ext);
    return format("%s.thumb%s", base, ext);
}

unittest
{
    assert(thumbnailName("/foo/bar/xyz.jpg") == "xyz.thumb.jpg");
}

/* This is a workaround for not being able to use the local variable
 * makeAlbum.outputDir when calling taskPool.map. The compiler says:
 *
 * "template instance map!((a) => processImage(a, outputDir)) cannot use local
 * '__lambda5(__T4)(a)' as parameter to non-global template
 * map(functions...)"
 */
shared string g_outputDir;

OutputInfo processImage(string filePath)
{
    writefln("Processing %s", filePath);

    auto image = Image(filePath);
    auto dateTimeOriginal = image.getProperty("exif:DateTimeOriginal");

    image.resize(pictureLongEdgeSize, pictureCompressionQuality);
    const pictName = format("./%s/%s", g_outputDir, filePath.baseName);
    writefln("Writing %s", pictName);
    image.write(pictName);

    image.thumbnail(thumbnailSize);
    const thumbnailName = format("./%s/%s",
                                 g_outputDir, thumbnailName(filePath));
    writefln("Writing %s", thumbnailName);
    image.write(thumbnailName);

    return OutputInfo(filePath,
                      format("%s/%s", g_outputDir, filePath.baseName),
                      dateTimeOriginal);
}

TableCell paddingCell()
{
    return new TableCell([ "bgcolor" : padColor ]);
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

        row.add(new TableCell([ "class" : "arrow",
                                "align" : "center",
                                "bgcolor" : padColor ])
                .add(makeLink(pictureFileName(pictures[previousPageIndex]
                                              .processedFilePath),
                              previousPageText)));

    } else {
        row.add(paddingCell());
    }

    foreach (_; padBefore) {
        row.add(paddingCell());
    }

    foreach (i; beg .. end) {
        if (i == index) {
            row.add(new TableCell([ "align" : "center" ])
                    .add(new Span([ "style" : "opacity:0.5;" ])
                         .add(makeImg(thumbnailName(pictures[i]
                                                    .processedFilePath)))));

        } else {
            row.add(new TableCell([ "align" : "center" ])
                    .add(new Link([ "href" :
                                    pictureFileName(pictures[i]
                                                    .processedFilePath) ])
                         .add(makeImg(thumbnailName(pictures[i]
                                                    .processedFilePath)))));
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

        row.add(new TableCell([ "class" : "arrow",
                                "align" : "center",
                                "bgcolor" : padColor ])
                    .add(makeLink(pictureFileName(pictures[nextPageIndex]
                                                  .processedFilePath),
                                  nextPageText)));
    } else {
        row.add(paddingCell());
    }

    auto table = (new Table).add(row);

    return table;
}

XmlElement makePictureRow(string picturePath, OutputInfo prev, OutputInfo next)
{
    return (new TableRow)
        .add(new TableCell([ "class" : "arrow",
                             "align" : "center",
                             "valign" : "top" ])
             .add(prev.processedFilePath.empty
                  ? ""
                  : makeLink(prev.processedFilePath.pictureFileName,
                             previousPictureText)
                  .text))
        .add(new TableCell([ "class" : "main", "align" : "center" ])
             .add(makeImg(picturePath.baseName)))
        .add(new TableCell([ "class" : "arrow",
                             "align" : "center",
                             "valign" : "top" ])
             .add(next.processedFilePath.empty
                  ? ""
                  : makeLink(next.processedFilePath.pictureFileName,
                             nextPictureText)
                  .text));
}

XmlElement makePictureDateTimeRow(string dateTimeOriginal)
{
    return (new TableRow)
        .add(new TableCell())
        .add(new TableCell([ "align" : "center" ]).add(dateTimeOriginal))
        .add(new TableCell());
}

XmlElement makePictureTable(OutputInfo picture,
                            OutputInfo prev,
                            OutputInfo next)
{
    return (new Table).add(
        [ makePictureRow(picture.processedFilePath, prev, next),
          makePictureDateTimeRow(picture.dateTimeOriginal) ]);
}

XmlElement[] makePageFooter()
{
    return [ new Hr,
             new Paragraph()
             .add(makeLink("https://github.com/acehreli/alibum", "alibum")) ];
}

void makeHtmlPages(OutputInfo[] pictures, string outputDir)
{
    foreach (i, picture; pictures.parallel) {
        const prev = (i > 0) ? pictures[i - 1] : OutputInfo.init;
        const next = (i < pictures.length - 1)
                     ? pictures[i + 1] : OutputInfo.init;

        auto docBody = (new Body).add(([ makeThumbnailStrip(pictures, i),
                                         makePictureTable(picture, prev, next) ]
                                       ~ makePageFooter())
                                      .centered);

        const pictureHtmlFileName =
            format(".%s", pictureHtml(picture.processedFilePath));
        auto file = File(pictureHtmlFileName, "w");

        auto doc = (new Document).add(
            (new Html).add([ (new Head).add(
                                   [ makeTitle(picture
                                               .processedFilePath.baseName),
                                     makeBase(outputDir ~ "/"),
                                     new Style([ "type" : "text/css" ])
                                     .add(tableCellStyle.text),

                                     new Style([ "type" : "text/css" ])
                                     .add(mainPictureCellStyle.text),

                                     new Style([ "type" : "text/css" ])
                                     .add(arrowCellStyle.text) ]),

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

    stderr.writefln("Usage  : %s <input-directory> <url-prefix>", progName);
    stderr.writeln();
    stderr.writefln("Example: %s ~/Pictures/birthday /photo/bday", progName);
}

size_t makeAlbum(string inputDir, string outputDir)
{
    writefln("Creating directory %s", outputDir);
    mkdirRecurse(format("./%s", outputDir));

    g_outputDir = outputDir;

    auto imageFiles = inputDir
                      .dirEntries(SpanMode.shallow)
                      .map!(a => a.name)
                      .filter!(a => supportedImageExtensions
                               .canFind(a.extension));

    auto pictures = taskPool.map!processImage(imageFiles).array;

    pictures.sort!((a, b) => (a.dateTimeOriginal < b.dateTimeOriginal));

    makeHtmlPages(pictures, outputDir);

    return pictures.length;
}

version (unittest)
{
} else {

int main(string[] args)
{
    int status = 0;

    if (args.length != 3) {
        printUsage(args);
        status = 1;

    } else {
        string outputDir = args[2];

        if (format("./%s", outputDir).exists) {
            stderr.writefln("Error: ./%s already exists", outputDir);
            status = 1;

        } else {
            MagickWandGenesis();
            scope (exit) MagickWandTerminus();

            StopWatch sw;
            sw.start();

            string inputDir = args[1];
            const totalFiles = makeAlbum(inputDir, outputDir);

            sw.stop();
            writefln("Made %s pages in %s seconds.",
                     totalFiles, sw.peek().seconds);
        }
    }

    return status;
}

} // version(unittest)
