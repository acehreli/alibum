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
import std.zip;

pragma(lib, "MagickWand");

enum size_t pictureSize = 800;
enum size_t thumbnailSize = 64;
enum size_t cellWidth = thumbnailSize + 4;
enum size_t cellHeight = cellWidth;

enum size_t compressionQuality = 70;
enum size_t zipFileSizeLimit = 100 * 1024 * 1024;

enum size_t thumbnailForward = pictureSize / thumbnailSize / 2 - 1;
enum size_t thumbnailBackward = thumbnailForward;

enum string[] imageExtensions = [ ".JPG", ".jpg", ".jpeg" ];
enum string zipFileNameTemplate = format("%spx_pictures_%%s.zip", pictureSize);
enum string originalsZipFileNameTemplate = "original_pictures_%s.zip";

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
            height = (width * ratio).to!ulong;
            toReturn = height;

        } else {
            height = size;
            width = (height / ratio).to!ulong;
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

        return propertyValue_raw.to!string;
    }
}

struct OutputInfo
{
    string originalFilePath;
    string processedFilePath;
    string dateTimeOriginal;
}

string thumbnailName(string fileName)
{
    string ext = fileName.extension;
    string base = fileName.baseName(ext);
    return format("%s.thumb%s", base, ext);
}

shared string g_outputDir;

OutputInfo processImage(string filePath)
{
    writefln("Processing %s", filePath);

    auto image = Image(filePath);
    auto dateTimeOriginal = image.getProperty("exif:DateTimeOriginal");

    image.resize(pictureSize);
    const pictName = format("./%s/%s", g_outputDir, filePath.baseName);
    writefln("Writing %s", pictName);
    image.write(pictName);

    image.resize(thumbnailSize);
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
                                              .processedFilePath),
                              previousPageText)));

    } else {
        row.add(new TableCell([ "align" : "center",
                                "bgcolor" : padColor ]));
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
            row.add(new TableCell([ "align" : "center",
                                    "bgcolor" : linkBgColor ])
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

        row.add(new TableCell([ "align" : "center",
                                "bgcolor" : linkBgColor ])
                    .add(makeLink(pictureFileName(pictures[nextPageIndex]
                                                  .processedFilePath),
                                  nextPageText)));
    } else {
        row.add(new TableCell([ "align" : "center",
                                "bgcolor" : padColor ]));
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

string fileSizeText(const size_t originalSize)
{
    enum denoms = [ " bytes", "K", "M", "G" ];

    size_t size = originalSize;

    foreach (denom; denoms) {
        if (size < 1024) {
            return format("%s%s", size, denom);

        } else {
            size /= 1024;
        }
    }

    return format("%s bytes", originalSize);
}

struct ZipFileInfo
{
    string fileName;
    size_t fileCount;
}

string zipFileText(ZipFileInfo zipFile)
{
    return format("%s&nbsp;(%s&nbsp;files,&nbsp;%s)",
                  makeLink(zipFile.fileName.baseName),
                  zipFile.fileCount,
                  fileSizeText(zipFile.fileName.getSize));
}

XmlElement makeZipLinkRow(ZipFileInfo[] zipFiles)
{
    string downLoadText = format("Downloads: %s%-(%s%)",
                                 new Break,
                                 zipFiles
                                 .sort!((a, b) => a.fileName < b.fileName)
                                 .map!(a => format("%s%s",
                                                   zipFileText(a), new Break)));

    return (new TableRow)
        .add([ new TableCell([ "align" : "center" ])
               .add(downLoadText) ]);
}

XmlElement makePictureTable(OutputInfo outputInfo, XmlElement zipLinkRow)
{
    return (new Table).add(
        [ makePictureRow(outputInfo.processedFilePath),
          makePictureDateTimeRow(outputInfo.dateTimeOriginal),
          zipLinkRow ]);
}

XmlElement[] makePageFooter()
{
    return [ new Hr,
             new Paragraph()
             .add(makeLink("https://github.com/acehreli/alibum", "alibum"))
             .add(" • Ali Çehreli") ];
}

void makeHtmlPages(OutputInfo[] pictures,
                   string outputDir,
                   ZipFileInfo[] zipFiles)
{
    auto zipLinkRow = makeZipLinkRow(zipFiles);

    foreach (i, picture; pictures.parallel) {
        auto docBody = (new Body).add(([ makeThumbnailStrip(pictures, i),
                                         makePictureTable(picture, zipLinkRow) ]
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

ZipFileInfo[] makeZipArchive(string[] filePaths, string zipFilePathTemplate)
{
    ZipFileInfo[] result;

    for (size_t zipFileCount = 0; !filePaths.empty; ++zipFileCount) {
        auto archive = new ZipArchive;
        size_t fileCount = 0;

        for (size_t archiveSize = 0;
             !filePaths.empty && (archiveSize < zipFileSizeLimit);
             filePaths.popFront()) {

            const filePath = filePaths.front;
            auto fileContent = read(filePath);
            auto archiveMember = new ArchiveMember();
            archiveMember.name = filePath.baseName;
            archiveMember.expandedData = cast(ubyte[])fileContent;

            archive.addMember(archiveMember);

            archiveSize += filePath.getSize();
            ++fileCount;
        }

        const zipFilePath = format(zipFilePathTemplate, zipFileCount + 1);

        writefln("Creating %s", zipFilePath);
        archive.build();

        writefln("Writing %s", zipFilePath);
        std.file.write(zipFilePath, archive.data);

        result ~= ZipFileInfo(zipFilePath, fileCount);
    }

    return result;
}

void printUsage(string[] args)
{
    const progName = baseName(args[0]);

    stderr.writefln("Usage  : %s <input-directory> <url-prefix>", progName);
    stderr.writeln();
    stderr.writefln("Example: %s ~/Pictures/birthday /photo/bday", progName);
}

void makeAlbum(string inputDir, string outputDir)
{
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

    ZipFileInfo[] zipFiles;

    zipFiles ~=
        makeZipArchive(pictures
                       .map!(a => format("./%s", a.processedFilePath))
                       .array,
                       format("./%s/%s", outputDir, zipFileNameTemplate));

    zipFiles ~=
        makeZipArchive(pictures
                       .map!(a => a.originalFilePath)
                       .array,
                       format("./%s/%s", outputDir,
                              originalsZipFileNameTemplate));

    makeHtmlPages(pictures, outputDir, zipFiles);
}

int main(string[] args)
{
    int status = 0;

    if (args.length != 3) {
        printUsage(args);
        status = 1;

    } else {
        string inputDir = args[1];
        string outputDir = args[2];

        MagickWandGenesis();
        scope (exit) MagickWandTerminus();

        if (format("./%s", outputDir).exists) {
            stderr.writefln("Error: ./%s already exists", outputDir);
            status = 1;

        } else {
            makeAlbum(inputDir, outputDir);
        }
    }

    return status;
}
