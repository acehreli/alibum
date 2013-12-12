module magickwand;

extern (C) {

struct MagickWand;

enum MagickBooleanType : int
{
  MagickFalse = 0,
  MagickTrue = 1
}

enum FilterTypes
{
  UndefinedFilter,
  PointFilter,
  BoxFilter,
  TriangleFilter,
  HermiteFilter,
  HanningFilter,
  HammingFilter,
  BlackmanFilter,
  GaussianFilter,
  QuadraticFilter,
  CubicFilter,
  CatromFilter,
  MitchellFilter,
  LanczosFilter,
  BesselFilter,
  SincFilter,
  KaiserFilter,
  WelshFilter,
  ParzenFilter,
  LagrangeFilter,
  BohmanFilter,
  BartlettFilter,
  SentinelFilter  /* a count of all the filters, not a real filter */
}

MagickWand *DestroyMagickWand(MagickWand *);
MagickBooleanType MagickWriteImages(MagickWand *,
                                    const char *,const MagickBooleanType);
MagickBooleanType MagickResizeImage(MagickWand *, const ulong,const ulong,
                                    const FilterTypes,const double);
MagickBooleanType MagickAdaptiveResizeImage(MagickWand *wand,
                                            const size_t columns,
                                            const size_t rows);
MagickBooleanType MagickNextImage(MagickWand *);
void MagickResetIterator(MagickWand *);
MagickWand *NewMagickWand();
void MagickWandGenesis();
void MagickWandTerminus();
MagickBooleanType MagickReadImage(MagickWand *,const char *);

ulong MagickGetImageWidth(MagickWand *);
ulong MagickGetImageHeight(MagickWand *);
char *MagickGetImageProperty(MagickWand *,const char *);
char **MagickGetImageProperties(MagickWand *,const char *,ulong *);
void *MagickRelinquishMemory(void *);
MagickBooleanType MagickSetImageProperty(MagickWand *,
                                         const char *,const char *);
MagickBooleanType MagickThumbnailImage(MagickWand *wand,
                                       const size_t columns,const size_t rows);

MagickWand *CloneMagickWand(const MagickWand *);
MagickBooleanType IsMagickWand(const MagickWand *);

enum CompressionType
{
  UndefinedCompression,
  NoCompression,
  BZipCompression,
  DXT1Compression,
  DXT3Compression,
  DXT5Compression,
  FaxCompression,
  Group4Compression,
  JPEGCompression,
  JPEG2000Compression,
  LosslessJPEGCompression,
  LZWCompression,
  RLECompression,
  ZipCompression
}

CompressionType MagickGetImageCompression(MagickWand *wand);
size_t MagickGetImageCompressionQuality(MagickWand *wand);
MagickBooleanType MagickSetImageCompressionQuality(MagickWand *wand,
                                                   const size_t quality);

alias ssize_t = long;

MagickBooleanType MagickCropImage(MagickWand *wand,
                                  const size_t width,
                                  const size_t height,
                                  const ssize_t x,
                                  const ssize_t y);

} /* extern (C) */
